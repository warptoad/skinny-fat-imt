import { expect } from "chai"
import { ethers } from "hardhat"
// already imported by hardhat.config.ts; re-importing just reuses the module for its helper
import { deployPoseidon2 } from "../tasks/deploy-imt-poseidon2-test"

// FatIMTFullNodeReadable takes the tree as an input (treeId -> `_tree`) rather than assuming a single
// tree at a fixed slot. These tests pin that down against a mapping layout, where every tree lives at
// a keccak-derived slot: the readers must stay per-tree, and `leavesBaseSlot` must point at the slot
// the skinnyfatJs lib would actually read from.
describe("FatIMTFullNodeReadable (multi-tree)", () => {
    const TREE_A = 1n
    const TREE_B = 2n
    const leavesA = [11n, 22n, 33n]
    const leavesB = [44n, 55n]

    async function deploy() {
        // poseidon2 hashes via a Yul contract at a fixed CREATE2 address rather than a linked library
        const [sender] = await ethers.getSigners()
        await deployPoseidon2(ethers.provider, sender)

        const fullNode = await (
            await ethers.getContractFactory("FatIMTPoseidon2WriteFullNode", { libraries: {} })
        ).deploy()

        // root() moved to the Read library, which MultiTreeTest now calls, so it must be linked too.
        const read = await (await ethers.getContractFactory("FatIMTPoseidon2Read", { libraries: {} })).deploy()

        const contract = await (
            await ethers.getContractFactory("FatIMTPoseidon2MultiTreeTest", {
                libraries: {
                    FatIMTPoseidon2WriteFullNode: await fullNode.getAddress(),
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

    it("Should read each tree's leaves independently", async () => {
        const contract = await deploy()

        expect(await contract.getLeaves(TREE_A, 0, leavesA.length)).to.deep.equal(leavesA)
        expect(await contract.getLeaves(TREE_B, 0, leavesB.length)).to.deep.equal(leavesB)

        // a sub-range, to confirm [from, to) is honoured per tree
        expect(await contract.getLeaves(TREE_A, 1, 3)).to.deep.equal(leavesA.slice(1))
    })

    it("Should clear a tree's leaves array on reset, then rebuild with no stale leaves", async () => {
        const contract = await deploy()

        expect(await contract.getLeaves(TREE_A, 0, leavesA.length)).to.deep.equal(leavesA)

        await contract.reset(TREE_A)
        expect(await contract.size(TREE_A)).to.equal(0)
        expect(await contract.getLeaves(TREE_A, 0, 0)).to.deep.equal([])

        // Re-insert FEWER, DIFFERENT leaves. If reset had not done `delete self.leaves`, the array
        // would still hold the old leaves at index 0..1 and this would read [11, 22], not [77, 88].
        await contract.insertMany(TREE_A, [77n, 88n])
        expect(await contract.size(TREE_A)).to.equal(2)
        expect(await contract.getLeaves(TREE_A, 0, 2)).to.deep.equal([77n, 88n])
        // the array is exactly length 2 now: reading past it reverts
        await expect(contract.getLeaves(TREE_A, 0, 3)).to.be.reverted

        // the other tree is untouched by the reset
        expect(await contract.getLeaves(TREE_B, 0, leavesB.length)).to.deep.equal(leavesB)
    })

    it("Should read each tree's nodes independently (level 0 == leaves)", async () => {
        const contract = await deploy()

        expect(await contract.getNodes(TREE_A, 0, leavesA.length, 0)).to.deep.equal(leavesA)
        expect(await contract.getNodes(TREE_B, 0, leavesB.length, 0)).to.deep.equal(leavesB)

        // level 1 of tree A is hash(11,22) and the dangling 33 lifted as-is
        const level1 = await contract.getNodes(TREE_A, 0, 2, 1)
        expect(level1[1]).to.equal(leavesA[2])
    })

    it("Should give each tree a distinct, non-zero leavesBaseSlot", async () => {
        const contract = await deploy()

        const slotA = await contract.leavesBaseSlot(TREE_A)
        const slotB = await contract.leavesBaseSlot(TREE_B)

        expect(slotA).to.not.equal(0n)
        expect(slotA).to.not.equal(slotB)
    })

    // The real contract with skinnyfatJs: the returned slot must be the `leaves` array header, so that
    // the array length is at that slot and element i is at keccak256(slot) + i. If the assembly read
    // the wrong pointer this passes nothing.
    it("Should return a slot whose storage actually holds the leaves array", async () => {
        const contract = await deploy()
        const address = await contract.getAddress()

        for (const [id, expected] of [
            [TREE_A, leavesA],
            [TREE_B, leavesB]
        ] as const) {
            const slot = await contract.leavesBaseSlot(id)

            // `leaves` is the first member of FatIMTDataFullNode, so the struct slot is the array header
            const length = await ethers.provider.getStorage(address, slot)
            expect(BigInt(length), `tree ${id} leaves.length`).to.equal(BigInt(expected.length))

            // elements live at keccak256(slot) + i
            const start = BigInt(ethers.keccak256(ethers.toBeHex(slot, 32)))
            for (let i = 0; i < expected.length; i++) {
                const raw = await ethers.provider.getStorage(address, ethers.toBeHex(start + BigInt(i), 32))
                expect(BigInt(raw), `tree ${id} leaf ${i}`).to.equal(expected[i])
            }
        }
    })

    // An unwritten mapping key yields an all-zero struct, so without the guard these would quietly
    // report "empty tree" for a tree that doesn't exist, and a storage-reading client would take that
    // at face value rather than knowing it asked for the wrong id.
    describe("uninitialized trees", () => {
        const UNKNOWN = 999n

        it("Should revert on every reader for a tree that was never initialized", async () => {
            const contract = await deploy()

            await expect(contract.getLeaves(UNKNOWN, 0, 1)).to.be.revertedWithCustomError(contract, "NotInitialized")
            await expect(contract.getNodes(UNKNOWN, 0, 1, 0)).to.be.revertedWithCustomError(contract, "NotInitialized")
            await expect(contract.leavesBaseSlot(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
        })

        it("Should distinguish an initialized-but-empty tree from a nonexistent one", async () => {
            const contract = await deploy()
            const EMPTY = 3n
            await contract.init(EMPTY)

            // initialized and empty: reads fine, returns nothing
            expect(await contract.getLeaves(EMPTY, 0, 0)).to.deep.equal([])
            expect(await contract.leavesBaseSlot(EMPTY)).to.not.equal(0n)

            // nonexistent: rejected outright
            await expect(contract.getLeaves(UNKNOWN, 0, 0)).to.be.revertedWithCustomError(contract, "NotInitialized")
        })
    })

    it("Should keep trees isolated when one is updated", async () => {
        const contract = await deploy()
        const rootBBefore = await contract.root(TREE_B)

        await contract.update(TREE_A, 99n, 0)

        expect(await contract.getLeaves(TREE_A, 0, 3)).to.deep.equal([99n, ...leavesA.slice(1)])
        expect(await contract.getLeaves(TREE_B, 0, 2)).to.deep.equal(leavesB)
        expect(await contract.root(TREE_B)).to.equal(rootBBefore)
    })
})
