import { expect } from "chai"
import { ethers } from "hardhat"
// already imported by hardhat.config.ts; re-importing just reuses the module for its helper
import { deployPoseidon2 } from "../tasks/deploy-imt-poseidon2-test"

// FatIMTReadableEvent is the base for a tree that keeps no `leaves` array: every node, the leaves
// included, lives in the `nodes` mapping. So `getFatLeaves` here is level 0 of `getFatNodes`, and
// there is no base-slot reader to offer — nothing is in consecutive slots. Same treeId-as-input
// contract as the storage variant, pinned down against a mapping of trees.
describe("FatIMTReadableEvent (multi-tree)", () => {
    const TREE_A = 1n
    const TREE_B = 2n
    const leavesA = [11n, 22n, 33n]
    const leavesB = [44n, 55n]

    async function deploy() {
        // poseidon2 hashes via a Yul contract at a fixed CREATE2 address rather than a linked library
        const [sender] = await ethers.getSigners()
        await deployPoseidon2(ethers.provider, sender)

        const Event = await (await ethers.getContractFactory("FatIMTPoseidon2WriteEvent", { libraries: {} })).deploy()
        const read = await (await ethers.getContractFactory("FatIMTPoseidon2Read", { libraries: {} })).deploy()

        const contract = await (
            await ethers.getContractFactory("FatIMTPoseidon2EventMultiTreeTest", {
                libraries: {
                    FatIMTPoseidon2WriteEvent: await Event.getAddress(),
                    FatIMTPoseidon2Read: await read.getAddress()
                }
            })
        ).deploy()

        await contract.init(TREE_A)
        await contract.init(TREE_B)
        await contract.insertMany(TREE_A, leavesA)
        await contract.insertMany(TREE_B, leavesB)
        return contract
    }

    // The leaves are read out of the nodes mapping rather than a leaves array, so this is the one
    // reader whose implementation differs from the storage variant's.
    it("Should read each tree's leaves off level 0 of the nodes mapping", async () => {
        const contract = await deploy()

        expect(await contract.getFatLeaves(TREE_A, 0, leavesA.length)).to.deep.equal(leavesA)
        expect(await contract.getFatLeaves(TREE_B, 0, leavesB.length)).to.deep.equal(leavesB)

        // a sub-range, to confirm [from, to) is honoured per tree
        expect(await contract.getFatLeaves(TREE_A, 1, 3)).to.deep.equal(leavesA.slice(1))

        // ...and it agrees with asking for level 0 directly
        expect(await contract.getFatNodes(TREE_A, 0, leavesA.length, 0)).to.deep.equal(leavesA)
    })

    it("Should read each tree's interior nodes independently", async () => {
        const contract = await deploy()

        // level 1 of tree A is hash(11,22) and the dangling 33 lifted as-is
        const level1 = await contract.getFatNodes(TREE_A, 0, 2, 1)
        expect(level1[1]).to.equal(leavesA[2])
        expect(level1[0]).to.not.equal(0n)

        // tree B is one level deep, and that level is its root
        expect((await contract.getFatNodes(TREE_B, 0, 1, 1))[0]).to.equal(await contract.root(TREE_B))
    })

    it("Should report each tree's own size and depth", async () => {
        const contract = await deploy()

        // 3 leaves need a depth-2 tree, 2 leaves only a depth-1 one
        expect(await contract.getFatSize(TREE_A)).to.equal(leavesA.length)
        expect(await contract.getFatDepth(TREE_A)).to.equal(2)
        expect(await contract.getFatSize(TREE_B)).to.equal(leavesB.length)
        expect(await contract.getFatDepth(TREE_B)).to.equal(1)
    })

    it("Should put the root at the top level getFatDepth points at", async () => {
        const contract = await deploy()

        for (const id of [TREE_A, TREE_B]) {
            const depth = await contract.getFatDepth(id)
            expect((await contract.getFatNodes(id, 0, 1, depth))[0]).to.equal(await contract.root(id))
        }
    })

    it("Should keep trees isolated when one is updated", async () => {
        const contract = await deploy()
        const rootBBefore = await contract.root(TREE_B)

        await contract.update(TREE_A, 99n, 0)

        expect(await contract.getFatLeaves(TREE_A, 0, 3)).to.deep.equal([99n, ...leavesA.slice(1)])
        expect(await contract.getFatLeaves(TREE_B, 0, 2)).to.deep.equal(leavesB)
        expect(await contract.root(TREE_B)).to.equal(rootBBefore)
    })

    // Size and depth are what bound a read, so a reset has to shrink them back or a client would go
    // on reading nodes the tree no longer claims.
    it("Should shrink the readable range back on reset", async () => {
        const contract = await deploy()

        await contract.reset(TREE_A)

        expect(await contract.getFatSize(TREE_A)).to.equal(0)
        expect(await contract.getFatDepth(TREE_A)).to.equal(0)
        await expect(contract.getFatLeaves(TREE_A, 0, 1)).to.be.revertedWithCustomError(contract, "EndIndexOutOfRange")

        // the other tree is untouched by the reset
        expect(await contract.getFatLeaves(TREE_B, 0, leavesB.length)).to.deep.equal(leavesB)
    })

    // An unwritten mapping key yields an all-zero struct, so without the guard these would quietly
    // report "empty tree" for a tree that doesn't exist.
    describe("uninitialized trees", () => {
        const UNKNOWN = 999n

        it("Should revert on every reader for a tree that was never initialized", async () => {
            const contract = await deploy()

            await expect(contract.getFatLeaves(UNKNOWN, 0, 1)).to.be.revertedWithCustomError(contract, "NotInitialized")
            await expect(contract.getFatNodes(UNKNOWN, 0, 1, 0)).to.be.revertedWithCustomError(
                contract,
                "NotInitialized"
            )
            await expect(contract.getFatSize(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
            await expect(contract.getFatDepth(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
        })

        it("Should distinguish an initialized-but-empty tree from a nonexistent one", async () => {
            const contract = await deploy()
            const EMPTY = 3n
            await contract.init(EMPTY)

            // initialized and empty: reads fine, returns nothing
            expect(await contract.getFatLeaves(EMPTY, 0, 0)).to.deep.equal([])
            expect(await contract.getFatSize(EMPTY)).to.equal(0)

            // nonexistent: rejected outright
            await expect(contract.getFatLeaves(UNKNOWN, 0, 0)).to.be.revertedWithCustomError(contract, "NotInitialized")
        })
    })
})
