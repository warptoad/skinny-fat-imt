import { expect } from "chai"
import { ethers } from "hardhat"
// already imported by hardhat.config.ts; re-importing just reuses the module for its helper
import { deployPoseidon2 } from "../tasks/deploy-imt-poseidon2-test"

// Interface ids are built here by XOR-ing a signature list written out by hand rather than read off
// the compiled interface, which is the point: the bases derive their ids from `type(I).interfaceId`,
// so if a reader were added to a base and its interface without this list being updated, the two
// would disagree and these tests would fail. Reading the id from the same artifact the base does
// would agree with itself no matter what drifted.
const interfaceId = (signatures: string[]) =>
    ethers.toBeHex(
        signatures.reduce((acc, signature) => acc ^ BigInt(ethers.id(signature).slice(0, 10)), 0n),
        4
    )

// `supportsInterface` is deliberately absent from every list: `type(I).interfaceId` XORs only the
// functions an interface declares itself, and these all inherit it from IERC165 rather than
// declaring it. The storage ids likewise cover only what a `leaves` array adds, so they are much
// shorter than the read ABI a storage consumer actually answers.
const ERC165_ID = "0x01ffc9a7"
const FAT_EVENT_ID = interfaceId([
    "getFatLeaves(uint256,uint256,uint256)",
    "getFatNodes(uint256,uint256,uint256,uint256)",
    "getFatRoot(uint256)",
    "getFatSize(uint256)",
    "getFatDepth(uint256)"
])
// Just the one reader, because `getFatLeaves` is overridden by the fat storage base rather than
// added by it, so it stays in the event id above.
const FAT_STORAGE_ID = interfaceId(["getFatLeavesBaseSlot(uint256)"])
const SKINNY_EVENT_ID = interfaceId([
    "getSkinnySideNodes(uint256,uint256,uint256)",
    "getSkinnyRoot(uint256)",
    "getSkinnySize(uint256)",
    "getSkinnyDepth(uint256)"
])
const SKINNY_STORAGE_ID = interfaceId(["getSkinnyLeaves(uint256,uint256,uint256)", "getSkinnyLeavesBaseSlot(uint256)"])

// One contract holding both a fat and a skinny tree. Every name in both readable bases is
// family-prefixed down to the external ABI, so the bases share no reader selector and no internal
// hook — `supportsInterface` alone excepted, since ERC-165 fixes its selector and a prefix cannot
// separate it. Both trees deliberately use the same id, to pin down that the prefixing leaves each
// family its own id space rather than one shared one.
describe("Fat + Skinny IMT in one contract", () => {
    const TREE = 1n
    const fatLeaves = [11n, 22n, 33n]
    const skinnyLeaves = [44n, 55n]

    async function deploy() {
        // poseidon2 hashes via a Yul contract at a fixed CREATE2 address rather than a linked library
        const [sender] = await ethers.getSigners()
        await deployPoseidon2(ethers.provider, sender)

        const fat = await (await ethers.getContractFactory("FatIMTPoseidon2WriteStorage")).deploy()
        const skinny = await (await ethers.getContractFactory("SkinnyIMTPoseidon2WriteStorage")).deploy()

        const contract = await (
            await ethers.getContractFactory("FatAndSkinnyIMTPoseidon2Test", {
                libraries: {
                    FatIMTPoseidon2WriteStorage: await fat.getAddress(),
                    SkinnyIMTPoseidon2WriteStorage: await skinny.getAddress()
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

        const fatSlot = await contract.getFatLeavesBaseSlot(TREE)
        const skinnySlot = await contract.getSkinnyLeavesBaseSlot(TREE)

        expect(fatSlot).to.not.equal(0n)
        expect(skinnySlot).to.not.equal(0n)
        // same id, different mappings, so the slots must not collide
        expect(fatSlot).to.not.equal(skinnySlot)
    })

    it("Should point each leavesBaseSlot at storage the raw leaves actually live in", async () => {
        const contract = await deploy()
        const address = await contract.getAddress()

        for (const [slot, leaves] of [
            [await contract.getFatLeavesBaseSlot(TREE), fatLeaves],
            [await contract.getSkinnyLeavesBaseSlot(TREE), skinnyLeaves]
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

    // Each family stores its interior differently — fat materializes every node, skinny keeps only
    // the side nodes it needs to insert — so the two readers are named apart and both stay reachable.
    it("Should expose each family's interior reader side by side", async () => {
        const contract = await deploy()

        expect(await contract.getFatNodes(TREE, 0, fatLeaves.length, 0)).to.deep.equal(fatLeaves)

        const skinnyDepth = await contract.getSkinnyDepth(TREE)
        const skinnySideNodes = await contract.getSkinnySideNodes(TREE, 0, skinnyDepth + 1n)
        expect(skinnySideNodes.length).to.equal(Number(skinnyDepth) + 1)
    })

    it("Should report each family's size and depth under the same id", async () => {
        const contract = await deploy()

        expect(await contract.getFatSize(TREE)).to.equal(fatLeaves.length)
        expect(await contract.getSkinnySize(TREE)).to.equal(skinnyLeaves.length)
        expect(await contract.getFatDepth(TREE)).to.equal(2)
        expect(await contract.getSkinnyDepth(TREE)).to.equal(1)
    })

    it("Should report each family's root under the same id", async () => {
        const contract = await deploy()

        const fatRoot = await contract.getFatRoot(TREE)
        const skinnyRoot = await contract.getSkinnyRoot(TREE)

        // the fat root is the single node at the top level, the skinny one the top side node
        expect((await contract.getFatNodes(TREE, 0, 1, await contract.getFatDepth(TREE)))[0]).to.equal(fatRoot)
        expect(
            (
                await contract.getSkinnySideNodes(
                    TREE,
                    await contract.getSkinnyDepth(TREE),
                    (await contract.getSkinnyDepth(TREE)) + 1n
                )
            )[0]
        ).to.equal(skinnyRoot)

        // different trees under the same id, so the roots must not coincide
        expect(fatRoot).to.not.equal(skinnyRoot)
    })

    // ERC-165 is the one thing inheriting both bases costs, because its selector is fixed by the
    // standard and so is the only name in either family a prefix cannot separate. The contract
    // resolves it with `override(FatIMTReadableStorage, SkinnyIMTReadableStorage)` + `super`.
    describe("ERC-165", () => {
        it("Should answer ERC-165 itself, and disclaim the reserved id", async () => {
            const contract = await deploy()

            expect(await contract.supportsInterface(ERC165_ID)).to.equal(true)
            // required by the standard, and what stops a catch-all fallback from reading as
            // "supports everything" — a client that skips this check can be lied to by any contract
            expect(await contract.supportsInterface("0xffffffff")).to.equal(false)
        })

        // The reason the override can use `super`: both families root at the same OpenZeppelin
        // ERC165, so one walk threads all four readable bases. Two independent roots would compile
        // identically and report only whichever family the walk reached first — these four
        // assertions together are what catches that, since either family alone still passes its own.
        it("Should advertise all four read ABIs, both families through one supportsInterface", async () => {
            const contract = await deploy()

            expect(await contract.supportsInterface(FAT_EVENT_ID)).to.equal(true)
            expect(await contract.supportsInterface(FAT_STORAGE_ID)).to.equal(true)
            expect(await contract.supportsInterface(SKINNY_EVENT_ID)).to.equal(true)
            expect(await contract.supportsInterface(SKINNY_STORAGE_ID)).to.equal(true)
        })

        it("Should give the two families distinct ids", async () => {
            // prefixing is what buys this: same shape of reader in both families, no shared selector,
            // so no id collides and a client can tell which family an address serves
            expect(new Set([FAT_EVENT_ID, FAT_STORAGE_ID, SKINNY_EVENT_ID, SKINNY_STORAGE_ID]).size).to.equal(4)
        })

        it("Should not claim an id it has no readers for", async () => {
            const contract = await deploy()

            // a plausible-looking reader neither family declares
            expect(
                await contract.supportsInterface(interfaceId(["getFatSideNodes(uint256,uint256,uint256)"]))
            ).to.equal(false)
        })

        // ERC-165 requires the probe to answer within 30 000 gas, so a client can staticcall it with
        // a cap and treat running out as "not supported" rather than as a failure of its own. This
        // contract is the worst case: four ids to check before falling through to ERC165's own.
        it("Should answer within the ERC-165 gas budget", async () => {
            const contract = await deploy()

            expect(await contract.supportsInterface.estimateGas(ERC165_ID)).to.be.lessThan(30_000n)
            expect(await contract.supportsInterface.estimateGas("0xffffffff")).to.be.lessThan(30_000n)
        })
    })

    it("Should revert NotInitialized per family, for an id that family never initialized", async () => {
        const contract = await deploy()
        const UNKNOWN = 99n

        await expect(contract.getFatLeaves(UNKNOWN, 0, 1)).to.be.revertedWithCustomError(contract, "NotInitialized")
        await expect(contract.getSkinnyLeaves(UNKNOWN, 0, 1)).to.be.revertedWithCustomError(contract, "NotInitialized")
        await expect(contract.getFatLeavesBaseSlot(UNKNOWN)).to.be.revertedWithCustomError(contract, "NotInitialized")
        await expect(contract.getSkinnyLeavesBaseSlot(UNKNOWN)).to.be.revertedWithCustomError(
            contract,
            "NotInitialized"
        )
    })
})
