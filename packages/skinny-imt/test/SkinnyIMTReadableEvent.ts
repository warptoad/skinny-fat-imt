import { LeanIMT as JSLeanIMT } from "@zk-kit/lean-imt"
// @ts-ignore - @zkpassport/poseidon2's exports map omits a "types" condition, so
// exports-aware resolution can't find its (shipped) declarations. Types are fine at runtime.
import { poseidon2Hash } from "@zkpassport/poseidon2"
import { expect } from "chai"
import { ethers } from "hardhat"
// already imported by hardhat.config.ts; re-importing just reuses the module for its helper
import { deployPoseidon2 } from "../tasks/deploy-imt-poseidon2-test"

// SkinnyIMTReadableEvent is the base for a tree that stores no leaves at all — only the side nodes
// it needs to keep inserting — so the side-node reader plus size/depth is the whole read surface,
// and there is no leaf reader and no base-slot reader to offer. Same treeId-as-input contract as the
// storage variant, pinned down against a mapping of trees.
describe("SkinnyIMTReadableEvent (multi-tree)", () => {
    const hash = (a: bigint, b: bigint) => poseidon2Hash([a, b])
    const TREE_A = 1n
    const TREE_B = 2n
    const leavesA = [11n, 22n, 33n]
    const leavesB = [44n, 55n]

    async function deploy() {
        // poseidon2 hashes via a Yul contract at a fixed CREATE2 address rather than a linked library
        const [sender] = await ethers.getSigners()
        await deployPoseidon2(ethers.provider, sender)

        const Event = await (
            await ethers.getContractFactory("SkinnyIMTPoseidon2WriteEvent", { libraries: {} })
        ).deploy()

        const contract = await (
            await ethers.getContractFactory("SkinnyIMTPoseidon2EventMultiTreeTest", {
                libraries: {
                    SkinnyIMTPoseidon2WriteEvent: await Event.getAddress()
                }
            })
        ).deploy()

        await contract.init(TREE_A)
        await contract.init(TREE_B)
        await contract.insertMany(TREE_A, leavesA)
        await contract.insertMany(TREE_B, leavesB)

        // JS mirror, used only to produce proof siblings for skinny's proof-consuming update
        const jsA = new JSLeanIMT(hash)
        jsA.insertMany(leavesA)
        return { contract, jsA }
    }

    it("Should report each tree's own size and depth", async () => {
        const { contract } = await deploy()

        // 3 leaves need a depth-2 tree, 2 leaves only a depth-1 one
        expect(await contract.getSkinnySize(TREE_A)).to.equal(leavesA.length)
        expect(await contract.getSkinnyDepth(TREE_A)).to.equal(2)
        expect(await contract.getSkinnySize(TREE_B)).to.equal(leavesB.length)
        expect(await contract.getSkinnyDepth(TREE_B)).to.equal(1)
    })

    // The side nodes are everything this variant keeps, so a client resyncing a tree reads them
    // through here. The one at `depth` is what `root` returns, and level 0 holds the last leaf left
    // waiting for a partner.
    it("Should read each tree's side nodes independently", async () => {
        const { contract } = await deploy()

        const sideNodesA = await contract.getSkinnySideNodes(TREE_A, 0, 3)
        expect(sideNodesA.length).to.equal(3)
        expect(sideNodesA[0]).to.equal(leavesA[2])
        expect(sideNodesA[2]).to.equal(await contract.getSkinnyRoot(TREE_A))

        // tree B's two leaves already paired up, so its top side node is the root
        const sideNodesB = await contract.getSkinnySideNodes(TREE_B, 0, 2)
        expect(sideNodesB[1]).to.equal(await contract.getSkinnyRoot(TREE_B))
        expect(sideNodesB[1]).to.not.equal(sideNodesA[2])
    })

    it("Should keep trees isolated when one is updated", async () => {
        const { contract, jsA } = await deploy()
        const rootBBefore = await contract.getSkinnyRoot(TREE_B)

        // skinny update consumes a proof: (oldLeaf, newLeaf, leafIndex, siblings)
        const { siblings } = jsA.generateProof(0)
        await contract.update(TREE_A, leavesA[0], 99n, 0, siblings)
        jsA.update(0, 99n)

        expect(await contract.getSkinnyRoot(TREE_A)).to.equal(jsA.root)
        expect(await contract.getSkinnyRoot(TREE_B)).to.equal(rootBBefore)
        expect(await contract.getSkinnySize(TREE_B)).to.equal(leavesB.length)
    })

    it("Should shrink size and depth back on reset", async () => {
        const { contract } = await deploy()

        await contract.reset(TREE_A)

        expect(await contract.getSkinnySize(TREE_A)).to.equal(0)
        expect(await contract.getSkinnyDepth(TREE_A)).to.equal(0)

        // the other tree is untouched by the reset
        expect(await contract.getSkinnySize(TREE_B)).to.equal(leavesB.length)
    })

    // An unwritten mapping key yields an all-zero struct, so without the guard these would quietly
    // report "empty tree" for a tree that doesn't exist.
    describe("uninitialized trees", () => {
        const UNKNOWN = 999n

        it("Should revert on every reader for a tree that was never initialized", async () => {
            const { contract } = await deploy()

            await expect(contract.getSkinnySideNodes(UNKNOWN, 0, 1)).to.be.revertedWithCustomError(
                contract,
                "NotInitialized"
            )
            await expect(contract.getSkinnySize(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
            await expect(contract.getSkinnyDepth(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
        })

        it("Should distinguish an initialized-but-empty tree from a nonexistent one", async () => {
            const { contract } = await deploy()
            const EMPTY = 3n
            await contract.init(EMPTY)

            // initialized and empty: reads fine, returns nothing
            expect(await contract.getSkinnySize(EMPTY)).to.equal(0)
            expect(await contract.getSkinnySideNodes(EMPTY, 0, 0)).to.deep.equal([])

            // nonexistent: rejected outright
            await expect(contract.getSkinnySize(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
        })
    })
})
