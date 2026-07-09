import { LeanIMT as JSLeanIMT } from "@zk-kit/lean-imt"
import { expect } from "chai"
import { run } from "hardhat"

// @notice: js-leanIMT has a bug in insertMany that causes inserts to be skipped if the value is 0
// see: https://github.com/zk-kit/zk-kit/issues/419
// these test do a for loop on (regular) insert instead as a workaround

export interface SkinnyIMTTestConfig {
    deployTaskName: string
    libraryName: string
    hashFn: (a: bigint, b: bigint) => bigint
    hasSnarkFieldCheck?: boolean
    // Whether the library exposes `verifyMany` (the shared Merkle multiproof).
    hasVerifyMany?: boolean
    // Whether the library exposes `updateMany` (batch update via the shared multiproof).
    hasUpdateMany?: boolean
}

// Builds a shared (deduplicated) multiproof for `rawIndices` against `tree`, in
// the flat shape `_proofManyToRoot` expects:
//   - `leaves`: flat leaf values in ascending-index order.
//   - `leafIndexes`: the matching real tree indexes, aligned entry-for-entry.
//   - `siblings`: the flat, bottom-up / left-to-right proof-sibling stream (a
//     paired neighbour and a right-edge dangle cost nothing; everything else pulls one).
// Every leaf is fed in at level 0; the contract carries dangling nodes up itself
// from `edgeIndex`, so no per-level schedule is needed.
function generateMultiProof(
    tree: JSLeanIMT,
    rawIndices: number[]
): { leaves: bigint[]; leafIndexes: number[]; siblings: bigint[] } {
    const indices = [...new Set(rawIndices)].sort((a, b) => a - b)
    // `_nodes[level][position]` holds every computed node; it isn't in the public typings.
    const nodes = (tree as any)._nodes as bigint[][]
    const size = tree.size
    const depth = tree.depth

    // --- proofSiblings: climb the known set from level 0 and collect a sibling
    //     only where the contract reads one from the stream. ---
    let knownPositions = indices.slice()
    let levelSize = size
    const siblings: bigint[] = []
    for (let level = 0; level < depth; level += 1) {
        const parentPositions: number[] = []
        let readCursor = 0
        while (readCursor < knownPositions.length) {
            const childPosition = knownPositions[readCursor]
            if (childPosition % 2 === 0) {
                // left child
                if (childPosition + 1 >= levelSize) {
                    // dangle: rightmost node of the level, no sibling to supply
                } else if (
                    readCursor + 1 < knownPositions.length &&
                    knownPositions[readCursor + 1] === childPosition + 1
                ) {
                    // pair: the next known node is the right sibling, nothing to supply
                    readCursor += 1
                } else {
                    // proof: the contract reads this right sibling from the stream
                    siblings.push(nodes[level][childPosition + 1])
                }
            } else {
                // right child: the contract always reads the left sibling
                siblings.push(nodes[level][childPosition - 1])
            }
            parentPositions.push(Math.floor(childPosition / 2))
            readCursor += 1
        }
        knownPositions = parentPositions
        levelSize = Math.ceil(levelSize / 2)
    }

    return {
        leaves: indices.map((idx) => tree.leaves[idx]),
        leafIndexes: indices,
        siblings
    }
}

export function runSkinnyIMTTests(config: SkinnyIMTTestConfig) {
    const {
        deployTaskName,
        libraryName,
        hashFn,
        hasSnarkFieldCheck = true,
        hasVerifyMany = false,
        hasUpdateMany = false
    } = config

    describe("SkinnyIMT", () => {
        const SNARK_SCALAR_FIELD = BigInt(
            "21888242871839275222246405745257275088548364400416034343698204186575808495617"
        )
        let skinnyIMTTest: any
        let skinnyIMT: any
        let jsLeanIMT: JSLeanIMT

        beforeEach(async () => {
            const { library, contract } = await run(deployTaskName, {
                library: libraryName,
                logs: false
            })

            skinnyIMTTest = contract
            skinnyIMT = library
            jsLeanIMT = new JSLeanIMT((a, b) => hashFn(a, b))
        })

        // verify/verifyMany return a bool. These helpers always send a real tx (so the
        // call lands in the gas report) and then read the boolean result back via a
        // static call, since awaiting a state-changing call resolves to a tx response,
        // not the bool. This requires the test contract to expose verify/verifyMany as
        // non-view txs (as the poseidon2 suite does); the `.wait()` fails on a `view` one.
        async function callVerify(leaf: any, index: any, siblings: any): Promise<boolean> {
            await (await skinnyIMTTest.verify(leaf, index, siblings)).wait()
            return skinnyIMTTest.verify.staticCall(leaf, index, siblings)
        }

        async function callVerifyMany(leaves: any, leafIndexes: any, siblings: any): Promise<boolean> {
            await (await skinnyIMTTest.verifyMany(leaves, leafIndexes, siblings)).wait()
            return skinnyIMTTest.verifyMany.staticCall(leaves, leafIndexes, siblings)
        }

        describe("# insert", () => {
            if (hasSnarkFieldCheck) {
                it("Should not insert a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = skinnyIMTTest.insert(SNARK_SCALAR_FIELD)

                    await expect(transaction).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "LeafGreaterThanSnarkScalarField"
                    )
                })
            }

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
            if (hasSnarkFieldCheck) {
                it("Should not insert a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = skinnyIMTTest.insertMany([SNARK_SCALAR_FIELD])

                    await expect(transaction).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "LeafGreaterThanSnarkScalarField"
                    )
                })
            }

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

        describe("# insertManyRepeated", () => {
            if (hasSnarkFieldCheck) {
                it("Should reject a value >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = skinnyIMTTest.insertManyRepeated(SNARK_SCALAR_FIELD, 3)

                    await expect(transaction).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "LeafGreaterThanSnarkScalarField"
                    )
                })
            }

            it("Should be a no-op when amount is 0", async () => {
                const before = await skinnyIMTTest.root()
                await skinnyIMTTest.insertManyRepeated(42, 0)

                expect(await skinnyIMTTest.root()).to.equal(before)
                expect(await skinnyIMTTest.size()).to.equal(0)
            })

            it("Should insert N copies of a non-zero value into an empty tree", async () => {
                const value = 42n
                const amountLeafs = 7
                for (let i = 0; i < amountLeafs; i++) jsLeanIMT.insert(value)

                await skinnyIMTTest.insertManyRepeated(value, amountLeafs)

                expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                expect(await skinnyIMTTest.size()).to.equal(amountLeafs)
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
                            await skinnyIMTTest.insertMany(preLeaves)
                        }

                        for (let i = 0; i < n; i++) jsLeanIMT.insert(v)
                        await skinnyIMTTest.insertManyRepeated(v, n)

                        // Sanity: the geometry really is what the case row claims.
                        // firstIndex = pre, lastIndex = pre + n - 1.
                        // Convergence level L = smallest level with (firstIndex >> L) == (lastIndex >> L).
                        const firstIndex = pre
                        const lastIndex = pre + n - 1
                        let convergence = 0
                        while (firstIndex >> convergence !== lastIndex >> convergence) convergence++
                        expect(convergence, "convergence level matches the case row").to.equal(L)
                        expect(await skinnyIMTTest.depth(), "newTreeDepth matches the case row").to.equal(depth)

                        expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                        expect(await skinnyIMTTest.size()).to.equal(pre + n)
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
                    await skinnyIMTTest.insertMany(preLeaves)

                    jsLeanIMT.insert(v)
                    jsLeanIMT.insert(v)
                    await skinnyIMTTest.insertManyRepeated(v, 2)

                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                    expect(await skinnyIMTTest.depth()).to.equal(7)
                })
            })
        })

        describe("# precomputeRepeatedCache", () => {
            it("Should allow inserting a fuck ton of zeros in one tx. With pre-computed zeros", async () => {
                await skinnyIMTTest.precomputeRepeatedCache(0, 255)
                await skinnyIMTTest.insertManyRepeated(0, 2n ** 255n)
            })

            it("Should burn worst-case gas for insertManyRepeated in one call (every shortcut defeated)", async () => {
                // The pre-optimisation upper bound was "insertManyZeros(2^255) into empty
                // tree with cache pre-warmed". Now that's a *best* case: every level hits
                // the canonical-chain shortcuts (leftBoundary == repeatedCenter, and
                // rightEdge == newSideNode == repeatedCenter), so each level is a cache
                // SLOAD plus a sideNode SSTORE — zero real hashes.
                //
                // To reconstruct an upper bound, defeat all three shortcuts so every
                // level pays two real hashes (one leftBoundary + one rightEdge):
                //
                //   1. leftBoundary shortcut needs leftBoundary == repeatedCenter (and
                //      oldSideNode == repeatedCenter on the right branch). Break it by
                //      making firstIndex odd AND sideNodes[0] != value, so the level-0
                //      hash is hash(oldSideNode != value, value). leftBoundary diverges
                //      from the canonical chain at level 0 and stays off it forever.
                //
                //   2. rightEdge shortcut needs newSideNode == rightEdge. Break it by
                //      making lastIndex even at level 0 so rightEdge dangles (stays =
                //      value while repeatedCenter advances). From level 1 onward
                //      newSideNode tracks the canonical repeatedCenter while rightEdge
                //      is off it, so the operands always differ.
                //
                //   3. Convergence skip only fires once firstIndex and lastIndex share
                //      top bits. With firstIndex=1 and lastIndex=2^D - 2 they only
                //      share the top zero bit, so the skip fires only at the very top
                //      and leftBoundary updates fire at D-1 levels.
                //
                // Geometry: pre-insert one leaf of value 7, then insertManyZeros of
                // (2^D - 2). That gives firstIndex=1 (odd), lastIndex=2^D-2 (even at
                // level 0), sideNodes[0]=7 (≠ 0). Resulting per-call work (warm cache):
                //   * D cache SLOADs (hits)
                //   * D-1 real leftBoundary hashes
                //   * D-1 real rightEdge hashes
                //   * D sideNode SSTOREs
                const D = 255n

                await skinnyIMTTest.precomputeRepeatedCache(0, D)
                await skinnyIMTTest.insert(7)
                await skinnyIMTTest.insertManyRepeated(0, 2n ** D - 2n)

                expect(await skinnyIMTTest.size()).to.equal(2n ** D - 1n)
                expect(await skinnyIMTTest.depth()).to.equal(D)
            })

            if (hasSnarkFieldCheck) {
                it("Should reject a value >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = skinnyIMTTest.precomputeRepeatedCache(SNARK_SCALAR_FIELD, 4)

                    await expect(transaction).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "LeafGreaterThanSnarkScalarField"
                    )
                })
            }

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
            it("Should not update a leaf if the leaf does not exist", async () => {
                const transaction = skinnyIMTTest.update(2, 1, 0, [1, 2, 3, 4])

                await expect(transaction).to.be.revertedWithCustomError(skinnyIMT, "WrongSiblingNodes")
            })

            if (hasSnarkFieldCheck) {
                it("Should not update a leaf if its value is >= SNARK_SCALAR_FIELD", async () => {
                    const transaction = skinnyIMTTest.update(2, SNARK_SCALAR_FIELD, 0, [1, 2, 3, 4])

                    await expect(transaction).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "LeafGreaterThanSnarkScalarField"
                    )
                })
            }

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

            if (hasSnarkFieldCheck) {
                it("Should not update a leaf if its index is even and the value of at least one sibling node is >= SNARK_SCALAR_FIELD", async () => {
                    await skinnyIMTTest.insert(1)
                    await skinnyIMTTest.insert(2)

                    jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
                    jsLeanIMT.update(0, BigInt(3))

                    const { siblings } = jsLeanIMT.generateProof(0)

                    siblings[0] = SNARK_SCALAR_FIELD

                    const transaction = skinnyIMTTest.update(1, 3, 0, siblings)

                    await expect(transaction).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "LeafGreaterThanSnarkScalarField"
                    )
                })

                it("Should not update a leaf if its index is odd and the value of at least one sibling node is >= SNARK_SCALAR_FIELD", async () => {
                    await skinnyIMTTest.insert(1)
                    await skinnyIMTTest.insert(2)

                    jsLeanIMT.insertMany([BigInt(1), BigInt(2)])
                    jsLeanIMT.update(1, BigInt(3))

                    const { siblings } = jsLeanIMT.generateProof(1)

                    siblings[0] = SNARK_SCALAR_FIELD

                    const transaction = skinnyIMTTest.update(2, 3, 1, siblings)

                    await expect(transaction).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "LeafGreaterThanSnarkScalarField"
                    )
                })
            }

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

            it("Should not clobber a non-frontier side node when updating (size 11, then insert)", async () => {
                // Regression guard for the sideNodes refresh condition in _update.
                //
                // In a size-11 tree the live side node at level 1 is H(idx8, idx9) — that's the
                // left sibling the next insert (idx 11) hashes against. Updating index 0 recomputes
                // H(idx0, idx1) at level 1, but index 0 does NOT share a parent with the last leaf
                // there, so sideNodes[1] must be left alone.
                //
                // The real condition (`leafIndex >> (level+1) == edgeIndex >> (level+1)`) knows that
                // and skips the write. A liveness-only stand-in such as `(edgeIndex >> level) & 1`
                // fires here (the edge is at an odd position at level 1) and overwrites sideNodes[1]
                // with H(idx0, idx1). The corruption is invisible right after the update — it only
                // surfaces when the next insert reads that slot and the root diverges.
                for (let i = 0; i < 11; i += 1) {
                    jsLeanIMT.insert(BigInt(i + 1))
                    await skinnyIMTTest.insert(i + 1)
                }

                const { siblings } = jsLeanIMT.generateProof(0)
                await skinnyIMTTest.update(1, 99, 0, siblings)
                jsLeanIMT.update(0, 99n)

                // Still correct here: the update reconstructs index 0's own path fine.
                expect(await skinnyIMTTest.root(), "root immediately after update").to.equal(jsLeanIMT.root)

                // The next insert hashes against sideNodes[1]; a clobbered slot diverges here.
                jsLeanIMT.insert(12n)
                await skinnyIMTTest.insert(12)
                expect(await skinnyIMTTest.root(), "root after a later insert").to.equal(jsLeanIMT.root)
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
            // Verifies `value` against the on-chain tree using its REAL (raw) array
            // position -- jsLeanIMT.indexOf(value) -- NOT the compacted proof.index.
            // The siblings are exactly what zk-kit supplies (dangle levels omitted).
            async function verifyByRealIndex(value: bigint): Promise<boolean> {
                const realIndex = jsLeanIMT.indexOf(value)
                const { siblings } = jsLeanIMT.generateProof(realIndex)
                return callVerify(value, realIndex, siblings)
            }

            it("Should return true because the node is in the tree", async () => {
                await skinnyIMTTest.insert(1)
                jsLeanIMT.insert(1n)

                expect(await verifyByRealIndex(1n)).to.equal(true)
            })

            it("Should return false because the node is not the tree", async () => {
                // should insert something other wise, treeSize == 0 and _proofToRoot reverts with "TreeEmpty"
                await skinnyIMTTest.insert(1)
                jsLeanIMT.insert(2n)
                const proof = jsLeanIMT.generateProof(0)
                const hasLeaf = await callVerify(2, 0, proof.siblings)

                expect(hasLeaf).to.equal(false)
            })

            it("Should return true if the leaf is 0", async () => {
                await skinnyIMTTest.insertMany([1, 2])
                jsLeanIMT.insertMany([BigInt(1), BigInt(2)])

                jsLeanIMT.update(1, BigInt(0))

                const { siblings } = jsLeanIMT.generateProof(1)
                await skinnyIMTTest.update(2, 0, 1, siblings)

                // leaf 0 sits at real index 1
                expect(await verifyByRealIndex(0n)).to.equal(true)
            })

            it("Should verify a dense interior leaf by its real index", async () => {
                jsLeanIMT.insertMany([1n, 2n, 3n, 4n])
                await skinnyIMTTest.insertMany([1, 2, 3, 4])

                // leaf 3 -> real index 2; a sibling exists at every level (raw == compacted)
                expect(await verifyByRealIndex(3n)).to.equal(true)
            })

            // --- Dangling right-edge leaves. The proof SKIPS a level (a rightmost
            // left child that bubbles up), so the raw array index differs from the
            // compacted proof.index. A naive `index >> (treeDepth - siblings.length)`
            // shift lands on the wrong root here, because the skipped level is NOT the
            // lowest one -- there is a real "right turn" below the skip.

            it("Should verify a dangling right-edge leaf with a real turn below the skip (size 6)", async () => {
                // leaf 6 -> real index 5
                //   level 0: right child (pairs with leaf 5) -> real sibling
                //   level 1: rightmost left child            -> DANGLE (skipped)
                //   level 2: right child                     -> real sibling
                // raw index    = 5 (101)
                // compacted    = 3  (11)   <- proof.index
                // naive 5 >> 1 = 2  (10)   <- WRONG
                jsLeanIMT.insertMany([1n, 2n, 3n, 4n, 5n, 6n])
                await skinnyIMTTest.insertMany([1, 2, 3, 4, 5, 6])

                expect(await verifyByRealIndex(6n)).to.equal(true)
            })

            it("Should verify a dangling right-edge leaf skipped higher up the tree (size 12)", async () => {
                // leaf 12 -> real index 11
                //   level 0: right child          -> real sibling
                //   level 1: right child          -> real sibling
                //   level 2: rightmost left child -> DANGLE (skipped)
                //   level 3: right child          -> real sibling
                // raw index     = 11 (1011)
                // compacted     =  7  (111)  <- proof.index
                // naive 11 >> 1 =  5  (101)  <- WRONG
                const values = Array.from({ length: 12 }, (_, i) => i + 1)
                jsLeanIMT.insertMany(values.map((v) => BigInt(v)))
                await skinnyIMTTest.insertMany(values)

                expect(await verifyByRealIndex(12n)).to.equal(true)
            })
        })

        if (hasVerifyMany) {
            describe("# verifyMany", () => {
                // Cross-checks the shared multiproof against N independent single-leaf
                // proofs: both must agree the leaves are in the tree.
                async function insertRange(count: number) {
                    const elems = new Array(count).fill(0).map((_, i) => BigInt(i + 1))
                    jsLeanIMT.insertMany(elems)
                    await skinnyIMTTest.insertMany(elems)
                }

                it("Should verify a single leaf (degenerate multiproof)", async () => {
                    await insertRange(1)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [0])
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })

                it("Should verify several leaves in a balanced tree", async () => {
                    await insertRange(8)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })

                it("Should verify adjacent leaves that share a parent", async () => {
                    await insertRange(8)

                    // 2 and 3 pair directly, so no sibling is supplied between them.
                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [2, 3])
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })

                it("Should verify every leaf with an empty sibling list", async () => {
                    await insertRange(8)

                    const all = new Array(8).fill(0).map((_, i) => i)
                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, all)
                    // When all leaves are supplied, nothing is left to provide.
                    expect(siblings.length).to.equal(0)
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })

                it("Should verify a dangling right-edge leaf in an odd-sized tree", async () => {
                    // 3 leaves: leaf 2 dangles, so it sits above level 0.
                    await insertRange(3)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [0, 2])
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })

                it("Should verify a spread-out batch in a non-power-of-two tree", async () => {
                    // size 13: leaf 12 (the last leaf) dangles and sits at level 2 -> [11,11,12,12,12].
                    await insertRange(13)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [0, 5, 9, 12])
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })

                it("Should verify four odd-indexed leaves scattered across a size-12 tree", async () => {
                    // size 12 (even leaf count, edgeIndex 11 is odd) -> nothing dangles, so every leaf
                    // including 11 sits at level 0. Indexes 1,3,9,11 are all right children at level 0.
                    await insertRange(12)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 3, 9, 11])
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })

                it("Should match a batch built after inserts and an update", async () => {
                    await insertRange(6)
                    jsLeanIMT.update(2, 0n)
                    const { siblings: updateSiblings } = jsLeanIMT.generateProof(2)
                    await skinnyIMTTest.update(3, 0, 2, updateSiblings)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 2, 4])
                    // None is the last leaf, so all three sit at level 0; index 2 is now 0.
                    expect(leaves[1]).to.equal(0n)
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })

                it("Should return false when a leaf value is wrong", async () => {
                    await insertRange(8)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                    const tampered = [...leaves]
                    tampered[0] = leaves[0] + 1n
                    expect(await callVerifyMany(tampered, leafIndexes, siblings)).to.equal(false)
                })

                it("Should return false when a sibling is wrong", async () => {
                    await insertRange(8)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                    const tampered = [...siblings]
                    tampered[0] = siblings[0] + 1n
                    expect(await callVerifyMany(leaves, leafIndexes, tampered)).to.equal(false)
                })

                // NOTE: out-of-range and unsorted indexes are intentionally NOT rejected —
                // neither can forge a false membership (a scrambled climb just yields a
                // non-matching root -> false, or reverts on an out-of-bounds read). Length
                // and sibling-count well-formedness ARE enforced: a surplus leafIndex or a
                // leftover sibling would let a caller believe something was proven that never
                // actually entered a hash.

                it("Should revert when leaves and leafIndexes lengths differ", async () => {
                    await insertRange(8)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                    // More indexes than leaves: without a length guard the surplus index is
                    // silently never folded, so a caller would think it was proven when it wasn't.
                    await expect(
                        skinnyIMTTest.verifyMany(leaves, [...leafIndexes, 5], siblings)
                    ).to.be.revertedWithCustomError(skinnyIMT, "WrongMultiProof")
                })

                it("Should revert when an extra sibling is supplied", async () => {
                    await insertRange(8)

                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                    // A leftover sibling is a node the proof never hashes against anything, so
                    // it is never checked to be part of the tree — reject rather than ignore it.
                    await expect(
                        skinnyIMTTest.verifyMany(leaves, leafIndexes, [...siblings, 123n])
                    ).to.be.revertedWithCustomError(skinnyIMT, "WrongMultiProof")
                })

                it("Should revert when the batch is empty", async () => {
                    await insertRange(8)

                    await expect(skinnyIMTTest.verifyMany([], [], [])).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "WrongMultiProof"
                    )
                })

                if (hasSnarkFieldCheck) {
                    it("Should reject a leaf >= SNARK_SCALAR_FIELD", async () => {
                        await insertRange(8)

                        const { leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                        await expect(
                            skinnyIMTTest.verifyMany([1n, SNARK_SCALAR_FIELD], leafIndexes, siblings)
                        ).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
                    })
                }

                // The multiproof once let the caller choose, per level, when each claimed leaf
                // entered the climb (`leavesLevelIndexes`). A leaf injected above level 0 was folded
                // upward WITHOUT being hashed from the bottom, so — with no leaf/internal domain
                // separation — a caller could pass an internal-node value off as a member leaf (and,
                // relatedly, claim the edge leaf at a wrong index). That schedule is gone: every leaf
                // now enters at level 0 and is hashed up, so a bad value or a wrong index simply
                // yields a non-matching root. This test pins that an internal node can't verify.
                it("Should reject an internal-node value passed off as a leaf", async () => {
                    // Honest proof of leaves at indexes 0 and 2, then swap the value at index 2 for the
                    // internal node H(3,4). Because it is hashed up from level 0 like any leaf, the
                    // computed root no longer matches -> false. It can no longer be smuggled in un-hashed.
                    await insertRange(4)
                    const honest = generateMultiProof(jsLeanIMT, [0, 2])
                    const withInternalNode = [honest.leaves[0], hashFn(3n, 4n)]
                    expect(await callVerifyMany(withInternalNode, honest.leafIndexes, honest.siblings)).to.equal(false)
                })

                it("Should accept an honest proof of two paired leaves in an odd tree", async () => {
                    // Regression for the earlier stale-slot bug: in tree [1,2,3] the proof of {0,1} reaches
                    // a level where the lone live node is an even non-edge node; it must pair correctly and
                    // not mis-read a stale slot (which used to skip a sibling and wrongly revert).
                    await insertRange(3)
                    const { leaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [0, 1])
                    expect(await callVerifyMany(leaves, leafIndexes, siblings)).to.equal(true)
                })
            })
        }

        if (hasUpdateMany) {
            describe("# updateMany", () => {
                async function insertRange(count: number) {
                    const elems = new Array(count).fill(0).map((_, i) => BigInt(i + 1))
                    jsLeanIMT.insertMany(elems)
                    await skinnyIMTTest.insertMany(elems)
                }

                // Builds a shared multiproof for `rawIndices` against the CURRENT tree, applies
                // `makeVal` to each (in ascending-index order) via updateMany on-chain, mirrors the
                // same updates on the reference tree, and returns the aligned indexes/new values.
                async function updateManyDiff(rawIndices: number[], makeVal: (idx: number) => bigint) {
                    const { leaves: oldLeaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, rawIndices)
                    const newLeaves = leafIndexes.map((idx) => makeVal(idx))
                    await (await skinnyIMTTest.updateMany(oldLeaves, newLeaves, leafIndexes, siblings)).wait()
                    leafIndexes.forEach((idx, i) => jsLeanIMT.update(idx, newLeaves[i]))
                    return { leafIndexes, siblings, oldLeaves, newLeaves }
                }

                it("Should batch-update several leaves in a balanced tree", async () => {
                    await insertRange(8)
                    await updateManyDiff([1, 4, 6], (idx) => BigInt(1000 + idx))
                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                })

                it("Should batch-update a single leaf (degenerate multiproof) like update()", async () => {
                    await insertRange(6)
                    await updateManyDiff([2], () => 4242n)
                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                })

                it("Should batch-update adjacent leaves that share a parent", async () => {
                    await insertRange(8)
                    // 2 and 3 pair directly, so no sibling is supplied between them.
                    await updateManyDiff([2, 3], (idx) => BigInt(7000 + idx))
                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                })

                it("Should batch-update every leaf with an empty sibling list", async () => {
                    await insertRange(8)
                    const all = new Array(8).fill(0).map((_, i) => i)
                    const { siblings } = await updateManyDiff(all, (idx) => BigInt(5000 + idx))
                    // When all leaves are supplied, nothing is left to provide.
                    expect(siblings.length).to.equal(0)
                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                })

                it("Should batch-update including the dangling right-edge leaf in an odd tree", async () => {
                    // 3 leaves: leaf 2 dangles above level 0.
                    await insertRange(3)
                    await updateManyDiff([0, 2], (idx) => BigInt(300 + idx))
                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                })

                it("Should batch-update leaves to 0", async () => {
                    await insertRange(6)
                    await updateManyDiff([1, 4], () => 0n)
                    expect(await skinnyIMTTest.root()).to.equal(jsLeanIMT.root)
                })

                // Regression for the per-node isNewSideNode reset: in a size-5 tree the level-2 frontier
                // is position 0, but the dangling edge node (position 1) is processed AFTER it in the same
                // level. Resetting the flag per node would clobber the frontier write, so sideNodes[2] would
                // go stale — only surfacing on a later insert. Update {0,4}, then grow, and diff the root.
                it("Should refresh a frontier clobbered by a later edge node (size 5, update {0,4}), then grow", async () => {
                    await insertRange(5)
                    await updateManyDiff([0, 4], (idx) => BigInt(90000 + idx))
                    expect(await skinnyIMTTest.root(), "post-update").to.equal(jsLeanIMT.root)

                    for (let k = 0; k < 4; k++) {
                        const v = BigInt(600000 + k)
                        jsLeanIMT.insert(v)
                        await skinnyIMTTest.insert(v)
                        expect(await skinnyIMTTest.root(), `append k=${k}`).to.equal(jsLeanIMT.root)
                    }
                })

                // Batch-update then grow, across sizes with distinct trailing-bit shapes. A wrongly skipped
                // (or clobbered) live sideNode write only surfaces later as a wrong root on an op that READS
                // sideNodes — so update, then append leaf-by-leaf and via a batch, diffing against the reference.
                it("Should batch-update representative sizes/index-sets, then grow", async function () {
                    this.timeout(120000)
                    const cases: [number, number[]][] = [
                        [5, [0, 4]],
                        [5, [0, 1, 2, 3, 4]],
                        [7, [0, 3, 6]],
                        [8, [0, 4, 7]],
                        [9, [0, 4, 8]],
                        [12, [1, 5, 11]],
                        [13, [0, 6, 12]]
                    ]
                    for (const [size, indices] of cases) {
                        const { contract } = await run(deployTaskName, { library: libraryName, logs: false })
                        const ref = new JSLeanIMT((a, b) => hashFn(a, b))
                        const initial = Array.from({ length: size }, (_, i) => BigInt(i + 1))
                        ref.insertMany(initial)
                        await contract.insertMany(initial)

                        const { leaves: oldLeaves, leafIndexes, siblings } = generateMultiProof(ref, indices)
                        const newLeaves = leafIndexes.map((idx) => BigInt(100000 + size * 100 + idx))
                        await (await contract.updateMany(oldLeaves, newLeaves, leafIndexes, siblings)).wait()
                        leafIndexes.forEach((idx, i) => ref.update(idx, newLeaves[i]))
                        expect(await contract.root(), `size=${size} set=${indices} post-update`).to.equal(ref.root)

                        for (let k = 0; k < 4; k++) {
                            const v = BigInt(900000 + size * 1000 + k)
                            ref.insert(v)
                            await contract.insert(v)
                            expect(await contract.root(), `size=${size} set=${indices} append k=${k}`).to.equal(
                                ref.root
                            )
                        }

                        const batch = [111n, 222n, 333n]
                        ref.insertMany(batch)
                        await contract.insertMany(batch)
                        expect(await contract.root(), `size=${size} set=${indices} post-batch`).to.equal(ref.root)
                    }
                })

                it("Should revert on an empty batch", async () => {
                    await insertRange(8)
                    await expect(skinnyIMTTest.updateMany([], [], [], [])).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "WrongMultiProof"
                    )
                })

                it("Should revert on an empty tree", async () => {
                    await expect(skinnyIMTTest.updateMany([1], [2], [0], [])).to.be.revertedWithCustomError(
                        skinnyIMT,
                        "TreeEmpty"
                    )
                })

                it("Should revert when newLeaves length differs from leafIndexes", async () => {
                    await insertRange(8)
                    const { leaves: oldLeaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                    await expect(
                        skinnyIMTTest.updateMany(oldLeaves, [111n], leafIndexes, siblings)
                    ).to.be.revertedWithCustomError(skinnyIMT, "WrongMultiProof")
                })

                it("Should revert when a wrong oldLeaf breaks the old-root check", async () => {
                    await insertRange(8)
                    const { leaves: oldLeaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                    const tampered = [...oldLeaves]
                    tampered[0] = oldLeaves[0] + 1n
                    await expect(
                        skinnyIMTTest.updateMany(tampered, [111n, 222n], leafIndexes, siblings)
                    ).to.be.revertedWithCustomError(skinnyIMT, "WrongMultiProof")
                })

                it("Should revert when an extra sibling is supplied", async () => {
                    await insertRange(8)
                    const { leaves: oldLeaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                    await expect(
                        skinnyIMTTest.updateMany(oldLeaves, [111n, 222n], leafIndexes, [...siblings, 123n])
                    ).to.be.revertedWithCustomError(skinnyIMT, "WrongMultiProof")
                })

                if (hasSnarkFieldCheck) {
                    it("Should reject a newLeaf >= SNARK_SCALAR_FIELD", async () => {
                        await insertRange(8)
                        const { leaves: oldLeaves, leafIndexes, siblings } = generateMultiProof(jsLeanIMT, [1, 4])
                        await expect(
                            skinnyIMTTest.updateMany(oldLeaves, [111n, SNARK_SCALAR_FIELD], leafIndexes, siblings)
                        ).to.be.revertedWithCustomError(skinnyIMT, "LeafGreaterThanSnarkScalarField")
                    })
                }
            })
        }

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
                expect(await callVerify(0, 0, proof.siblings)).to.equal(true)
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
                expect(await callVerify(1, 0, proof.siblings)).to.equal(true)
            })

            it("Should not corrupt sideNodes when updating a non-frontier leaf that shares the frontier's value", async () => {
                // Value 7 sits at BOTH index 0 and index 2. Index 2 is the last leaf,
                // so sideNodes[0] tracks leaf 2 (= 7). Updating index 0 (also 7) must
                // leave sideNodes[0] alone — but _update refreshes sideNodes by VALUE
                // (`sideNodes[level] == oldRoot`), so it matches 7 == 7 and silently
                // rewrites sideNodes[0] to point at the wrong (updated) node.
                await skinnyIMTTest.insertMany([7, 8, 7])
                jsLeanIMT.insertMany([7n, 8n, 7n])

                const { siblings } = jsLeanIMT.generateProof(0)
                await skinnyIMTTest.update(7, 9, 0, siblings)
                jsLeanIMT.update(0, 9n)

                // The update itself reconstructs index 0's path correctly, so the root
                // is right immediately after — the corruption is invisible here.
                expect(await skinnyIMTTest.root(), "root immediately after update").to.equal(jsLeanIMT.root)

                // But the next insert hashes against sideNodes[0], which should still be
                // leaf 2 (= 7). If it was corrupted to 9, the roots diverge.
                jsLeanIMT.insert(5n)
                await skinnyIMTTest.insert(5)
                expect(await skinnyIMTTest.root(), "root after a later insert").to.equal(jsLeanIMT.root)
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

        // The _update / insertMany / insertManyRepeated sideNode-write optimization SKIPS
        // writes it deems dead (a slot the next op overwrites before reading). A wrongly
        // skipped *live* write only surfaces later, as a wrong root on an op that READS
        // sideNodes (a subsequent insert / insertMany / insertManyRepeated). These curated
        // cases do exactly that — optimized op, then grow — and diff against the reference
        // LeanIMT. Representative geometries only; exhaustive + randomized fuzzing lives in a
        // separate repo.
        describe("sideNode write optimization safety (differential)", () => {
            async function freshDeploy() {
                const { contract } = await run(deployTaskName, { library: libraryName, logs: false })
                return contract
            }

            // Sizes picked for distinct trailing-bit shapes (odd, even, all-ones, power-of-two,
            // power+1, mixed) — that's what changes which sideNode level a write is skipped at.
            // Growing after the update turns a "dead at update time" slot into one a later op reads.
            it("update boundary indexes on representative sizes, then grow", async function () {
                this.timeout(120000)
                const sizes = [1, 2, 3, 7, 8, 9, 12]
                for (const size of sizes) {
                    const indexes = [...new Set([0, size >> 1, size - 1])]
                    for (const idx of indexes) {
                        const contract = await freshDeploy()
                        const ref = new JSLeanIMT((a, b) => hashFn(a, b))
                        const initial = Array.from({ length: size }, (_, i) => BigInt(i + 1))
                        ref.insertMany(initial)
                        await contract.insertMany(initial)

                        const newVal = BigInt(100000 + size * 100 + idx)
                        const { siblings } = ref.generateProof(idx)
                        await contract.update(ref.leaves[idx], newVal, idx, siblings)
                        ref.update(idx, newVal)
                        expect(await contract.root(), `size=${size} idx=${idx} post-update`).to.equal(ref.root)

                        // grow leaf-by-leaf: single insert reads sideNodes
                        for (let k = 0; k < 4; k++) {
                            const v = BigInt(900000 + size * 1000 + idx * 100 + k)
                            ref.insert(v)
                            await contract.insert(v)
                            expect(await contract.root(), `size=${size} idx=${idx} append k=${k}`).to.equal(ref.root)
                        }

                        // and via a batch op, which reads sideNodes on a different path
                        const batch = [111n, 222n, 333n]
                        ref.insertMany(batch)
                        await contract.insertMany(batch)
                        expect(await contract.root(), `size=${size} idx=${idx} post-batch`).to.equal(ref.root)
                    }
                }
            })

            // Batch build (which skips dead frontier writes), then append so later inserts read
            // that frontier. A few representative (pre, batch, mode) shapes.
            it("batch-build then append leaf-by-leaf", async function () {
                this.timeout(120000)
                const cases: [number, number, "insertMany" | "insertManyRepeated"][] = [
                    [0, 1, "insertMany"],
                    [0, 5, "insertMany"],
                    [3, 4, "insertMany"],
                    [0, 3, "insertManyRepeated"],
                    [5, 6, "insertManyRepeated"],
                    [1, 7, "insertMany"]
                ]
                for (const [pre, batch, mode] of cases) {
                    const contract = await freshDeploy()
                    const ref = new JSLeanIMT((a, b) => hashFn(a, b))

                    if (pre > 0) {
                        const preLeaves = Array.from({ length: pre }, (_, i) => BigInt(i + 1))
                        ref.insertMany(preLeaves)
                        await contract.insertMany(preLeaves)
                    }

                    if (mode === "insertMany") {
                        const b = Array.from({ length: batch }, (_, i) => BigInt(1000 + i))
                        ref.insertMany(b)
                        await contract.insertMany(b)
                    } else {
                        const v = 7777n
                        for (let i = 0; i < batch; i++) ref.insert(v)
                        await contract.insertManyRepeated(v, batch)
                    }
                    expect(await contract.root(), `${mode} pre=${pre} batch=${batch} post-op`).to.equal(ref.root)

                    for (let k = 0; k < 4; k++) {
                        const v = BigInt(50000 + k)
                        ref.insert(v)
                        await contract.insert(v)
                        expect(await contract.root(), `${mode} pre=${pre} batch=${batch} append k=${k}`).to.equal(
                            ref.root
                        )
                    }
                }
            })
        })
    })
}
