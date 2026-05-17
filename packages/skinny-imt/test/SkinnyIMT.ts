import { LeanIMT as JSLeanIMT } from "@zk-kit/lean-imt"
import { expect } from "chai"
import { run } from "hardhat"
import { poseidon2 } from "poseidon-lite"
import { SkinnyIMT, SkinnyIMTTest } from "../typechain-types"

describe("SkinnyIMT", () => {
    const SNARK_SCALAR_FIELD = BigInt("21888242871839275222246405745257275088548364400416034343698204186575808495617")
    let skinnyIMTTest: SkinnyIMTTest
    let skinnyIMT: SkinnyIMT
    let jsLeanIMT: JSLeanIMT

    beforeEach(async () => {
        const { library, contract } = await run("deploy:imt-test", { library: "SkinnyIMT", logs: false })

        skinnyIMTTest = contract
        skinnyIMT = library
        jsLeanIMT = new JSLeanIMT((a, b) => poseidon2([a, b]))
    })

    describe("# insert", () => {
        it("Should not insert a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
            const transaction = skinnyIMTTest.insert(SNARK_SCALAR_FIELD)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        // it("Should not insert a leaf if it is 0", async () => {
        //     const leaf = 0

        //     const transaction = skinnyIMTTest.insert(leaf)

        //     await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafCannotBeZero")
        // })

        it("Should insert a leaf", async () => {
            jsLeanIMT.insert(BigInt(1))

            await skinnyIMTTest.insert(1)

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        // it("Should not insert a leaf if it was already inserted before", async () => {
        //     await skinnyIMTTest.insert(1)

        //     const transaction = skinnyIMTTest.insert(1)

        //     await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafAlreadyExists")
        // })

        it("Should insert 10 leaves", async () => {
            for (let i = 0; i < 10; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await skinnyIMTTest.insert(i + 1)

                const root = await skinnyIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })

        it("Should insert 128 leaves", async () => {
            for (let i = 0; i < 128; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await skinnyIMTTest.insert(i + 1)

                const root = await skinnyIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })
    })

    describe("# insertMany", () => {
        it("Should not insert a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
            const transaction = skinnyIMTTest.insertMany([SNARK_SCALAR_FIELD])

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        // it("Should not insert a leaf if it is 0", async () => {
        //     const leaf = 0

        //     const transaction = skinnyIMTTest.insertMany([leaf])

        //     await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafCannotBeZero")
        // })
        // it("Should not insert a leaf if it was already inserted before", async () => {
        //     await skinnyIMTTest.insert(1)

        //     const transaction = skinnyIMTTest.insertMany([1])

        //     await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafAlreadyExists")
        // })
        it("Should insert a leaf", async () => {
            jsLeanIMT.insert(BigInt(1))

            await skinnyIMTTest.insertMany([1])

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })
        it("Should insert 10 leaves", async () => {
            const elems: bigint[] = []
            for (let i = 0; i < 10; i += 1) {
                elems.push(BigInt(i + 1))
            }

            jsLeanIMT.insertMany(elems)
            await skinnyIMTTest.insertMany(elems)

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })
        it("Should insert 18 leaves 8 times", async () => {
            const howMany = 18
            const howManyTimes = 8
            for (let index = 0; index < howManyTimes; index++) {
                const elems = new Array(howMany).fill(0).map((v, i) => BigInt(index * howMany + i + 1))

                jsLeanIMT.insertMany(elems)
                await skinnyIMTTest.insertMany(elems)

                const root = await skinnyIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            }
        })
        it("Should insert many leaves when the tree is not empty", async () => {
            jsLeanIMT.insert(BigInt(1))

            await skinnyIMTTest.insert(BigInt(1))

            const elems: bigint[] = []
            for (let i = 1; i < 10; i += 1) {
                elems.push(BigInt(i + 1))
            }

            jsLeanIMT.insertMany(elems)
            await skinnyIMTTest.insertMany(elems)

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })
    })

    describe("# update", () => {
        it("Should not update a leaf if the leaf does not exist", async () => {
            const transaction = skinnyIMTTest.update(2, 1, [1, 2, 3, 4])

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafDoesNotExist")
        })

        it("Should not update a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
            const transaction = skinnyIMTTest.update(2, SNARK_SCALAR_FIELD, [1, 2, 3, 4])

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should update a leaf if that's the only leaf in the tree", async () => {
            await skinnyIMTTest.insert(1)

            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.update(0, BigInt(2))

            const { siblings } = jsLeanIMT.generateProof(0)

            await skinnyIMTTest.update(1, 2, siblings)

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should update a leaf if there's more than 1 leaf in the tree", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(0)

            await skinnyIMTTest.update(1, 3, siblings)

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should update a leaf if there's are 128 leaf in the tree", async () => {
            const oldLeaf = 1n
            const newLeaf = 6969n
            const howMany = 18
            const howManyTimes = 8
            // do insert in batches other wise insertMany would look off on gas report
            // use insertMany so test runs faster
            for (let index = 0; index < howManyTimes; index++) {
                const elems = new Array(howMany).fill(0).map((v, i) => BigInt(index * howMany + i + 1))

                jsLeanIMT.insertMany(elems)
                await skinnyIMTTest.insertMany(elems)

                const root = await skinnyIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            }
            const { siblings } = jsLeanIMT.generateProof(0)

            await skinnyIMTTest.update(oldLeaf, newLeaf, siblings)
            jsLeanIMT.update(jsLeanIMT.indexOf(oldLeaf), newLeaf)

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should not update a leaf if its index is even and the value of at least one sibling node is >= SNARK_SCALAR_FIELD", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(0)

            siblings[0] = SNARK_SCALAR_FIELD

            const transaction = skinnyIMTTest.update(1, 3, siblings)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should not update a leaf if its index is odd and the value of at least one sibling node is >= SNARK_SCALAR_FIELD", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(1, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(1)

            siblings[0] = SNARK_SCALAR_FIELD

            const transaction = skinnyIMTTest.update(2, 3, siblings)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should not update a leaf if the siblings are wrong", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(0)

            siblings[0] = BigInt(3)

            const transaction = skinnyIMTTest.update(1, 3, siblings)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "WrongSiblingNodes")
        })

        it("Should update 6 leaves", async () => {
            for (let i = 0; i < 6; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await skinnyIMTTest.insert(i + 1)
            }

            for (let i = 0; i < 6; i += 1) {
                jsLeanIMT.update(i, BigInt(i + 7))

                const { siblings } = jsLeanIMT.generateProof(i)

                await skinnyIMTTest.update(i + 1, i + 7, siblings)

                const root = await skinnyIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })

        it("Should maintain correct tree state after multiple updates and inserts", async () => {
            for (let i = 0; i < 5; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))
                await skinnyIMTTest.insert(i + 1)
            }

            for (let i = 0; i < 3; i += 1) {
                jsLeanIMT.update(i, BigInt(i + 10))
                const { siblings } = jsLeanIMT.generateProof(i)
                await skinnyIMTTest.update(i + 1, i + 10, siblings)
            }

            for (let i = 5; i < 8; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))
                await skinnyIMTTest.insert(i + 1)
            }

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })
    })

    // @TODO again double check this weird concept of update(leaf=0) as being a "remove"
    describe("# remove", () => {
        it("Should remove a leaf", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)
            await skinnyIMTTest.insert(3)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2), BigInt(3)])
            jsLeanIMT.update(2, BigInt(0))

            const { siblings } = jsLeanIMT.generateProof(2)

            await skinnyIMTTest.remove(3, siblings)

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should remove 10 leaf", async () => {
            for (let i = 0; i < 10; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await skinnyIMTTest.insert(i + 1)
            }

            for (let i = 0; i < 10; i += 1) {
                jsLeanIMT.update(i, BigInt(0))

                const { siblings } = jsLeanIMT.generateProof(i)

                await skinnyIMTTest.remove(i + 1, siblings)

                const root = await skinnyIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })
    })

    describe("# has", () => {
        it("Should return true because the node is in the tree", async () => {
            await skinnyIMTTest.insert(1)

            const hasLeaf = await skinnyIMTTest.has(1)

            expect(hasLeaf).to.equal(true)
        })

        it("Should return false because the node is not the tree", async () => {
            const hasLeaf = await skinnyIMTTest.has(2)

            expect(hasLeaf).to.equal(false)
        })

        it("Should return false if the leaf is 0", async () => {
            await skinnyIMTTest.insertMany([1, 2])
            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])

            jsLeanIMT.update(1, BigInt(0))

            const { siblings } = jsLeanIMT.generateProof(1)

            await skinnyIMTTest.remove(2, siblings)

            const hasLeaf = await skinnyIMTTest.has(0)

            expect(hasLeaf).to.equal(false)
        })
    })
    describe("# indexOf", () => {
        it("Should return the index of a leaf", async () => {
            await skinnyIMTTest.insert(1)

            const index = await skinnyIMTTest.indexOf(1)

            expect(index).to.equal(0)
        })

        it("Should return the indices of the leaves", async () => {
            await skinnyIMTTest.insertMany([1, 2])

            const index1 = await skinnyIMTTest.indexOf(1)
            const index2 = await skinnyIMTTest.indexOf(2)

            expect(index1).to.equal(0)
            expect(index2).to.equal(1)
        })

        it("Should throw a custom error if the leaf does not exist", async () => {
            await skinnyIMTTest.insertMany([1, 2])

            const transaction = skinnyIMTTest.indexOf(3)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafDoesNotExist")
        })
    })

    // These tests exist because naively removing the LeafCannotBeZero checks
    // introduced bugs in _insertMany (rightNode != 0 sentinel collision) and
    // _update (if (newLeaf != 0) guard skipping leaves[0] write).
    describe("zero inserts and updates test", () => {
        it("Should insert a leaf with value 0", async () => {
            jsLeanIMT.insert(BigInt(0))

            await skinnyIMTTest.insert(0)

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should insertMany with 0 as the only leaf", async () => {
            jsLeanIMT.insert(BigInt(0))

            await skinnyIMTTest.insertMany([0])

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should insertMany with 0 as the right child", async () => {
            // When forked from LeanIMT, naively removing the LeafCannotBeZero would break this
            // _insertMany used `if (rightNode != 0)` to detect a missing right child, which collided
            // with a real zero-valued leaf and treated it as dangling instead of hashing it.
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.insert(BigInt(0))

            await skinnyIMTTest.insertMany([1, 0])

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should track leaf 0 in has() after updating a leaf to 0", async () => {
            // When forked from LeanIMT, naively removing the LeafCannotBeZero would break this
            // _update had a `if (newLeaf != 0)` guard that skipped writing leaves[0],
            // so has(0) always returned false even after a leaf was updated to zero.
            await skinnyIMTTest.insert(1)
            jsLeanIMT.insert(BigInt(1))

            jsLeanIMT.update(0, BigInt(0))
            const { siblings } = jsLeanIMT.generateProof(0)

            await skinnyIMTTest.update(1, 0, siblings)

            expect(await skinnyIMTTest.has(0)).to.equal(true)
        })

        it("Should allow updating leaf 0 after a leaf was updated to 0", async () => {
            // When forked from LeanIMT, naively removing the LeafCannotBeZero would break this
            // update uses _has(0) which would return false. Even though 0 was inserted.
            // this caused LeafDoesNotExist error, even though it is there!
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)
            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])

            jsLeanIMT.update(0, BigInt(0))
            const { siblings } = jsLeanIMT.generateProof(0)
            await skinnyIMTTest.update(1, 0, siblings)

            jsLeanIMT.update(0, BigInt(3))
            const { siblings: newSiblings } = jsLeanIMT.generateProof(0)
            await skinnyIMTTest.update(0, 3, newSiblings)

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })
    })

    // These tests exist because naively removing the LeafAlreadyExists checks
    // caused bugs — duplicate entries should be allowed and produce roots matching leanIMT.js.
    describe("duplicate entries test", () => {
        it("Should insert a duplicate leaf via insert", async () => {
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.insert(BigInt(1))

            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(1)

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should insert duplicate leaves via insertMany", async () => {
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.insert(BigInt(1))

            await skinnyIMTTest.insertMany([1, 1])

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should insert many duplicates across multiple insertMany calls", async () => {
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.insert(BigInt(2))
            jsLeanIMT.insert(BigInt(2))

            await skinnyIMTTest.insertMany([1, 1])
            await skinnyIMTTest.insertMany([2, 2])

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should update to an already existing leaf value", async () => {
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.insert(BigInt(2))
            jsLeanIMT.update(0, BigInt(2))

            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)

            const { siblings } = jsLeanIMT.generateProof(0)
            await skinnyIMTTest.update(1, 2, siblings)

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should insert a duplicate then update it", async () => {
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.update(1, BigInt(5))

            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(1)

            const { siblings } = jsLeanIMT.generateProof(1)
            await skinnyIMTTest.update(1, 5, siblings)

            const root = await skinnyIMTTest.root()
            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should still find the first occurrence after updating the last duplicate", async () => {
            // When forked from LeanIMT, naively removing the LeafAlreadyExists check caused this to break,
            // leaves were tracked as leave -> index in SkinnyIMTData.leaves.
            // a duplicate insert would overwrite the index of the previous insert of that value
            // this causes update to use the wrong index
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(1) // duplicate at index 1, leaves[1] overwritten to point here
            jsLeanIMT.insert(BigInt(1))
            jsLeanIMT.insert(BigInt(1))

            // update(1, 5) targets last occurrence (index 1) since leaves[1] points there
            jsLeanIMT.update(1, BigInt(5))
            const { siblings } = jsLeanIMT.generateProof(1)
            await skinnyIMTTest.update(1, 5, siblings)

            // leaves[1] is now cleared — the first occurrence at index 0 (still value 1)
            // is permanently orphaned, has(1) returns false even though 1 exists at index 0
            expect(await skinnyIMTTest.has(1)).to.equal(true)
        })
    })

    describe("# root", () => {
        it("Should return the tree root", async () => {
            jsLeanIMT.insert(BigInt(1))

            await skinnyIMTTest.insert(1)

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })
    })
})
