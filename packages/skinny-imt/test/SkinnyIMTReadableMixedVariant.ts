import { expect } from "chai"
import { ethers } from "hardhat"
// already imported by hardhat.config.ts; re-importing just reuses the module for its helper
import { deployPoseidon2 } from "../tasks/deploy-imt-poseidon2-test"

// One contract holding both variants of the SAME family. Prefixing can't separate them the way it
// separates skinny from fat — `getSkinnySize(uint256)` is one selector either way — so the two
// variants share one id space and the consumer routes ids by overriding `_getSkinnyEventTree`. These
// tests pin down that both sets stay reachable and independent through the single inherited read ABI.
describe("SkinnyIMTReadable, event + storage variant in one contract", () => {
    // the trees live in arrays, so an id is just the index `init*` handed back, in creation order
    const EVENT_TREE = 0n
    const STORAGE_TREE = 1n
    const eventLeaves = [11n, 22n, 33n]
    const storageLeaves = [44n, 55n]

    async function deploy() {
        // poseidon2 hashes via a Yul contract at a fixed CREATE2 address rather than a linked library
        const [sender] = await ethers.getSigners()
        await deployPoseidon2(ethers.provider, sender)

        const Event = await (
            await ethers.getContractFactory("SkinnyIMTPoseidon2WriteEvent", { libraries: {} })
        ).deploy()
        const Storage = await (
            await ethers.getContractFactory("SkinnyIMTPoseidon2WriteStorage", { libraries: {} })
        ).deploy()

        const contract = await (
            await ethers.getContractFactory("SkinnyIMTPoseidon2MixedVariantTest", {
                libraries: {
                    SkinnyIMTPoseidon2WriteEvent: await Event.getAddress(),
                    SkinnyIMTPoseidon2WriteStorage: await Storage.getAddress()
                }
            })
        ).deploy()

        // indexes are handed out in creation order, so these land on EVENT_TREE / STORAGE_TREE
        expect(await contract.initEvent.staticCall()).to.equal(EVENT_TREE)
        await contract.initEvent()
        expect(await contract.initStorage.staticCall()).to.equal(STORAGE_TREE)
        await contract.initStorage()

        await contract.insertManyEvent(EVENT_TREE, eventLeaves)
        await contract.insertManyStorage(STORAGE_TREE, storageLeaves)
        return contract
    }

    // Without the `_getSkinnyEventTree` override every one of these would resolve to the storage
    // trees, and the event tree would be invisible through the ABI.
    it("Should reach both variants through the one inherited reader set", async () => {
        const contract = await deploy()

        expect(await contract.getSkinnySize(EVENT_TREE)).to.equal(eventLeaves.length)
        expect(await contract.getSkinnySize(STORAGE_TREE)).to.equal(storageLeaves.length)
        expect(await contract.getSkinnyDepth(EVENT_TREE)).to.equal(2)
        expect(await contract.getSkinnyDepth(STORAGE_TREE)).to.equal(1)

        // each tree's own side nodes: the top one is its root, and the two trees don't share it
        const eventSideNodes = await contract.getSkinnySideNodes(EVENT_TREE, 0, 3)
        const storageSideNodes = await contract.getSkinnySideNodes(STORAGE_TREE, 0, 2)
        expect(eventSideNodes[0]).to.equal(eventLeaves[2])
        expect(eventSideNodes[2]).to.not.equal(storageSideNodes[1])
    })

    // An event tree stores no leaves at all, so there is nothing to route for the leaf readers:
    // reverting for those ids is the honest answer.
    it("Should serve the leaf readers for storage ids only", async () => {
        const contract = await deploy()

        expect(await contract.getSkinnyLeaves(STORAGE_TREE, 0, storageLeaves.length)).to.deep.equal(storageLeaves)
        expect(await contract.getSkinnyLeavesBaseSlot(STORAGE_TREE)).to.not.equal(0n)

        await expect(contract.getSkinnyLeaves(EVENT_TREE, 0, 1)).to.be.revertedWithCustomError(
            contract,
            "NotInitialized"
        )
        await expect(contract.getSkinnyLeavesBaseSlot(EVENT_TREE)).to.be.revertedWithCustomError(
            contract,
            "NotInitialized"
        )
    })

    it("Should keep the two variants' writes from touching each other", async () => {
        const contract = await deploy()

        await contract.insertManyEvent(EVENT_TREE, [66n])

        expect(await contract.getSkinnySize(EVENT_TREE)).to.equal(4)
        expect(await contract.getSkinnySize(STORAGE_TREE)).to.equal(storageLeaves.length)
        expect(await contract.getSkinnyLeaves(STORAGE_TREE, 0, storageLeaves.length)).to.deep.equal(storageLeaves)
    })

    // With an array layout an id past the end can't resolve at all, so it never reaches the
    // NotInitialized guard — it stops on the array bound instead. Either way a client asking for a
    // tree that isn't there is told so rather than handed an empty one.
    it("Should reject ids past the trees it has", async () => {
        const contract = await deploy()

        expect(await contract.treeCount()).to.equal(2)
        await expect(contract.getSkinnySize(2n)).to.be.reverted
        await expect(contract.getSkinnyLeaves(2n, 0, 1)).to.be.reverted
    })
})
