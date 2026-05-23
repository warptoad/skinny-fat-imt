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

        it("Should insert a leaf", async () => {
            jsLeanIMT.insert(BigInt(1))

            await skinnyIMTTest.insert(1)

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

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

    describe("# insertManyZeros", () => {
        // @zk-kit/lean-imt's `insertMany` and `update` use `if (rightNode)` / `if (sibling)` truthy
        // checks that treat BigInt(0) as falsy, silently skipping hashes when zeros are involved.
        // Workaround: feed zeros to jsLeanIMT via `insert(0n)` one at a time — that path doesn't
        // hit the bug. The update tests use odd-index updates to avoid the same falsy-sibling bug
        // in `update`.
        const jsInsertZeros = (n: number) => {
            for (let i = 0; i < n; i++) jsLeanIMT.insert(0n)
        }

        describe("empty tree", () => {
            it("Should be a no-op when amount is 0", async () => {
                const before = await skinnyIMTTest.root()
                await skinnyIMTTest.insertManyZeros(0)

                expect(await skinnyIMTTest.root()).to.equal(before)
                expect(await skinnyIMTTest.size()).to.equal(0)
                expect(await skinnyIMTTest.depth()).to.equal(0)
            })

            for (const n of [1, 2, 3, 4, 5, 6, 7, 8, 16, 100]) {
                const label =
                    n === 1
                        ? "1 zero"
                        : `${n} zeros${
                              Number.isInteger(Math.log2(n))
                                  ? " (power of 2)"
                                  : ` (binary ${n.toString(2)})`
                          }`

                it(`Should insert ${label}`, async () => {
                    jsInsertZeros(n)
                    await skinnyIMTTest.insertManyZeros(n)

                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                    expect(await skinnyIMTTest.size()).to.equal(n)
                    expect(await skinnyIMTTest.depth()).to.equal(jsLeanIMT.depth)
                })
            }
        })

        describe("non-empty tree", () => {
            it("Should be a no-op when amount is 0", async () => {
                const leaves = [1n, 2n, 3n]
                jsLeanIMT.insertMany(leaves)
                await skinnyIMTTest.insertMany(leaves)

                const before = await skinnyIMTTest.root()
                const beforeSize = await skinnyIMTTest.size()
                const beforeDepth = await skinnyIMTTest.depth()
                await skinnyIMTTest.insertManyZeros(0)

                expect(await skinnyIMTTest.root()).to.equal(before)
                expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await skinnyIMTTest.size()).to.equal(beforeSize)
                expect(await skinnyIMTTest.depth()).to.equal(beforeDepth)
            })

            const cases: { pre: bigint[]; n: number; label: string }[] = [
                { pre: [1n], n: 1, label: "1 zero after 1 leaf" },
                { pre: [1n, 2n, 3n, 4n, 5n], n: 3, label: "3 zeros after 5 leaves" },
                { pre: [1n, 2n, 3n], n: 5, label: "5 zeros after 3 leaves" },
                {
                    pre: [1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n],
                    n: 8,
                    label: "8 zeros after 8 leaves (both powers of 2)"
                },
                { pre: [42n], n: 7, label: "7 zeros after 1 leaf (worst-case popcount of n)" }
            ]
            for (const { pre, n, label } of cases) {
                it(`Should append ${label}`, async () => {
                    jsLeanIMT.insertMany(pre)
                    await skinnyIMTTest.insertMany(pre)

                    jsInsertZeros(n)
                    await skinnyIMTTest.insertManyZeros(n)

                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                    expect(await skinnyIMTTest.size()).to.equal(pre.length + n)
                    expect(await skinnyIMTTest.depth()).to.equal(jsLeanIMT.depth)
                })
            }

            it("Should append zeros that cross a depth boundary", async () => {
                // size 3 (depth 2) → size 8 (depth 3): the depth must grow during the zero append.
                const pre = [1n, 2n, 3n]
                jsLeanIMT.insertMany(pre)
                await skinnyIMTTest.insertMany(pre)
                expect(await skinnyIMTTest.depth()).to.equal(2)

                jsInsertZeros(5)
                await skinnyIMTTest.insertManyZeros(5)

                expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await skinnyIMTTest.depth()).to.equal(3)
            })
        })

        describe("composability", () => {
            it("Should allow inserting non-zero leaves after insertManyZeros", async () => {
                jsInsertZeros(5)
                await skinnyIMTTest.insertManyZeros(5)

                jsLeanIMT.insertMany([7n, 8n])
                await skinnyIMTTest.insertMany([7, 8])

                expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await skinnyIMTTest.size()).to.equal(7)
            })

            it("Should allow a single insert after insertManyZeros", async () => {
                jsInsertZeros(3)
                await skinnyIMTTest.insertManyZeros(3)

                jsLeanIMT.insert(99n)
                await skinnyIMTTest.insert(99)

                expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await skinnyIMTTest.size()).to.equal(4)
            })

            it("Should allow two consecutive insertManyZeros calls", async () => {
                jsInsertZeros(3)
                await skinnyIMTTest.insertManyZeros(3)

                jsInsertZeros(5)
                await skinnyIMTTest.insertManyZeros(5)

                expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await skinnyIMTTest.size()).to.equal(8)
            })

            it("Should allow alternating non-zero inserts and insertManyZeros", async () => {
                jsLeanIMT.insert(1n)
                await skinnyIMTTest.insert(1)

                jsInsertZeros(2)
                await skinnyIMTTest.insertManyZeros(2)

                jsLeanIMT.insert(2n)
                await skinnyIMTTest.insert(2)

                jsInsertZeros(3)
                await skinnyIMTTest.insertManyZeros(3)

                expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await skinnyIMTTest.size()).to.equal(7)
            })

            it("Should let a non-zero leaf inserted before insertManyZeros still verify", async () => {
                jsLeanIMT.insert(42n)
                await skinnyIMTTest.insert(42)

                jsInsertZeros(6)
                await skinnyIMTTest.insertManyZeros(6)

                const { siblings } = jsLeanIMT.generateProof(0)
                expect(await skinnyIMTTest.verify(42, 0, siblings)).to.equal(true)
            })

            it("Should let a zero leaf inserted via insertManyZeros verify at its index", async () => {
                jsLeanIMT.insertMany([1n, 2n])
                await skinnyIMTTest.insertMany([1, 2])

                jsInsertZeros(3)
                await skinnyIMTTest.insertManyZeros(3)

                // zero appended at index 3 should be provable
                const { siblings } = jsLeanIMT.generateProof(3)
                expect(await skinnyIMTTest.verify(0, 3, siblings)).to.equal(true)
            })

            it("Should allow updating a zero leaf inserted via insertManyZeros (odd index)", async () => {
                // Update at an ODD index avoids jsLeanIMT.update's `if (sibling)` falsy-on-zero bug.
                jsLeanIMT.insertMany([1n, 2n])
                await skinnyIMTTest.insertMany([1, 2])

                jsInsertZeros(3)
                await skinnyIMTTest.insertManyZeros(3)

                // promote the zero at index 3 (odd) to 7
                const { siblings } = jsLeanIMT.generateProof(3)
                await skinnyIMTTest.update(0, 7, 3, siblings)
                jsLeanIMT.update(3, 7n)

                expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
            })
        })
    })

    describe("# insertManyRepeated", () => {
        it("Should reject a value >= SNARK_SCALAR_FIELD", async () => {
            const transaction = skinnyIMTTest.insertManyRepeated(SNARK_SCALAR_FIELD, 3)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should be a no-op when amount is 0", async () => {
            const before = await skinnyIMTTest.root()
            await skinnyIMTTest.insertManyRepeated(42, 0)

            expect(await skinnyIMTTest.root()).to.equal(before)
            expect(await skinnyIMTTest.size()).to.equal(0)
        })

        it("Should insert N copies of a non-zero value into an empty tree", async () => {
            const v = 42n
            const n = 7
            for (let i = 0; i < n; i++) jsLeanIMT.insert(v)

            await skinnyIMTTest.insertManyRepeated(v, n)

            expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
            expect(await skinnyIMTTest.size()).to.equal(n)
            expect(await skinnyIMTTest.depth()).to.equal(jsLeanIMT.depth)
        })

        it("Should append N copies of a value after pre-existing leaves", async () => {
            const v = 99n
            const n = 5
            jsLeanIMT.insertMany([1n, 2n, 3n])
            await skinnyIMTTest.insertMany([1, 2, 3])

            for (let i = 0; i < n; i++) jsLeanIMT.insert(v)
            await skinnyIMTTest.insertManyRepeated(v, n)

            expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
            expect(await skinnyIMTTest.size()).to.equal(3 + n)
        })

        it("Should produce the same root as insertManyZeros when value is 0", async () => {
            const n = 8
            await skinnyIMTTest.insertManyRepeated(0, n)

            const { contract: other } = await run("deploy:imt-test", { library: "SkinnyIMT", logs: false })
            await other.insertManyZeros(n)

            expect(await skinnyIMTTest.root()).to.equal(await other.root())
        })

        it("Should allow alternating values across calls", async () => {
            jsLeanIMT.insertMany([3n, 3n, 3n])
            await skinnyIMTTest.insertManyRepeated(3, 3)

            jsLeanIMT.insertMany([5n, 5n])
            await skinnyIMTTest.insertManyRepeated(5, 2)

            jsLeanIMT.insertMany([3n, 3n, 3n, 3n])
            await skinnyIMTTest.insertManyRepeated(3, 4)

            expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
            expect(await skinnyIMTTest.size()).to.equal(9)
        })

        it("Should match the root from individual inserts of the same value", async () => {
            const v = 7n
            const n = 13
            for (let i = 0; i < n; i++) jsLeanIMT.insert(v)

            await skinnyIMTTest.insertManyRepeated(v, n)

            expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
        })
    })

    describe("# precomputeRepeatedCache", () => {
        it("Should reject a value >= SNARK_SCALAR_FIELD", async () => {
            const transaction = skinnyIMTTest.precomputeRepeatedCache(SNARK_SCALAR_FIELD, 4)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should allow inserting a fuck ton of zeros in one tx. With pre-computed zeros", async () => {
            const transaction = skinnyIMTTest.precomputeRepeatedCache(0, 255)
            await skinnyIMTTest.insertManyZeros(2n**255n)
        })

        it("Should burn an even worse amount of gas (max-depth tree built in many TXs)", async () => {
            // Required: pre-cache zeros. ~10M gas on its own.
            await skinnyIMTTest.precomputeRepeatedCache(0, 255)

            // Bonus pre-caches we'll cash in below. Each ~10M gas. Three extra
            // values × 10M = ~30M gas burnt just on cache warming.
            await skinnyIMTTest.precomputeRepeatedCache(7, 255)
            await skinnyIMTTest.precomputeRepeatedCache(13, 255)
            await skinnyIMTTest.precomputeRepeatedCache(42, 255)

            // Fill the tree in five chunks instead of one. Each call rewalks
            // the full ~255 levels of sideNodes — the per-call gas hovers near
            // the block limit, so total burn ≫ a single insertManyZeros(2^255).
            //
            // Capacity ceiling: size = 2^255 (one more leaf would need depth
            // 256, where `2 ** treeDepth` overflows). The chunk sizes sum to
            // exactly 2^255: 2^254 + 2^253 + 2^252 + (2^252 - 1) + 1.
            await skinnyIMTTest.insertManyZeros(2n ** 254n)              // size 2^254,                depth 254
            await skinnyIMTTest.insertManyZeros(2n ** 253n)              // size 2^254 + 2^253,        depth 255
            await skinnyIMTTest.insertManyRepeated(7, 2n ** 252n)        // size 2^254 + 2^253 + 2^252
            await skinnyIMTTest.insertManyRepeated(13, 2n ** 252n - 1n)  // size 2^255 - 1
            await skinnyIMTTest.insertManyRepeated(42, 1)                // size 2^255 (uses _insert shortcut)

            expect(await skinnyIMTTest.size()).to.equal(2n ** 255n)
            expect(await skinnyIMTTest.depth()).to.equal(255)
        })

        it("Should be a no-op when upToLevel is 0", async () => {
            await skinnyIMTTest.precomputeRepeatedCache(7, 0)
            // No state side-effects to observe directly; just verify it doesn't revert
            // and the tree is still empty.
            expect(await skinnyIMTTest.size()).to.equal(0)
        })

        it("Should not change the root of a subsequent insertManyRepeated", async () => {
            // Same tree built two ways: cache pre-warmed vs cold. Both must produce
            // identical roots since the cache only memoises hash results.
            const v = 13n
            const n = 12

            await skinnyIMTTest.precomputeRepeatedCache(v, 10)
            await skinnyIMTTest.insertManyRepeated(v, n)
            const warmRoot = await skinnyIMTTest.root()

            const { contract: cold } = await run("deploy:imt-test", { library: "SkinnyIMT", logs: false })
            await cold.insertManyRepeated(v, n)

            expect(warmRoot).to.equal(await cold.root())
        })

        it("Should make a follow-up insertManyRepeated cheaper", async () => {
            // First call (cold cache) pays SSTOREs to populate cache; second call
            // (warm cache) just SLOADs. Compare a fresh tree's cold call to a
            // pre-warmed tree's call on the same fresh state.
            const v = 21n
            const n = 50

            const { contract: cold } = await run("deploy:imt-test", { library: "SkinnyIMT", logs: false })
            const coldTx = await (await cold.insertManyRepeated(v, n)).wait()

            const { contract: warm } = await run("deploy:imt-test", { library: "SkinnyIMT", logs: false })
            await warm.precomputeRepeatedCache(v, 6)
            const warmTx = await (await warm.insertManyRepeated(v, n)).wait()

            expect(warmTx!.gasUsed).to.be.lessThan(coldTx!.gasUsed)
            expect(await warm.root()).to.equal(await cold.root())
        })
    })

    describe("# update", () => {
        it("Should not update a leaf if the leaf does not exist", async () => {
            const transaction = skinnyIMTTest.update(2, 1, 0, [1, 2, 3, 4])

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "WrongSiblingNodes")
        })

        it("Should not update a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
            const transaction = skinnyIMTTest.update(2, SNARK_SCALAR_FIELD, 0, [1, 2, 3, 4])

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should update a leaf if that's the only leaf in the tree", async () => {
            await skinnyIMTTest.insert(1)
            jsLeanIMT.insert(BigInt(1))

            const { siblings } = jsLeanIMT.generateProof(0)

            await skinnyIMTTest.update(1, 2, 0, siblings)
            jsLeanIMT.update(0, BigInt(2))

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should update a leaf if there's more than 1 leaf in the tree", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(0)

            await skinnyIMTTest.update(1, 3, 0, siblings)

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

            await skinnyIMTTest.update(oldLeaf, newLeaf, 0, siblings)
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

            const transaction = skinnyIMTTest.update(1, 3, 0, siblings)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should not update a leaf if its index is odd and the value of at least one sibling node is >= SNARK_SCALAR_FIELD", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(1, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(1)

            siblings[0] = SNARK_SCALAR_FIELD

            const transaction = skinnyIMTTest.update(2, 3, 1, siblings)

            await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
        })

        it("Should not update a leaf if the siblings are wrong", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
            jsLeanIMT.update(0, BigInt(3))

            const { siblings } = jsLeanIMT.generateProof(0)

            siblings[0] = BigInt(3)

            const transaction = skinnyIMTTest.update(1, 3, 0, siblings)

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

                await skinnyIMTTest.update(i + 1, i + 7, i, siblings)

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
                await skinnyIMTTest.update(i + 1, i + 10, i, siblings)
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
    describe("# update to 0", () => {
        it("Should update a leaf to be 0", async () => {
            await skinnyIMTTest.insert(1)
            await skinnyIMTTest.insert(2)
            await skinnyIMTTest.insert(3)

            jsLeanIMT.insertMany([BigInt(1), BigInt(2), BigInt(3)])
            jsLeanIMT.update(2, BigInt(0))

            const { siblings } = jsLeanIMT.generateProof(2)

            await skinnyIMTTest.update(3, 0, 2, siblings)

            const root = await skinnyIMTTest.root()

            expect(root).to.equal(jsLeanIMT.root)
        })

        it("Should update 10 leafs to be 0", async () => {
            for (let i = 0; i < 10; i += 1) {
                jsLeanIMT.insert(BigInt(i + 1))

                await skinnyIMTTest.insert(i + 1)
            }

            for (let i = 0; i < 10; i += 1) {
                jsLeanIMT.update(i, BigInt(0))

                const { siblings } = jsLeanIMT.generateProof(i)

                await skinnyIMTTest.update(i + 1, 0, i, siblings)

                const root = await skinnyIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            }
        })
    })

    describe("# verify", () => {
        it("Should return true because the node is in the tree", async () => {
            await skinnyIMTTest.insert(1)
            jsLeanIMT.insert(1n)
            const proof = jsLeanIMT.generateProof(0)
            const hasLeaf = await skinnyIMTTest.verify(1, 0, proof.siblings)

            expect(hasLeaf).to.equal(true)
        })

        it("Should return false because the node is not the tree", async () => {
            jsLeanIMT.insert(2n)
            const proof = jsLeanIMT.generateProof(0)
            const hasLeaf = await skinnyIMTTest.verify(2, 0, proof.siblings)

            expect(hasLeaf).to.equal(false)
        })

        it("Should return true if the leaf is 0", async () => {
            await skinnyIMTTest.insertMany([1, 2])
            jsLeanIMT.insertMany([BigInt(1), BigInt(2)])

            jsLeanIMT.update(1, BigInt(0))

            const { siblings } = jsLeanIMT.generateProof(1)

            await skinnyIMTTest.update(2, 0, 1, siblings)

            const proof = jsLeanIMT.generateProof(1)
            const hasLeaf = await skinnyIMTTest.verify(0, 1, proof.siblings)

            expect(hasLeaf).to.equal(true)
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

            await skinnyIMTTest.update(1, 0, 0, siblings)
            const proof = jsLeanIMT.generateProof(0)
            expect(await skinnyIMTTest.verify(0, 0, proof.siblings)).to.equal(true)
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
            await skinnyIMTTest.update(1, 0, 0, siblings)

            jsLeanIMT.update(0, BigInt(3))
            const { siblings: newSiblings } = jsLeanIMT.generateProof(0)
            await skinnyIMTTest.update(0, 3, 0, newSiblings)

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
            await skinnyIMTTest.update(1, 2, 0, siblings)

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
            await skinnyIMTTest.update(1, 5, 1, siblings)

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
            await skinnyIMTTest.update(1, 5, 1, siblings)

            // leaves[1] is now cleared — the first occurrence at index 0 (still value 1)
            // is permanently orphaned, has(1) returns false even though 1 exists at index 0
            const proof = jsLeanIMT.generateProof(0)
            expect(await skinnyIMTTest.verify(1, 0, proof.siblings)).to.equal(true)
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
