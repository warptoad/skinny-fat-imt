import { LeanIMT as JSLeanIMT } from "@zk-kit/lean-imt"
import { expect } from "chai"
import { run } from "hardhat"
import { poseidon2 } from "poseidon-lite"
import { LeanIMT, LeanIMTTest } from "../typechain-types"

describe("LeanIMT", () => {
    const SNARK_SCALAR_FIELD = BigInt("21888242871839275222246405745257275088548364400416034343698204186575808495617")
    let leanIMTTest: LeanIMTTest
    let leanIMT: LeanIMT
    let jsLeanIMT: JSLeanIMT

    beforeEach(async () => {
        const { library, contract } = await run("deploy:imt-test", { library: "LeanIMT", logs: false })

        leanIMTTest = contract
        leanIMT = library
        jsLeanIMT = new JSLeanIMT((a, b) => poseidon2([a, b]))
    })

    describe("# insert", () => {
        it("Should not insert a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
            const transaction = leanIMTTest.insert(SNARK_SCALAR_FIELD)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should not insert a leaf if it is 0", async () => {
            const leaf = 0

            const transaction = leanIMTTest.insert(leaf)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafCannotBeZero")
        })

        it("Should insert a leaf", async () => {
            jsLeanIMT.insert(BigInt(1))

            await leanIMTTest.insert(1)

            const root = await leanIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should not insert a leaf if it was already inserted before", async () => {
            await leanIMTTest.insert(1)

            const transaction = leanIMTTest.insert(1)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafAlreadyExists")
        })

        it("Should insert 10 leaves", async () => {
            for (let i = 0; i < 10; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await leanIMTTest.insert(i + 1)

                const root = await leanIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })

        // Benchmark scenario matched with the skinny/fat suites: the deepest single insert
        // (the 128th leaf hashes at all 7 levels) sets the `insert` Max in the gas report.
        it("Should insert 128 leaves", async () => {
            for (let i = 0; i < 128; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await leanIMTTest.insert(i + 1)

                const root = await leanIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })
    })

    describe("# insertMany", () => {
        it("Should not insert a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
            const transaction = leanIMTTest.insertMany([SNARK_SCALAR_FIELD])

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should not insert a leaf if it is 0", async () => {
            const leaf = 0

            const transaction = leanIMTTest.insertMany([leaf])

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafCannotBeZero")
        })
        it("Should not insert a leaf if it was already inserted before", async () => {
            await leanIMTTest.insert(1)

            const transaction = leanIMTTest.insertMany([1])

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafAlreadyExists")
        })
        it("Should insert a leaf", async () => {
            jsLeanIMT.insert(BigInt(1))

            await leanIMTTest.insertMany([1])

            const root = await leanIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })
        it("Should insert 10 leaves", async () => {
            const elems: bigint[] = []
            for (let i = 0; i < 10; i += 1) {
                elems.push(BigInt(i + 1))
            }

            jsLeanIMT.insertMany(elems)
            await leanIMTTest.insertMany(elems)

            const root = await leanIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })
        it("Should insert many leaves when the tree is not empty", async () => {
            jsLeanIMT.insert(BigInt(1))

            await leanIMTTest.insert(BigInt(1))

            const elems: bigint[] = []
            for (let i = 1; i < 10; i += 1) {
                elems.push(BigInt(i + 1))
            }

            jsLeanIMT.insertMany(elems)
            await leanIMTTest.insertMany(elems)

            const root = await leanIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        // Benchmark scenario matched with the skinny/fat suites: eight batches of 18 leaves
        // grow the tree to 144 leaves; the last batch (18 into a 126-leaf tree) is the heaviest
        // insertMany in the shared scenario set.
        it("Should insert 18 leaves 8 times", async () => {
            const howMany = 18
            const howManyTimes = 8
            for (let index = 0; index < howManyTimes; index++) {
                const elems = new Array(howMany).fill(0).map((v, i) => BigInt(index * howMany + i + 1))

                jsLeanIMT.insertMany(elems)
                await leanIMTTest.insertMany(elems)

                const root = await leanIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            }
        })
    })

    describe("# update", () => {
        it("Should not update a leaf if the leaf does not exist", async () => {
            const transaction = leanIMTTest.update(2, 1, [1, 2, 3, 4])

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafDoesNotExist")
        })

        it("Should not update a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
            const transaction = leanIMTTest.update(2, SNARK_SCALAR_FIELD, [1, 2, 3, 4])

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should update a leaf if that's the only leaf in the tree", async () => {
            await leanIMTTest.insert(1)

            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.update(0, BigInt(2))

            const { siblings } = jsLeanIMT.generateProof(0)

            await leanIMTTest.update(1, 2, siblings)

            const root = await leanIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should update a leaf if there's more than 1 leaf in the tree", async () => {
            await leanIMTTest.insert(1)
            await leanIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(0)

            await leanIMTTest.update(1, 3, siblings)

            const root = await leanIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        // Benchmark scenario matched with the skinny/fat suites: update the leaf at index 0 of a
        // 144-leaf tree (grown with eight 18-leaf batches). This deepest update sets the `update`
        // Max in the gas report.
        it("Should update a leaf if there's 144 leaves in the tree", async () => {
            const oldLeaf = 1n
            const newLeaf = 6969n
            const howMany = 18
            const howManyTimes = 8
            for (let index = 0; index < howManyTimes; index++) {
                const elems = new Array(howMany).fill(0).map((v, i) => BigInt(index * howMany + i + 1))

                jsLeanIMT.insertMany(elems)
                await leanIMTTest.insertMany(elems)

                const root = await leanIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            }

            const { siblings } = jsLeanIMT.generateProof(0)

            await leanIMTTest.update(oldLeaf, newLeaf, siblings)
            jsLeanIMT.update(0, newLeaf)

            const root = await leanIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should not update a leaf if its index is even and the value of at least one sibling node is >= SNARK_SCALAR_FIELD", async () => {
            await leanIMTTest.insert(1)
            await leanIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(0)

            siblings[0] = SNARK_SCALAR_FIELD

            const transaction = leanIMTTest.update(1, 3, siblings)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should not update a leaf if its index is odd and the value of at least one sibling node is >= SNARK_SCALAR_FIELD", async () => {
            await leanIMTTest.insert(1)
            await leanIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(1, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(1)

            siblings[0] = SNARK_SCALAR_FIELD

            const transaction = leanIMTTest.update(2, 3, siblings)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should not update a leaf if the siblings are wrong", async () => {
            await leanIMTTest.insert(1)
            await leanIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(0)

            siblings[0] = BigInt(3)

            const transaction = leanIMTTest.update(1, 3, siblings)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "WrongSiblingNodes")
        })

        it("Should update 6 leaves", async () => {
            for (let i = 0; i < 6; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await leanIMTTest.insert(i + 1)
            }

            for (let i = 0; i < 6; i += 1) {
                jsLeanIMT.update(i, BigInt(i + 7))

                const { siblings } = jsLeanIMT.generateProof(i)

                await leanIMTTest.update(i + 1, i + 7, siblings)

                const root = await leanIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })

        it("Should not update a leaf that was removed", async () => {
            await leanIMTTest.insertMany([1, 2])
            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])

            jsLeanIMT.update(1, BigInt(0))

            const { siblings } = jsLeanIMT.generateProof(1)

            await leanIMTTest.remove(2, siblings)

            jsLeanIMT.update(1, BigInt(3))

            const { siblings: newSiblings } = jsLeanIMT.generateProof(1)

            const transaction = leanIMTTest.update(0, 3, newSiblings)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafDoesNotExist")
        })
        it("Should not update a leaf if the new value already exists", async () => {
            await leanIMTTest.insert(1)
            await leanIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(2))

            const { siblings } = jsLeanIMT.generateProof(0)

            const transaction = leanIMTTest.update(1, 2, siblings)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafAlreadyExists")
        })
        it("Should maintain correct tree state after multiple updates and inserts", async () => {
            for (let i = 0; i < 5; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))
                await leanIMTTest.insert(i + 1)
            }

            for (let i = 0; i < 3; i += 1) {
                jsLeanIMT.update(i, BigInt(i + 10))
                const { siblings } = jsLeanIMT.generateProof(i)
                await leanIMTTest.update(i + 1, i + 10, siblings)
            }

            for (let i = 5; i < 8; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))
                await leanIMTTest.insert(i + 1)
            }

            const root = await leanIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })
    })

    describe("# remove", () => {
        it("Should remove a leaf", async () => {
            await leanIMTTest.insert(1)
            await leanIMTTest.insert(2)
            await leanIMTTest.insert(3)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2), BigInt(3)])
            jsLeanIMT.update(2, BigInt(0))

            const { siblings } = jsLeanIMT.generateProof(2)

            await leanIMTTest.remove(3, siblings)

            const root = await leanIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should remove 10 leaf", async () => {
            for (let i = 0; i < 10; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await leanIMTTest.insert(i + 1)
            }

            for (let i = 0; i < 10; i += 1) {
                jsLeanIMT.update(i, BigInt(0))

                const { siblings } = jsLeanIMT.generateProof(i)

                await leanIMTTest.remove(i + 1, siblings)

                const root = await leanIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })
    })

    describe("# has", () => {
        it("Should return true because the node is in the tree", async () => {
            await leanIMTTest.insert(1)

            const hasLeaf = await leanIMTTest.has(1)

            expect(hasLeaf).to.equal(true)
        })

        it("Should return false because the node is not the tree", async () => {
            const hasLeaf = await leanIMTTest.has(2)

            expect(hasLeaf).to.equal(false)
        })

        it("Should return false if the leaf is 0", async () => {
            await leanIMTTest.insertMany([1, 2])
            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])

            jsLeanIMT.update(1, BigInt(0))

            const { siblings } = jsLeanIMT.generateProof(1)

            await leanIMTTest.remove(2, siblings)

            const hasLeaf = await leanIMTTest.has(0)

            expect(hasLeaf).to.equal(false)
        })
    })
    describe("# indexOf", () => {
        it("Should return the index of a leaf", async () => {
            await leanIMTTest.insert(1)

            const index = await leanIMTTest.indexOf(1)

            expect(index).to.equal(0)
        })

        it("Should return the indices of the leaves", async () => {
            await leanIMTTest.insertMany([1, 2])

            const index1 = await leanIMTTest.indexOf(1)
            const index2 = await leanIMTTest.indexOf(2)

            expect(index1).to.equal(0)
            expect(index2).to.equal(1)
        })

        it("Should throw a custom error if the leaf does not exist", async () => {
            await leanIMTTest.insertMany([1, 2])

            const transaction = leanIMTTest.indexOf(3)

            await expect(transaction).to.be.revertedWithCustomError(leanIMT, "LeafDoesNotExist")
        })
    })

    describe("# root", () => {
        it("Should return the tree root", async () => {
            jsLeanIMT.insert(BigInt(1))

            await leanIMTTest.insert(1)

            const root = await leanIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })
    })

    // Stand-ins for skinny/fat's batch primitives (LeanIMT has neither). Kept in their own describes
    // so they do not pollute the `insert`/`insertMany`/`update` gas rows. Gas is captured directly
    // from the receipt (tagged `BENCH ...`) so the matched scenario is unambiguous.
    describe("# insertManyRepeated (batch-insert stand-in)", () => {
        it("Should insert 128 leaves in one call", async () => {
            for (let i = 0; i < 128; i += 1) {
                jsLeanIMT.insert(BigInt(7 + i))
            }

            const tx = await leanIMTTest.insertManyRepeated(7, 128)
            const receipt = await tx.wait()
            // eslint-disable-next-line no-console
            console.log(`BENCH insertManyRepeated128 ${receipt!.gasUsed}`)

            expect(await leanIMTTest.root()).to.equal(jsLeanIMT.root)
        })
    })

    describe("# updateMany (looped-update stand-in)", () => {
        it("Should update all 8 leaves in a size-8 tree", async () => {
            const elems = new Array(8).fill(0).map((_, i) => BigInt(i + 1))
            jsLeanIMT.insertMany(elems)
            await leanIMTTest.insertMany(elems)

            const oldLeaves: bigint[] = []
            const newLeaves: bigint[] = []
            const siblings: bigint[][] = []
            for (let idx = 0; idx < 8; idx += 1) {
                const { siblings: sib } = jsLeanIMT.generateProof(idx)
                oldLeaves.push(elems[idx])
                newLeaves.push(BigInt(5000 + idx))
                siblings.push(sib)
                jsLeanIMT.update(idx, BigInt(5000 + idx))
            }

            const tx = await leanIMTTest.updateMany(oldLeaves, newLeaves, siblings)
            const receipt = await tx.wait()
            // eslint-disable-next-line no-console
            console.log(`BENCH updateMany8 ${receipt!.gasUsed}`)

            expect(await leanIMTTest.root()).to.equal(jsLeanIMT.root)
        })
    })
})
