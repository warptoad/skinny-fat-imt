import { LeanIMT as JSLeanIMT } from "@zk-kit/lean-imt"
import { expect } from "chai"
import { run } from "hardhat"

export interface FatIMTTestConfig {
    deployTaskName: string
    libraryName: string
    hashFn: (a: bigint, b: bigint) => bigint
    hasSnarkFieldCheck?: boolean
}

export function runFatIMTTests(config: FatIMTTestConfig) {
    const { deployTaskName, libraryName, hashFn, hasSnarkFieldCheck = true } = config

    describe("FatIMT", () => {
        const SNARK_SCALAR_FIELD = BigInt(
            "21888242871839275222246405745257275088548364400416034343698204186575808495617"
        )
        let fatIMTTest: any
        let fatIMT: any
        let jsLeanIMT: JSLeanIMT

        beforeEach(async () => {
            const { library, contract } = await run(deployTaskName, {
                library: libraryName,
                logs: false
            })

            fatIMTTest = contract
            fatIMT = library
            jsLeanIMT = new JSLeanIMT((a, b) => hashFn(a, b))
        })

        describe("# insert", () => {
            if (hasSnarkFieldCheck) {
                it("Should not insert a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = fatIMTTest.insert(SNARK_SCALAR_FIELD)

                    await expect(transaction).to.be.revertedWithCustomError(fatIMT, "LeafGreaterThanSnarkScalarField")
                })
            }

            it("Should insert a leaf", async () => {
                jsLeanIMT.insert(BigInt(1))

                await fatIMTTest.insert(1)

                const root = await fatIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should insert 10 leaves", async () => {
                for (let i = 0; i < 10; i += 1) {
                    jsLeanIMT.insert(BigInt(i + 1))

                    await fatIMTTest.insert(i + 1)

                    const root = await fatIMTTest.root()

                    expect(root).to.equal(jsLeanIMT.root)
                }
            })

            it("Should insert 128 leaves", async () => {
                for (let i = 0; i < 128; i += 1) {
                    jsLeanIMT.insert(BigInt(i + 1))

                    await fatIMTTest.insert(i + 1)

                    const root = await fatIMTTest.root()

                    expect(root).to.equal(jsLeanIMT.root)
                }
            })
        })

        describe("# insertMany", () => {
            if (hasSnarkFieldCheck) {
                it("Should not insert a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = fatIMTTest.insertMany([SNARK_SCALAR_FIELD])

                    await expect(transaction).to.be.revertedWithCustomError(fatIMT, "LeafGreaterThanSnarkScalarField")
                })
            }

            it("Should insert a leaf", async () => {
                jsLeanIMT.insert(BigInt(1))

                await fatIMTTest.insertMany([1])

                const root = await fatIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should insert 10 leaves", async () => {
                const elems: bigint[] = []
                for (let i = 0; i < 10; i += 1) {
                    elems.push(BigInt(i + 1))
                }

                jsLeanIMT.insertMany(elems)
                await fatIMTTest.insertMany(elems)

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should insert 18 leaves 8 times", async () => {
                const howMany = 18
                const howManyTimes = 8
                for (let index = 0; index < howManyTimes; index++) {
                    const elems = new Array(howMany).fill(0).map((v, i) => BigInt(index * howMany + i + 1))

                    jsLeanIMT.insertMany(elems)
                    await fatIMTTest.insertMany(elems)

                    const root = await fatIMTTest.root()
                    expect(root).to.equal(jsLeanIMT.root)
                }
            })

            it("Should insert many leaves when the tree is not empty", async () => {
                jsLeanIMT.insert(BigInt(1))

                await fatIMTTest.insert(BigInt(1))

                const elems: bigint[] = []
                for (let i = 1; i < 10; i += 1) {
                    elems.push(BigInt(i + 1))
                }

                jsLeanIMT.insertMany(elems)
                await fatIMTTest.insertMany(elems)

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })
        })

        describe("# insertManyRepeated", () => {
            // TODO: assert NewLeaf event emission. insertManyRepeated/insertManyZeros
            // should emit exactly `amount` NewLeaf events, one per leaf, with
            // (treeId, treeSize + i, leaf) for i in 0..amount. No test currently checks
            // events, which is why the loop bound bug (loop ran 0 iterations, emitted
            // nothing) passed all tests. Use `.to.emit(...).withArgs(...)` per leaf.
            if (hasSnarkFieldCheck) {
                it("Should reject a value >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = fatIMTTest.insertManyRepeated(SNARK_SCALAR_FIELD, 3)

                    await expect(transaction).to.be.revertedWithCustomError(fatIMT, "LeafGreaterThanSnarkScalarField")
                })
            }

            it("Should be a no-op when amount is 0", async () => {
                const before = await fatIMTTest.root()
                await fatIMTTest.insertManyRepeated(42, 0)

                expect(await fatIMTTest.root()).to.equal(before)
                expect(await fatIMTTest.size()).to.equal(0)
            })

            it("Should insert N copies of a non-zero value into an empty tree", async () => {
                const v = 42n
                const n = 7
                for (let i = 0; i < n; i++) jsLeanIMT.insert(v)

                await fatIMTTest.insertManyRepeated(v, n)

                expect(await fatIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await fatIMTTest.size()).to.equal(n)
                expect(await fatIMTTest.depth()).to.equal(jsLeanIMT.depth)
            })

            it("Should append N copies of a value after pre-existing leaves", async () => {
                const v = 99n
                const n = 5
                jsLeanIMT.insertMany([1n, 2n, 3n])
                await fatIMTTest.insertMany([1, 2, 3])

                for (let i = 0; i < n; i++) jsLeanIMT.insert(v)
                await fatIMTTest.insertManyRepeated(v, n)

                expect(await fatIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await fatIMTTest.size()).to.equal(3 + n)
            })

            it("Should allow alternating values across calls", async () => {
                jsLeanIMT.insertMany([3n, 3n, 3n])
                await fatIMTTest.insertManyRepeated(3, 3)

                jsLeanIMT.insertMany([5n, 5n])
                await fatIMTTest.insertManyRepeated(5, 2)

                jsLeanIMT.insertMany([3n, 3n, 3n, 3n])
                await fatIMTTest.insertManyRepeated(3, 4)

                expect(await fatIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await fatIMTTest.size()).to.equal(9)
            })

            it("Should match the root from individual inserts of the same value", async () => {
                const v = 7n
                const n = 13
                for (let i = 0; i < n; i++) jsLeanIMT.insert(v)

                await fatIMTTest.insertManyRepeated(v, n)

                expect(await fatIMTTest.root()).to.equal(jsLeanIMT.root)
            })

            // The leftBoundary lift in _insertManyRepeated is guarded by
            //   if (leftEdgePosition != rightEdgePosition)
            // so it stops writing leftBoundaryNode once the boundary path has
            // converged with the rightmost path. These geometries each force the
            // convergence at a chosen level relative to newTreeDepth, so the skip
            // fires across a range of cases — single-level, multi-level, with and
            // without a dangling rightEdge subtree.
            describe("convergence-boundary geometries", () => {
                // Each row: (pre-existing leaf count, repeat count, expected convergence L, expected newTreeDepth)
                // pre is filled with [1, 2, ..., pre]; the repeat value is non-zero so the
                // _insertManyRepeated path (not _insertManyZeros) is exercised.
                const cases: { pre: number; n: number; L: number; depth: number; label: string }[] = [
                    { pre: 2, n: 2, L: 1, depth: 2, label: "convergence at level 1, top depth (single skip)" },
                    { pre: 4, n: 2, L: 1, depth: 3, label: "convergence at level 1, two levels skipped" },
                    { pre: 8, n: 2, L: 1, depth: 4, label: "convergence at level 1, three levels skipped" },
                    { pre: 16, n: 4, L: 2, depth: 5, label: "convergence at level 2 in a deeper tree" },
                    {
                        pre: 4,
                        n: 3,
                        L: 2,
                        depth: 3,
                        label: "rightEdge dangles past convergence (lastIndex=6, no leaf 7)"
                    },
                    { pre: 5, n: 3, L: 2, depth: 3, label: "convergence one level below the top" }
                ]

                for (const { pre, n, L, depth, label } of cases) {
                    it(`Should produce a correct root when ${label}`, async () => {
                        const v = 7n

                        if (pre > 0) {
                            const preLeaves = new Array(pre).fill(0).map((_, i) => BigInt(i + 1))
                            jsLeanIMT.insertMany(preLeaves)
                            await fatIMTTest.insertMany(preLeaves)
                        }

                        for (let i = 0; i < n; i++) jsLeanIMT.insert(v)
                        await fatIMTTest.insertManyRepeated(v, n)

                        // Sanity: the geometry really is what the case row claims.
                        // firstIndex = pre, lastIndex = pre + n - 1.
                        // Convergence level L = smallest level with (firstIndex >> L) == (lastIndex >> L).
                        const firstIndex = pre
                        const lastIndex = pre + n - 1
                        let convergence = 0
                        while (firstIndex >> convergence !== lastIndex >> convergence) convergence++
                        expect(convergence, "convergence level matches the case row").to.equal(L)
                        expect(await fatIMTTest.depth(), "newTreeDepth matches the case row").to.equal(depth)

                        expect(await fatIMTTest.root()).to.equal(jsLeanIMT.root)
                        expect(await fatIMTTest.size()).to.equal(pre + n)
                    })
                }

                it("Should produce a correct root when the skip fires across many levels (deep tree, tiny amount)", async () => {
                    // Build a tree to depth 6 (64 pre-existing leaves), then append 2 leaves.
                    // firstIndex=64, lastIndex=65, XOR=1, convergence L=1. newTreeDepth=7.
                    // The skip fires at levels 1..6 — five hashes saved per call.
                    const v = 99n
                    const pre = 64
                    const preLeaves = new Array(pre).fill(0).map((_, i) => BigInt(i + 1))
                    jsLeanIMT.insertMany(preLeaves)
                    await fatIMTTest.insertMany(preLeaves)

                    jsLeanIMT.insert(v)
                    jsLeanIMT.insert(v)
                    await fatIMTTest.insertManyRepeated(v, 2)

                    expect(await fatIMTTest.root()).to.equal(jsLeanIMT.root)
                    expect(await fatIMTTest.depth()).to.equal(7)
                })
            })
        })

        describe("# precomputeRepeatedCache", () => {
            // these do not fit within a single block because of the fat structure storing all node
            // it("Should allow inserting a fuck ton of zeros in one tx. With pre-computed zeros", async () => {
            //     await fatIMTTest.precomputeRepeatedCache(0, 255)
            //     await fatIMTTest.insertManyZeros(2n ** 255n)
            // })

            // it("Should burn worst-case gas for insertManyRepeated in one call (every shortcut defeated)", async () => {
            //     // The pre-optimisation upper bound was "insertManyZeros(2^255) into empty
            //     // tree with cache pre-warmed". Now that's a *best* case: every level hits
            //     // the canonical-chain shortcuts (leftBoundary == repeatedCenter, and
            //     // rightEdge == newSideNode == repeatedCenter), so each level is a cache
            //     // SLOAD plus a sideNode SSTORE — zero real hashes.
            //     //
            //     // To reconstruct an upper bound, defeat all three shortcuts so every
            //     // level pays two real hashes (one leftBoundary + one rightEdge):
            //     //
            //     //   1. leftBoundary shortcut needs leftBoundary == repeatedCenter (and
            //     //      oldSideNode == repeatedCenter on the right branch). Break it by
            //     //      making firstIndex odd AND sideNodes[0] != value, so the level-0
            //     //      hash is hash(oldSideNode != value, value). leftBoundary diverges
            //     //      from the canonical chain at level 0 and stays off it forever.
            //     //
            //     //   2. rightEdge shortcut needs newSideNode == rightEdge. Break it by
            //     //      making lastIndex even at level 0 so rightEdge dangles (stays =
            //     //      value while repeatedCenter advances). From level 1 onward
            //     //      newSideNode tracks the canonical repeatedCenter while rightEdge
            //     //      is off it, so the operands always differ.
            //     //
            //     //   3. Convergence skip only fires once firstIndex and lastIndex share
            //     //      top bits. With firstIndex=1 and lastIndex=2^D - 2 they only
            //     //      share the top zero bit, so the skip fires only at the very top
            //     //      and leftBoundary updates fire at D-1 levels.
            //     //
            //     // Geometry: pre-insert one leaf of value 7, then insertManyZeros of
            //     // (2^D - 2). That gives firstIndex=1 (odd), lastIndex=2^D-2 (even at
            //     // level 0), sideNodes[0]=7 (≠ 0). Resulting per-call work (warm cache):
            //     //   * D cache SLOADs (hits)
            //     //   * D-1 real leftBoundary hashes
            //     //   * D-1 real rightEdge hashes
            //     //   * D sideNode SSTOREs
            //     const D = 255n

            //     await fatIMTTest.precomputeRepeatedCache(0, D)
            //     await fatIMTTest.insert(7)
            //     await fatIMTTest.insertManyZeros(2n ** D - 2n)

            //     expect(await fatIMTTest.size()).to.equal(2n ** D - 1n)
            //     expect(await fatIMTTest.depth()).to.equal(D)
            // })

            if (hasSnarkFieldCheck) {
                it("Should reject a value >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = fatIMTTest.precomputeRepeatedCache(SNARK_SCALAR_FIELD, 4)

                    await expect(transaction).to.be.revertedWithCustomError(fatIMT, "LeafGreaterThanSnarkScalarField")
                })
            }

            it("Should be a no-op when upToLevel is 0", async () => {
                await fatIMTTest.precomputeRepeatedCache(7, 0)
                // No state side-effects to observe directly; just verify it doesn't revert
                // and the tree is still empty.
                expect(await fatIMTTest.size()).to.equal(0)
            })

            it("Should not change the root of a subsequent insertManyRepeated", async () => {
                // Same tree built two ways: cache pre-warmed vs cold. Both must produce
                // identical roots since the cache only memoises hash results.
                const v = 13n
                const n = 12

                await fatIMTTest.precomputeRepeatedCache(v, 10)
                await fatIMTTest.insertManyRepeated(v, n)
                const warmRoot = await fatIMTTest.root()

                const { contract: cold } = await run(deployTaskName, {
                    library: libraryName,
                    logs: false
                })
                await cold.insertManyRepeated(v, n)

                expect(warmRoot).to.equal(await cold.root())
            })

            it("Should make a follow-up insertManyRepeated cheaper", async () => {
                // First call (cold cache) pays SSTOREs to populate cache; second call
                // (warm cache) just SLOADs. Compare a fresh tree's cold call to a
                // pre-warmed tree's call on the same fresh state.
                const v = 21n
                const n = 50

                const { contract: cold } = await run(deployTaskName, {
                    library: libraryName,
                    logs: false
                })
                const coldTx = await (await cold.insertManyRepeated(v, n)).wait()

                const { contract: warm } = await run(deployTaskName, {
                    library: libraryName,
                    logs: false
                })
                await warm.precomputeRepeatedCache(v, 6)
                const warmTx = await (await warm.insertManyRepeated(v, n)).wait()

                expect(warmTx!.gasUsed).to.be.lessThan(coldTx!.gasUsed)
                expect(await warm.root()).to.equal(await cold.root())
            })
        })

        describe("# update", () => {
            // TODO(regression): `update` must revert when `index` is out of range.
            // Bug fixed in InternalFatIMT._update: there was no bounds check, so updating an
            // index >= size wrote phantom nodes and overwrote nodes[depth][0] (the root),
            // silently corrupting the tree. Add tests asserting (and that root() is unchanged
            // after each reverted call):
            //   - update(newLeaf, size)     reverts with "LeafDoesNotExist" (just past the edge)
            //   - update(newLeaf, size + 5) reverts with "LeafDoesNotExist"
            //   - update on an empty tree (size == 0) reverts with "LeafDoesNotExist"

            // TODO(regression): updating the rightmost *dangling* node must not corrupt later
            // inserts. Bug fixed in InternalFatIMT._update: a stray `self.nodes[level][index] = node`
            // (wrong index — should have been levelIndex) scribbled into an out-of-range slot at
            // levels >= 1. It was masked by append-only insert ordering, so the test must:
            //   - build a tree whose last leaf dangles at level >= 1 (e.g. size = 5),
            //   - update that rightmost leaf,
            //   - then insert enough leaves to reach the scribbled slot (e.g. up to index 10+),
            //   - and assert root() matches the reference (jsLeanIMT) at every step.

            // if (hasSnarkFieldCheck) {
            //     it("Should not update a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
            //         const transaction = fatIMTTest.update(2, SNARK_SCALAR_FIELD, 0, [1, 2, 3, 4])

            //         await expect(transaction).to.be.revertedWithCustomError(fatIMT, "LeafGreaterThanSnarkScalarField")
            //     })
            // }

            it("Should update a leaf if that's the only leaf in the tree", async () => {
                await fatIMTTest.insert(1)
                jsLeanIMT.insert(BigInt(1))

                const { siblings } = jsLeanIMT.generateProof(0)

                await fatIMTTest.update(2, 0)
                jsLeanIMT.update(0, BigInt(2))

                const root = await fatIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should update a leaf if there's more than 1 leaf in the tree", async () => {
                await fatIMTTest.insert(1)
                await fatIMTTest.insert(2)

                jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
                jsLeanIMT.update(0, BigInt(3))

                const { siblings } = jsLeanIMT.generateProof(0)

                await fatIMTTest.update(3, 0)

                const root = await fatIMTTest.root()

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
                    await fatIMTTest.insertMany(elems)

                    const root = await fatIMTTest.root()
                    expect(root).to.equal(jsLeanIMT.root)
                }
                const { siblings } = jsLeanIMT.generateProof(0)

                await fatIMTTest.update(newLeaf, 0)
                jsLeanIMT.update(jsLeanIMT.indexOf(oldLeaf), newLeaf)

                const root = await fatIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should update 6 leaves", async () => {
                for (let i = 0; i < 6; i += 1) {
                    jsLeanIMT.insert(BigInt(i + 1))

                    await fatIMTTest.insert(i + 1)
                }

                for (let i = 0; i < 6; i += 1) {
                    jsLeanIMT.update(i, BigInt(i + 7))

                    const { siblings } = jsLeanIMT.generateProof(i)

                    await fatIMTTest.update(i + 7, i)

                    const root = await fatIMTTest.root()

                    expect(root).to.equal(jsLeanIMT.root)
                }
            })

            it("Should maintain correct tree state after multiple updates and inserts", async () => {
                for (let i = 0; i < 5; i += 1) {
                    jsLeanIMT.insert(BigInt(i + 1))
                    await fatIMTTest.insert(i + 1)
                }

                for (let i = 0; i < 3; i += 1) {
                    jsLeanIMT.update(i, BigInt(i + 10))
                    const { siblings } = jsLeanIMT.generateProof(i)
                    await fatIMTTest.update(i + 10, i)
                }

                for (let i = 5; i < 8; i += 1) {
                    jsLeanIMT.insert(BigInt(i + 1))
                    await fatIMTTest.insert(i + 1)
                }

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })
        })

        // @TODO again double check this weird concept of update(leaf=0) as being a "remove"
        describe("# update to 0", () => {
            it("Should update a leaf to be 0", async () => {
                await fatIMTTest.insert(1)
                await fatIMTTest.insert(2)
                await fatIMTTest.insert(3)

                jsLeanIMT.insertMany([BigInt(1), BigInt(2), BigInt(3)])
                jsLeanIMT.update(2, BigInt(0))

                const { siblings } = jsLeanIMT.generateProof(2)

                await fatIMTTest.update(0, 2)

                const root = await fatIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should update 10 leafs to be 0", async () => {
                for (let i = 0; i < 10; i += 1) {
                    jsLeanIMT.insert(BigInt(i + 1))

                    await fatIMTTest.insert(i + 1)
                }

                for (let i = 0; i < 10; i += 1) {
                    jsLeanIMT.update(i, BigInt(0))

                    const { siblings } = jsLeanIMT.generateProof(i)

                    await fatIMTTest.update(0, i)

                    const root = await fatIMTTest.root()

                    expect(root).to.equal(jsLeanIMT.root)
                }
            })
        })

        describe("# verify", () => {
            it("Should return true because the node is in the tree", async () => {
                await fatIMTTest.insert(1)
                jsLeanIMT.insert(1n)
                const proof = jsLeanIMT.generateProof(0)
                const hasLeaf = await fatIMTTest.verify(1, 0, proof.siblings)

                expect(hasLeaf).to.equal(true)
            })

            it("Should return false because the node is not the tree", async () => {
                jsLeanIMT.insert(2n)
                const proof = jsLeanIMT.generateProof(0)
                const hasLeaf = await fatIMTTest.verify(2, 0, proof.siblings)

                expect(hasLeaf).to.equal(false)
            })

            it("Should return true if the leaf is 0", async () => {
                await fatIMTTest.insertMany([1, 2])
                jsLeanIMT.insertMany([BigInt(1), BigInt(2)])

                jsLeanIMT.update(1, BigInt(0))

                const { siblings } = jsLeanIMT.generateProof(1)

                await fatIMTTest.update(0, 1)

                const proof = jsLeanIMT.generateProof(1)
                const hasLeaf = await fatIMTTest.verify(0, 1, proof.siblings)

                expect(hasLeaf).to.equal(true)
            })
        })

        // These tests exist because naively removing the LeafCannotBeZero checks
        // introduced bugs in _insertMany (rightNode != 0 sentinel collision) and
        // _update (if (newLeaf != 0) guard skipping leaves[0] write).
        describe("zero inserts and updates test", () => {
            it("Should insert a leaf with value 0", async () => {
                jsLeanIMT.insert(BigInt(0))

                await fatIMTTest.insert(0)

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should insertMany with 0 as the only leaf", async () => {
                jsLeanIMT.insert(BigInt(0))

                await fatIMTTest.insertMany([0])

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should insertMany with 0 as the right child", async () => {
                // When forked from LeanIMT, naively removing the LeafCannotBeZero would break this
                // _insertMany used `if (rightNode != 0)` to detect a missing right child, which collided
                // with a real zero-valued leaf and treated it as dangling instead of hashing it.
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.insert(BigInt(0))

                await fatIMTTest.insertMany([1, 0])

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should track leaf 0 in has() after updating a leaf to 0", async () => {
                // When forked from LeanIMT, naively removing the LeafCannotBeZero would break this
                // _update had a `if (newLeaf != 0)` guard that skipped writing leaves[0],
                // so has(0) always returned false even after a leaf was updated to zero.
                await fatIMTTest.insert(1)
                jsLeanIMT.insert(BigInt(1))

                jsLeanIMT.update(0, BigInt(0))
                const { siblings } = jsLeanIMT.generateProof(0)

                await fatIMTTest.update(0, 0)
                const proof = jsLeanIMT.generateProof(0)
                expect(await fatIMTTest.verify(0, 0, proof.siblings)).to.equal(true)
            })

            it("Should allow updating leaf 0 after a leaf was updated to 0", async () => {
                // When forked from LeanIMT, naively removing the LeafCannotBeZero would break this
                // update uses _has(0) which would return false. Even though 0 was inserted.
                // this caused LeafDoesNotExist error, even though it is there!
                await fatIMTTest.insert(1)
                await fatIMTTest.insert(2)
                jsLeanIMT.insertMany([BigInt(1), BigInt(2)])

                jsLeanIMT.update(0, BigInt(0))
                const { siblings } = jsLeanIMT.generateProof(0)
                await fatIMTTest.update(0, 0)

                jsLeanIMT.update(0, BigInt(3))
                const { siblings: newSiblings } = jsLeanIMT.generateProof(0)
                await fatIMTTest.update(3, 0)

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })
        })

        // These tests exist because naively removing the LeafAlreadyExists checks
        // caused bugs — duplicate entries should be allowed and produce roots matching leanIMT.js.
        describe("duplicate entries test", () => {
            it("Should insert a duplicate leaf via insert", async () => {
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.insert(BigInt(1))

                await fatIMTTest.insert(1)
                await fatIMTTest.insert(1)

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should insert duplicate leaves via insertMany", async () => {
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.insert(BigInt(1))

                await fatIMTTest.insertMany([1, 1])

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should insert many duplicates across multiple insertMany calls", async () => {
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.insert(BigInt(2))
                jsLeanIMT.insert(BigInt(2))

                await fatIMTTest.insertMany([1, 1])
                await fatIMTTest.insertMany([2, 2])

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should update to an already existing leaf value", async () => {
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.insert(BigInt(2))
                jsLeanIMT.update(0, BigInt(2))

                await fatIMTTest.insert(1)
                await fatIMTTest.insert(2)

                const { siblings } = jsLeanIMT.generateProof(0)
                await fatIMTTest.update(2, 0)

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should insert a duplicate then update it", async () => {
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.update(1, BigInt(5))

                await fatIMTTest.insert(1)
                await fatIMTTest.insert(1)

                const { siblings } = jsLeanIMT.generateProof(1)
                await fatIMTTest.update(5, 1)

                const root = await fatIMTTest.root()
                expect(root).to.equal(jsLeanIMT.root)
            })

            it("Should still find the first occurrence after updating the last duplicate", async () => {
                // When forked from LeanIMT, naively removing the LeafAlreadyExists check caused this to break,
                // leaves were tracked as leave -> index in FatIMTData.leaves.
                // a duplicate insert would overwrite the index of the previous insert of that value
                // this causes update to use the wrong index
                await fatIMTTest.insert(1)
                await fatIMTTest.insert(1) // duplicate at index 1, leaves[1] overwritten to point here
                jsLeanIMT.insert(BigInt(1))
                jsLeanIMT.insert(BigInt(1))

                // update(1, 5) targets last occurrence (index 1) since leaves[1] points there
                jsLeanIMT.update(1, BigInt(5))
                const { siblings } = jsLeanIMT.generateProof(1)
                await fatIMTTest.update(5, 1)

                // leaves[1] is now cleared — the first occurrence at index 0 (still value 1)
                // is permanently orphaned, has(1) returns false even though 1 exists at index 0
                const proof = jsLeanIMT.generateProof(0)
                expect(await fatIMTTest.verify(1, 0, proof.siblings)).to.equal(true)
            })
        })

        describe("# root", () => {
            it("Should return the tree root", async () => {
                jsLeanIMT.insert(BigInt(1))

                await fatIMTTest.insert(1)

                const root = await fatIMTTest.root()

                expect(root).to.equal(jsLeanIMT.root)
            })
        })
    })
}
