import { expect } from "chai"
import { ethers } from "hardhat"
// already imported by hardhat.config.ts; re-importing just reuses the module for its helper
import { deployPoseidon2 } from "../tasks/deploy-imt-poseidon2-test"

// One contract holding both variants of the SAME family. Prefixing can't separate them the way it
// separates fat from skinny — `getFatSize(uint256)` is one selector either way — so the two variants
// share one id space and the consumer routes ids by overriding `_getFatEventTree`. These tests pin
// down that both sets stay reachable and independent through the single inherited read ABI.
describe("FatIMTReadable, event + storage variant in one contract", () => {
    // the trees live in arrays, so an id is just the index `init*` handed back, in creation order
    const EVENT_TREE = 0n
    const STORAGE_TREE = 1n
    const eventLeaves = [11n, 22n, 33n]
    const storageLeaves = [44n, 55n]

    async function deploy() {
        // poseidon2 hashes via a Yul contract at a fixed CREATE2 address rather than a linked library
        const [sender] = await ethers.getSigners()
        await deployPoseidon2(ethers.provider, sender)

        const Event = await (await ethers.getContractFactory("FatIMTPoseidon2WriteEvent", { libraries: {} })).deploy()
        const Storage = await (
            await ethers.getContractFactory("FatIMTPoseidon2WriteStorage", { libraries: {} })
        ).deploy()

        const contract = await (
            await ethers.getContractFactory("FatIMTPoseidon2MixedVariantTest", {
                libraries: {
                    FatIMTPoseidon2WriteEvent: await Event.getAddress(),
                    FatIMTPoseidon2WriteStorage: await Storage.getAddress()
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

    // Without the `_getFatEventTree` override every one of these would resolve to the storage trees,
    // and the event tree would be invisible through the ABI.
    it("Should reach both variants through the one inherited reader set", async () => {
        const contract = await deploy()

        expect(await contract.getFatSize(EVENT_TREE)).to.equal(eventLeaves.length)
        expect(await contract.getFatSize(STORAGE_TREE)).to.equal(storageLeaves.length)
        expect(await contract.getFatDepth(EVENT_TREE)).to.equal(2)
        expect(await contract.getFatDepth(STORAGE_TREE)).to.equal(1)

        expect(await contract.getFatNodes(EVENT_TREE, 0, eventLeaves.length, 0)).to.deep.equal(eventLeaves)
        expect(await contract.getFatNodes(STORAGE_TREE, 0, storageLeaves.length, 0)).to.deep.equal(storageLeaves)
    })

    // The leaf reader defaults to the `leaves` array; this consumer overrides it so event ids are
    // served off level 0 of `nodes` instead of reverting.
    it("Should serve each variant's leaves from where that variant keeps them", async () => {
        const contract = await deploy()

        expect(await contract.getFatLeaves(EVENT_TREE, 0, eventLeaves.length)).to.deep.equal(eventLeaves)
        expect(await contract.getFatLeaves(STORAGE_TREE, 0, storageLeaves.length)).to.deep.equal(storageLeaves)
    })

    // Only the storage variant has an array in consecutive slots, so only its ids have a base slot.
    it("Should offer a leaves base slot for storage ids only", async () => {
        const contract = await deploy()

        expect(await contract.getFatLeavesBaseSlot(STORAGE_TREE)).to.not.equal(0n)
        await expect(contract.getFatLeavesBaseSlot(EVENT_TREE)).to.be.revertedWithCustomError(
            contract,
            "NotInitialized"
        )
    })

    it("Should keep the two variants' writes from touching each other", async () => {
        const contract = await deploy()

        await contract.insertManyEvent(EVENT_TREE, [66n])

        expect(await contract.getFatSize(EVENT_TREE)).to.equal(4)
        expect(await contract.getFatSize(STORAGE_TREE)).to.equal(storageLeaves.length)
        expect(await contract.getFatLeaves(STORAGE_TREE, 0, storageLeaves.length)).to.deep.equal(storageLeaves)
    })

    // With an array layout an id past the end can't resolve at all, so it never reaches the
    // NotInitialized guard — it stops on the array bound instead. Either way a client asking for a
    // tree that isn't there is told so rather than handed an empty one.
    it("Should reject ids past the trees it has", async () => {
        const contract = await deploy()

        expect(await contract.treeCount()).to.equal(2)
        await expect(contract.getFatSize(2n)).to.be.reverted
        await expect(contract.getFatLeaves(2n, 0, 1)).to.be.reverted
    })
})
