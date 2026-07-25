import { expect } from "chai"
import { ethers } from "hardhat"
// already imported by hardhat.config.ts; re-importing just reuses the module for its helper
import { deployPoseidon2 } from "../tasks/deploy-imt-poseidon2-test"

// One contract holding both a fat and a skinny tree. Every name in both readable bases is
// family-prefixed down to the external ABI, so the bases share no selector and no internal hook and
// the contract inherits both with nothing to reconcile. Both trees deliberately use the same id, to
// pin down that the prefixing leaves each family its own id space rather than one shared one.
describe("Fat + Skinny IMT in one contract", () => {
    const TREE = 1n
    const fatLeaves = [11n, 22n, 33n]
    const skinnyLeaves = [44n, 55n]

    async function deploy() {
        // poseidon2 hashes via a Yul contract at a fixed CREATE2 address rather than a linked library
        const [sender] = await ethers.getSigners()
        await deployPoseidon2(ethers.provider, sender)

        const fat = await (await ethers.getContractFactory("FatIMTPoseidon2WriteFullNode")).deploy()
        const skinny = await (await ethers.getContractFactory("SkinnyIMTPoseidon2WriteFullNode")).deploy()

        const contract = await (
            await ethers.getContractFactory("FatAndSkinnyIMTPoseidon2Test", {
                libraries: {
                    FatIMTPoseidon2WriteFullNode: await fat.getAddress(),
                    SkinnyIMTPoseidon2WriteFullNode: await skinny.getAddress()
                }
            })
        ).deploy()

        await contract.initFat(TREE)
        await contract.initSkinny(TREE)
        await contract.insertManyFat(TREE, fatLeaves)
        await contract.insertManySkinny(TREE, skinnyLeaves)
        return contract
    }

    it("Should read each family's leaves through its own reader, under the same id", async () => {
        const contract = await deploy()

        expect(await contract.getFatLeaves(TREE, 0, fatLeaves.length)).to.deep.equal(fatLeaves)
        expect(await contract.getSkinnyLeaves(TREE, 0, skinnyLeaves.length)).to.deep.equal(skinnyLeaves)

        // a sub-range, to confirm [from, to) is still honoured per family
        expect(await contract.getFatLeaves(TREE, 1, 3)).to.deep.equal(fatLeaves.slice(1))
    })

    it("Should keep the two families' writes from touching each other", async () => {
        const contract = await deploy()

        await contract.insertManyFat(TREE, [66n])

        expect(await contract.getFatLeaves(TREE, 0, 4)).to.deep.equal([...fatLeaves, 66n])
        // the skinny tree under the same id must be untouched
        expect(await contract.getSkinnyLeaves(TREE, 0, skinnyLeaves.length)).to.deep.equal(skinnyLeaves)
    })

    it("Should give each family's tree its own leavesBaseSlot", async () => {
        const contract = await deploy()

        const fatSlot = await contract.fatLeavesBaseSlot(TREE)
        const skinnySlot = await contract.skinnyLeavesBaseSlot(TREE)

        expect(fatSlot).to.not.equal(0n)
        expect(skinnySlot).to.not.equal(0n)
        // same id, different mappings, so the slots must not collide
        expect(fatSlot).to.not.equal(skinnySlot)
    })

    it("Should point each leavesBaseSlot at storage the raw leaves actually live in", async () => {
        const contract = await deploy()
        const address = await contract.getAddress()

        for (const [slot, leaves] of [
            [await contract.fatLeavesBaseSlot(TREE), fatLeaves],
            [await contract.skinnyLeavesBaseSlot(TREE), skinnyLeaves]
        ] as const) {
            // `leaves` is the struct's first member, so the struct slot is the array header; elements
            // start at keccak256(slot) — the derivation the skinnyfatJs lib performs
            const first = BigInt(ethers.keccak256(ethers.toBeHex(slot, 32)))

            for (let i = 0; i < leaves.length; i++) {
                const raw = await ethers.provider.getStorage(address, first + BigInt(i))
                expect(BigInt(raw)).to.equal(leaves[i])
            }
        }
    })

    it("Should expose the fat-only node reader, which has no skinny counterpart", async () => {
        const contract = await deploy()

        expect(await contract.getFatNodes(TREE, 0, fatLeaves.length, 0)).to.deep.equal(fatLeaves)
    })

    it("Should revert NotInitialized per family, for an id that family never initialized", async () => {
        const contract = await deploy()
        const UNKNOWN = 99n

        await expect(contract.getFatLeaves(UNKNOWN, 0, 1)).to.be.revertedWithCustomError(contract, "NotInitialized")
        await expect(contract.getSkinnyLeaves(UNKNOWN, 0, 1)).to.be.revertedWithCustomError(contract, "NotInitialized")
        await expect(contract.fatLeavesBaseSlot(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
        await expect(contract.skinnyLeavesBaseSlot(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
    })
})
