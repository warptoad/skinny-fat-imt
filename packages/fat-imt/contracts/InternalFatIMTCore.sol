// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SNARK_SCALAR_FIELD} from "./Constants.sol";

// TODO optimize duplicate inserts by adding hashed from 0 level nodes
struct FatIMTData {
    // Tracks the current number of leaves in the tree.
    uint256 size;
    // Represents the current depth of the tree, which can increase as new leaves are inserted.
    uint256 depth;
    // Every node in the tree, keyed by [level][index]. Level 0 holds the leaves, and the
    // root lives at nodes[depth][0]. This allows leaf updates without merkle proofs
    mapping(uint256 => mapping(uint256 => uint256)) nodes;
    uint256 treeId;
    // caches the hash of a repeated value, so instead of doing hash(value,value)
    // you can lookup repeatedHashCache[value]
    mapping(uint256 => uint256) repeatedHashCache;
}

struct MultiProof {
    uint256 treeDepth;
    uint256 edgeIndex;
    uint256[] leafIndexes;
    uint256[] proofSiblings;
}

error WrongSiblingNodes();
error LeafDoesNotExist();
error WrongMultiProof();
error TreeEmpty();

/// @title Fat Incremental binary Merkle tree.
/// @dev The FatIMT is an optimized version of the BinaryIMT.
/// This implementation eliminates the use of pre-inserted zeroes, and make the tree depth dynamic.
/// When a node doesn't have the right child, instead of using a zero hash as in the BinaryIMT,
/// the node's value becomes that of its left child. Furthermore, rather than utilizing a static tree depth,
/// it is updated based on the number of leaves in the tree. This approach
/// results in the calculation of significantly fewer hashes, making the tree more efficient.
library InternalFatIMTCore {
    function _reset(FatIMTData storage self) internal {
        self.size = 0;
        self.depth = 0;
    }

    /// @dev self.nodes getter (to stay under stack limit)
    function _getNode(FatIMTData storage self, uint256 index, uint256 level) internal view returns (uint256) {
        return self.nodes[level][index];
    }

    /// @dev self.nodes setter (to stay under stack limit)
    function _setNode(FatIMTData storage self, uint256 index, uint256 value, uint256 level) private {
        self.nodes[level][index] = value;
    }

    /// @dev self.nodes getter (to stay under stack limit)
    /// writes a batch of nodes for one level
    function _setNodes(
        FatIMTData storage self,
        uint256 level,
        uint256 startIndex,
        uint256[] memory levelNodes
    ) private {
        for (uint256 i = 0; i < levelNodes.length; ) {
            self.nodes[level][startIndex + i] = levelNodes[i];
            unchecked {
                ++i;
            }
        }
    }

    /// @dev used in _insertManyRepeated (to stay under stack limit)
    /// writes all the nodes of one level from _insertManyRepeated:
    /// the left and right boundary node (who might differ from the repeating hashes)
    /// and the repeating nodes in between those (who always share the same value).
    /// @notice once indexes match up, this function choose rightEdgeNode above: leftBoundaryNode and centerRepeatingNode
    /// this means that, in that case leftBoundaryNode and centerRepeatingNode are allowed to be stale.
    function _setRepeatedRange(
        FatIMTData storage self,
        uint256 level,
        uint256 leftIndex,
        uint256 rightIndex,
        uint256 leftBoundaryNode,
        uint256 centerRepeatingNode,
        uint256 rightEdgeNode
    ) private {
        mapping(uint256 => uint256) storage levelNodes = self.nodes[level];

        // rightEdge is authoritative at rightIndex, always write it
        levelNodes[rightIndex] = rightEdgeNode;

        // only write if they are at different indexes
        if (leftIndex < rightIndex) {
            levelNodes[leftIndex] = leftBoundaryNode;
        }
        // fill in the gap with centerRepeatingNode. If there is any, otherwise ignore centerRepeatingNode
        for (uint256 index = leftIndex + 1; index < rightIndex; ) {
            levelNodes[index] = centerRepeatingNode;
            unchecked {
                ++index;
            }
        }
    }

    /// @dev Inserts a new leaf into the incremental merkle tree.
    /// @notice Does not do field checks. For that use `InternalFatIMTEvent._insertBN254()`
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param leaf: The value of the new leaf to be inserted into the tree.
    /// @return (root, index) root: the new root, index: index leaf landed at
    function _insert(
        FatIMTData storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        // init check moved to the Event layer (folded into the treeId read the event already does)
        uint256 index = self.size;

        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;

        // A new insertion can increase a tree's depth by at most 1,
        // and only if the number of leaves supported by the current
        // depth is less than the number of leaves to be supported after insertion.
        if ((1 << treeDepth) < index + 1) {
            ++treeDepth;
        }

        self.depth = treeDepth;

        uint256 node = leaf;

        // position of `node` at the current level, starting at the leaf index.
        uint256 nodeIndex = index;

        // store the leaf itself at level 0
        self.nodes[0][nodeIndex] = node;

        for (uint256 level = 0; level < treeDepth; ) {
            if (nodeIndex & 1 == 1) {
                // right child: hash with the left sibling
                // Tree fills left to right, and we carry up any even indexes until they're uneven,
                // so we only hash on the "node is right" case
                // This feels weird, since it sounds like an leaf at even index at lets say 8 that:
                //_hashMultiProofLevel needs to be hashed left in a balanced of size 16 tree
                // so `hash(index_8, index_9)`
                // That does happen, but at the next insert. Next insert does: `hash(index_8, index_9)`
                // where index_8 is read from storage (`self.nodes[level][index_9 - 1]`)
                node = hasher([self.nodes[level][nodeIndex - 1], node]);
            }
            // else {
            // left child (even pos): node dangles and becomes its own parent, carried up unchanged
            // until it hits a uneven pos, then it joins the tree by hashing with a subtree (`hash(subtree, node)`)
            // }

            // shift index to next level, store every node
            nodeIndex >>= 1;
            self.nodes[level + 1][nodeIndex] = node;

            unchecked {
                ++level;
            }
        }

        // the last iteration stored the root at nodes[treeDepth][0] (nodeIndex collapses to 0)
        // original did self.size = index++ above
        // since self.leaves[leaf] = index + 1. But that is no longer true
        self.size = index + 1;
        return (node, index);
    }

    /// @dev Per-level index/size trackers for `_insertMany`, bundled into one memory slot (one stack
    /// slot instead of four) so the function can also return the start/next indexes without blowing
    /// the 16-slot stack (no viaIR). Mutated in place as we climb: `currentLevel*` is the level being
    /// consumed, `nextLevel*` the level being built.
    struct InsertManyLevel {
        uint256 currentLevelStartIndex; // first index to change at the current level
        uint256 currentLevelSize; // number of nodes at the current level
        uint256 nextLevelStartIndex; // first index to change at the next level
        uint256 nextLevelSize; // number of nodes at the next level
    }

    /// @dev Inserts many leaves into the incremental merkle tree.
    /// @notice Contracts using this function with snark based hash functions,
    // need to check that the leafs are within the snark scalar field.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param leaves: The values of the new leaves to be inserted into the tree.
    /// @return root after the leaves have been inserted.
    /// @return startIndex index of the first appended leaf (inclusive).
    /// @return nextIndex index one past the last appended leaf (exclusive). Same shape as
    /// `_insertManyRepeated`. The per-level trackers are packed in an `InsertManyLevel` struct so the
    /// frame has room for the two extra return values under the 16-slot stack limit (no viaIR).
    function _insertMany(
        FatIMTData storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // init check moved to the Event layer (folded into the treeId read the event already does)
        // cache treeSize (this is also the startIndex)
        uint256 startIndex = self.size;

        // Array to save the nodes that will be used to create the next level of the tree.
        uint256[] memory currentLevelNewNodes;

        currentLevelNewNodes = leaves;

        // store the new leaves at level 0
        for (uint256 i = 0; i < leaves.length; ) {
            self.nodes[0][startIndex + i] = leaves[i];
            unchecked {
                ++i;
            }
        }

        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;

        // Calculate the depth of the tree after adding the new values.
        // Unlike the 'insert' function, we need a while here as
        // N insertions can increase the tree's depth more than once.
        while ((1 << treeDepth) < startIndex + leaves.length) {
            ++treeDepth;
        }
        self.depth = treeDepth;

        // Update tree size up front so `oldTreeSize` is no longer needed inside the level loop below,
        // freeing a stack slot in that already stack-tight loop.
        self.size = startIndex + leaves.length;

        // The four per-level trackers, in one memory slot
        InsertManyLevel memory lvl = InsertManyLevel({
            currentLevelStartIndex: startIndex,
            currentLevelSize: startIndex + leaves.length,
            nextLevelStartIndex: startIndex >> 1, // currentLevelStartIndex / 2
            nextLevelSize: ((startIndex + leaves.length - 1) >> 1) + 1 // ceil(currentLevelSize / 2)
        });

        for (uint256 level = 0; level < treeDepth; ) {
            // The number of nodes for the new level that will be created,
            // only the new values, not the entire level.
            uint256[] memory nextLevelNewNodes = new uint256[](lvl.nextLevelSize - lvl.nextLevelStartIndex);

            for (uint256 i = 0; i < lvl.nextLevelSize - lvl.nextLevelStartIndex; ) {
                // packing left and right node in one array saves on the stack size
                uint256[2] memory hasherInput;

                // Only the first node (i==0) can border the existing tree, and only when currentLevelStartIndex is
                // odd: then its left sibling is read from storage. Otherwise both children are in memory
                // (currentLevelNewNodes). Reading it here (not precomputed) keeps the stack slim.
                if (i == 0 && lvl.currentLevelStartIndex & 1 == 1) {
                    hasherInput[0] = self.nodes[level][lvl.nextLevelStartIndex * 2];
                } else {
                    hasherInput[0] = currentLevelNewNodes[
                        (i + lvl.nextLevelStartIndex) * 2 - lvl.currentLevelStartIndex
                    ];
                }
                // `i` counts parents so we reconstruct it's left childs index by doing:`(i + nextLevelStartIndex) << 1`
                // then +1 and we have the right child's index
                // then if that *right* child lays at or out side of currentLevelSize, it means we don't have the -
                // the *right* child rn, so we hoist the *left* child (we do have) up,
                /// to be hashed in *a* another iteration
                if (((i + lvl.nextLevelStartIndex) << 1) + 1 < lvl.currentLevelSize) {
                    hasherInput[1] = currentLevelNewNodes[
                        ((i + lvl.nextLevelStartIndex) << 1) + 1 - lvl.currentLevelStartIndex
                    ];
                    // store as parent node for next round
                    nextLevelNewNodes[i] = hasher(hasherInput);
                } else {
                    // leave to dangle:
                    // node is used in next iter, becomes it's own parent.
                    // Stored in nextLevelNewNodes, for when it will have an right sibling eventually
                    // store as parent node for next round
                    nextLevelNewNodes[i] = hasherInput[0];
                }

                unchecked {
                    ++i;
                }
            }

            // store every node (outside loop with helper because of stack limit)
            _setNodes(self, level + 1, lvl.nextLevelStartIndex, nextLevelNewNodes);

            lvl.currentLevelStartIndex = lvl.nextLevelStartIndex;

            // Calculate the next level startIndex value.
            // It is the position of the parent node which is pos/2.
            lvl.nextLevelStartIndex >>= 1;

            // Update the next array that will be used to calculate the next level.
            currentLevelNewNodes = nextLevelNewNodes;

            lvl.currentLevelSize = lvl.nextLevelSize;

            // Calculate the size of the next level.
            // The size of the next level is ceil(n / 2) (-1 +1 to efficiently mimic ceil).
            // rounded up since odd levelSize would result in a dangle being hoisted up,
            // so round up to include that hoisted node
            lvl.nextLevelSize = ((lvl.nextLevelSize - 1) >> 1) + 1;

            unchecked {
                ++level;
            }
        }

        // the loop already stored the root at nodes[treeDepth][0]; keep this explicit
        // we could also store as a safety net for the top of the tree.
        // self.nodes[treeDepth][0] = currentLevelNewNodes[0];

        return (currentLevelNewNodes[0], startIndex, startIndex + leaves.length);
    }

    /// @dev Returns `hasher(value, value)`
    // from cache if it has it, hashed fresh if not
    // also stores the fresh hash for future use
    /// per-iteration stack under Solidity's 16-slot limit.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param value: The value to hash with itself.
    /// @return `hasher(currentNode, currentNode)`.
    function _hashWithCache(
        FatIMTData storage self,
        uint256 value,
        function(uint256[2] memory) view returns (uint256) hasher
    ) private returns (uint256) {
        uint256 cached = self.repeatedHashCache[value];
        if (cached != 0) {
            return cached;
        }
        uint256 hash = hasher([value, value]);
        self.repeatedHashCache[value] = hash;
        return hash;
    }

    /// @dev Efficiently appends n-`amount` many leaves, with the same value in the tree.
    /// @notice Worst case hash cost is 3*newDepth hashes regardless of `amount`.
    /// Best case cost 1*newDept. However storage is O(amount): since the fat variant is forced to store all nodes
    /// Only the hashing keeps the O(newTreeDepth) repeated-subtree optimization.
    ///
    /// Only hashes 3 paths:
    ///  repeatedCenterNode: in the center of the insert,
    ///     these only contain nodes of "a balanced tree with only the same value repeating".
    ///     ex: H(0,0), H(H(0,0),H(0,0)), etc
    ///     Majority of the hashes are the same as a repeatedCenterNode at every level.
    ///     Re-using those hashes instead of re-hashing is the core of the optimization here
    ///  lefBoundaryNodes: at the left of the insert who mix with the existing tree.
    ///  rightEdgeNodes: at the right of the insert and tree, tracks potential dangling nodes to to root
    ///         Eventually meets lefBoundaryNodes and creates the root.
    ///
    /// both lefBoundaryNodes and rightEdgeNodes use repeatedCenterNode to attach to the rest of the inserted sub tree.
    /// Best case cost is O(1*newDepth) because both lefBoundaryNodes and rightEdgeNodes,
    /// will use nodes from repeatedCenterNode when ever they can.
    ///  And when a insert results in an balanced tree and previous tree is empty, that is alway the case.
    ///  So it will always be O(1*newTreeDepth)
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param value: The leaf value to insert `amount` copies of.
    /// @param amount: The number of leaves to append.
    /// @return root after the leaves have been appended.
    /// @return startIndex index of the first appended leaf (inclusive).
    /// @return nextIndex index one past the last appended leaf (exclusive), matching the Event layer.
    function _insertManyRepeated(
        FatIMTData storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256 root, uint256 startIndex, uint256 nextIndex) {
        uint256 newTreeDepth = self.depth;
        startIndex = self.size;
        // NOTE: named returns are load-bearing here — this frame is stack-tight (no viaIR) and
        // de-naming these into locals overflows it (verified). We return the exclusive `nextIndex`
        // and derive the inclusive last index inline as `(nextIndex - 1)` to occupy one less slot.
        {
            nextIndex = startIndex + amount;
            while (1 << newTreeDepth < nextIndex) {
                unchecked {
                    ++newTreeDepth;
                }
            }

            // init check moved to the Event layer
            if (amount == 0) {
                // nothing appended: the exclusive end is startIndex itself
                return (_root(self), startIndex, startIndex);
            }
            if (amount == 1) {
                (root, ) = _insert(self, value, hasher);
                return (root, startIndex, nextIndex);
            }

            self.depth = newTreeDepth;
            self.size = nextIndex;
        }

        // Nodes used in hashing at the edges of the insert and the center where the node only contains zeros:
        //   lefBoundaryNode = The node at the boundary between the insert and existing tree.
        //   rightEdgeNode = The node that is at the very edge of the tree.
        //   repeatedCenterNode = The node that all sit in the center of the insert and
        //      only contain repeated values and is always balanced. Always cache-able
        uint256 leftBoundaryNode = value;
        uint256 rightEdgeNode = value;
        uint256 repeatedCenterNode = value;

        // loops only once over the newTreeDepth
        // does at most 3 hashes,
        // 2 hashes for the left and right side of the inserted values (lefEdgeNode, rightEdgeNode)
        // 1 hash / cache lookup for the node that only contains zeros (repeatedCenterNode)
        for (uint256 level = 0; level < newTreeDepth; ) {
            // ------------assign sideNode --------------
            // oldSideNode is only actually consumed when the left boundary sits at an odd position
            // (the newSideNode == oldSideNode branch and the leftBoundary hashing below). At those
            // levels the node right before the boundary is the existing tree's frontier, stored at
            // its real index. When the boundary is even oldSideNode is read but never used, so 0 is fine.
            uint256 oldSideNode = ((startIndex >> level) & 1 == 1) ? self.nodes[level][(startIndex >> level) - 1] : 0;
            uint256 newSideNode;
            {
                // calculate the current index of the most left and right node of the insert
                // by doing: index >> level (same as: index / 2^level). (nextIndex - 1) is the inclusive
                // last leaf index; see the note at the top on why we don't keep it in its own slot.
                uint256 rightEdgePosition = (nextIndex - 1) >> level;
                uint256 leftBoundaryPosition = startIndex >> level;

                // determine where the sideNode is at. Left,right, (somewhere) center of the inserted nodes or unchanged
                // sideNode == rightEdgeNodeSibling (left sibling of rightEdge), unless dangles or if root
                if (rightEdgePosition & 1 == 0) {
                    // here rightEdgeNode is at an uneven index, because it is at the very edge of the entire tree,
                    // it will have no sibling :(, it will "dangle" and thus will be the newSideNode
                    newSideNode = rightEdgeNode;

                    // these cases when rightEdgeNode does have a sibling :D
                    // now we just detect who is that sibling. leftBoundary, repeatedCenter or oldSideNode?
                } else if (leftBoundaryPosition < (rightEdgePosition - 1)) {
                    // rightEdgeNode has a sibling :D
                    // But that sibling is not leftBoundaryPosition yet, since the position of
                    // the sibling of rightEdgeNode (rightEdgePosition - 1) is higher then leftBoundaryPosition
                    // There for we need a sibling between the old tree and the very right edge,
                    // we need repeatedCenterNode!
                    newSideNode = repeatedCenterNode;
                } else if (leftBoundaryPosition == (rightEdgePosition - 1)) {
                    // Now rightEdgeNode's sibling positions is *exactly* leftBoundaryPosition
                    // it's sibling is leftBoundaryNode!
                    newSideNode = leftBoundaryNode;
                } else {
                    // now leftBoundaryPosition is the same as rightEdgePosition
                    // we know this because leftBoundaryPosition < rightEdgeSiblingPosition (else if #1)
                    // and leftBoundaryPosition != rightEdgeSiblingPosition (else if #2)
                    // and because node position only converge when moving up a tree, but never cross,
                    // we can now say leftBoundaryNode is at the same position as rightEdgeNode
                    // because leftBoundaryNode and rightEdgeNode are the same, they form a subTreeRoot that contains
                    // all values we are inserting (sometimes some values of existing tree).
                    // Now we need to just "attach" this root with our inserts to the existing tree
                    // simply by constantly hashing in the oldSideNode of that level.
                    newSideNode = oldSideNode;
                }
            }

            // stores all repeated nodes and boundary node at this level.
            _setRepeatedRange(
                self,
                level,
                startIndex >> level,
                (nextIndex - 1) >> level,
                // leftBoundaryNode goes stale when leftIndex == rightIndex,
                // but this function ignores leftBoundaryNode at that point.
                leftBoundaryNode,
                repeatedCenterNode,
                rightEdgeNode
            );

            //-------- hashing -----------------
            {
                // ---- repeatedCenterNode---
                // newRepeatedCenterNode use a cache to look hashes from a "balanced tree with only repeated values"
                uint256 newRepeatedCenterNode = _hashWithCache(self, repeatedCenterNode, hasher);

                // ----leftBoundaryNode---
                // calculate index of the left boundary node at this level and check if it's odd or even, left or right
                // oldSize / (2**level) % 2
                {
                    // redoing calculation here because of stack limits
                    // uint256 leftBoundaryPosition = startIndex >> level; over stack limit again :/
                    uint256 nextRightEdgePosition = (nextIndex - 1) >> (level + 1);
                    uint256 nextLeftEdgePosition = startIndex >> (level + 1);

                    // we can skip leftBoundaryNode if the next iter rightEdgeNode is at the same position
                    // at that point leftBoundaryNode does the same as rightEdgeNode,
                    // so no need to do things twice
                    if (nextLeftEdgePosition != nextRightEdgePosition) {
                        // if leftBoundaryPosition is right
                        if ((startIndex >> level) & 1 == 1) {
                            // if right use oldSideNode, since that is where these added nodes "attach" to the
                            // existing tree
                            if (leftBoundaryNode == repeatedCenterNode && oldSideNode == repeatedCenterNode) {
                                // no need to hash, already done by newRepeatedCenterNode!
                                // oldSideNode was just a N-hashed repeated value
                                leftBoundaryNode = newRepeatedCenterNode;
                            } else {
                                // existing tree had something else, no luck!
                                leftBoundaryNode = hasher([oldSideNode, leftBoundaryNode]);
                            }
                        } else {
                            // if left, use the repeatedCenterNode,
                            // (could be one if but requires another var on the stack)
                            if (leftBoundaryNode == repeatedCenterNode) {
                                // no need to hash, already done by newRepeatedCenterNode!
                                leftBoundaryNode = newRepeatedCenterNode;
                            } else {
                                // our boundary node picked up an existing value from the existing tree
                                // that is not our value we are repeatedly inserting. No luck :(
                                leftBoundaryNode = hasher([leftBoundaryNode, repeatedCenterNode]);
                            }
                        }
                    }
                }

                // ---- rightEdgeNode ---
                // calculate index of the newSide node at this level and check if it's odd or even
                // rightEdgePosition = ((nextIndex - 1) / (2**level)) % 2
                if (((nextIndex - 1) >> level) & 1 == 1) {
                    // if odd rightEdgeNode has a sibling so we hash it right
                    if (newSideNode == rightEdgeNode) {
                        // we are doing hasher([rightEdgeNode, rightEdgeNode])
                        if (repeatedCenterNode == rightEdgeNode) {
                            // it's just a center node
                            rightEdgeNode = newRepeatedCenterNode;
                        } else {
                            // we might be doing hasher([rightEdgeNode, rightEdgeNode])
                            // as a coincidence. Or we did do a "balanced tree with only repeated values" hash
                            // check the cache
                            uint256 cached = self.repeatedHashCache[rightEdgeNode];
                            if (cached != 0) {
                                rightEdgeNode = cached; // free hash
                            } else {
                                // not storing this because it might have been a coincidence
                                rightEdgeNode = hasher([rightEdgeNode, rightEdgeNode]);
                            }
                        }
                    } else {
                        rightEdgeNode = hasher([newSideNode, rightEdgeNode]);
                    }
                }
                // we don't do the left case since we need to leave rightEdgeNode to dangle

                // repeatedCenterNode updates for the next iter
                repeatedCenterNode = newRepeatedCenterNode;
            }

            // Advance level first so it doubles as `nextLevel` for the cache lift.
            unchecked {
                ++level;
            }
        }

        // finally store the root!
        root = rightEdgeNode;
        self.nodes[newTreeDepth][0] = root;
        return (root, startIndex, nextIndex);
    }

    /// @dev Warms the `(value, level)` cache for levels 1..`upToLevel` so that
    /// subsequent `_insertManyRepeated(value, ...)` calls hit the cache instead of
    /// re-hashing. Idempotent: levels already cached are not rewritten.
    /// @notice Useful when you know in advance the maximum depth a tree will reach
    /// for a particular `value` (e.g. zero) — pay the SSTOREs once, then every
    /// subsequent bulk-insert of that value reads cheaply from storage.
    /// @notice Reverts if the tree has not been initialized.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param value: The leaf value whose repeated-subtree chain to precompute.
    /// @param upToLevel: The highest level (inclusive) to populate the cache for.
    function _precomputeRepeatedCache(
        FatIMTData storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        // init check moved to the Event layer (folded into the treeId read the event already does)
        if (upToLevel == 0) {
            return;
        }

        // subtreeRoot tracks the repeated-subtree root at the current level as we
        // climb. Start at level 0 = value. Each iteration looks up (or fills)
        // hasher(subtreeRoot, subtreeRoot) and advances one level.
        uint256 subtreeRoot = value;
        for (uint256 level = 1; level <= upToLevel; ) {
            subtreeRoot = _hashWithCache(self, subtreeRoot, hasher);
            unchecked {
                ++level;
            }
        }
    }

    /// @dev Updates the value of an existing leaf and re-hashes its path to the root, persisting every
    /// recomputed node at its real index. Reads each sibling straight from storage — the left sibling
    /// (`nodes[level][pos - 1]`) for a right child, the right sibling (`nodes[level][pos + 1]`) for a
    /// left child — unless the node is the dangling right edge at that level (`pos == edgeIndex >> level`),
    /// which has no sibling and is carried up unchanged. No merkle proof and no caller-supplied oldLeaf
    /// is required; the old value is read from storage and returned (for the event).
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param newLeaf: The new value that will replace the current leaf.
    /// @param leafIndex: The index of the leaf to be updated.
    /// @return newRoot The new root after the leaf has been updated.
    /// @return oldLeaf The value the leaf held before the update.
    /// @notice Reverts with LeafDoesNotExist if leafIndex is out of range. Contracts using this
    /// function with snark based hash functions need to check that newLeaf is within the snark
    /// scalar field.
    function _update(
        FatIMTData storage self,
        uint256 newLeaf,
        uint256 leafIndex,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        // init check moved to the Event layer (folded into the treeId read the event already does)
        uint256 treeSize = self.size;
        if (leafIndex >= treeSize) {
            revert LeafDoesNotExist();
        }

        uint256 oldLeaf = self.nodes[0][leafIndex];

        // overwrite the leaf, then climb re-hashing its path. `leafIndex` doubles as the climbing
        // position and `newRoot` as the running node; both collapse to the root at the top.
        uint256 newRoot = newLeaf;
        self.nodes[0][leafIndex] = newLeaf;

        uint256 treeDepth = self.depth;
        uint256 edgeIndex = treeSize - 1;
        for (uint256 level = 0; level < treeDepth; ) {
            if (leafIndex & 1 == 1) {
                // right child: hash with the stored left sibling
                newRoot = hasher([self.nodes[level][leafIndex - 1], newRoot]);
            } else if (leafIndex != edgeIndex >> level) {
                // left child that has a right sibling present in the tree
                newRoot = hasher([newRoot, self.nodes[level][leafIndex + 1]]);
            }
            // else: dangling right edge at this level, carried up unchanged

            // move up a level and store the recomputed parent at its index
            leafIndex >>= 1;
            self.nodes[level + 1][leafIndex] = newRoot;

            unchecked {
                ++level;
            }
        }
        return (newRoot, oldLeaf);
    }

    /// @dev Hashes merkle proof and returns the root the leaf belongs to
    /// @param leafIndex: The leaf to proof inclusion of
    /// @param leafIndex: The index of the leaf within the tree.
    /// @param proofSiblings: The sibling nodes along the path from the leaf to the root.
    /// @return The root obtained from hashing the leaf with the provided siblings.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the leaf and proofSiblings are within the snark scalar field.
    function _proofToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        if (treeSize == 0) {
            revert TreeEmpty();
        }

        // index of the very last leaf in the tree
        // tracking this index up the tree, follows the indexes of the nodes in self.sidNodes
        uint256 edgeIndex = treeSize - 1;

        // because leanIMT is not balanced proofSiblings.length can be smaller then tree depth
        // we cant just use level so we separately track those 2
        uint256 siblingIndex = 0;

        uint256 node = leaf;
        for (uint256 level = 0; level < treeDepth; ) {
            if ((leafIndex >> level) & 1 == 1) {
                node = hasher([proofSiblings[siblingIndex], node]);

                unchecked {
                    ++siblingIndex;
                }
            } else {
                // make sure node index is not at the edge @TODO explain
                if (leafIndex >> level != edgeIndex >> level) {
                    node = hasher([node, proofSiblings[siblingIndex]]);

                    unchecked {
                        ++siblingIndex;
                    }
                }
            }

            unchecked {
                ++level;
            }
        }
        return node;
    }

    struct MultiProofLevel {
        // One level's known nodes and their positions. The fold rewrites parents in place into
        // the low end of these same arrays: the write cursor (nextNodesFreeSlot) never runs ahead
        // of the read index, and the only forward read (the i+1 sibling) is always still unwritten,
        // so a single buffer aliases safely. `currentNodesFreeSlot` bounds the live prefix.
        uint256[] nodes;
        uint256[] positions;
    }

    struct MultiProofArrLevelPositions {
        uint256 currentNodesFreeSlot;
        uint256 nextNodesFreeSlot;
        uint256 proofSiblingsReadPos;
        uint256 edgePos;
        uint256 level;
    }

    /// @dev Folds one tree level: reads the known nodes in `nodes` (positions in `positions`)
    /// and rewrites their parents into the low end of those same arrays in place,
    /// pulling a sibling from `proof.proofSiblings` only where one isn't already known.
    /// A rightmost node with no sibling (position == edgePos) is carried up unchanged — this
    /// is where dangling (a leaf or an internal node with no right neighbor) is resolved,
    /// entirely from the tree's `edgeIndex`, not from any caller-supplied schedule.
    function _hashMultiProofLevel(
        MultiProof memory proof,
        MultiProofLevel memory lvl,
        MultiProofArrLevelPositions memory lvlPos,
        function(uint256[2] memory) view returns (uint256) hasher
    ) private view returns (MultiProofLevel memory, MultiProofArrLevelPositions memory) {
        for (uint256 i = 0; i < lvlPos.currentNodesFreeSlot; i++) {
            // hash left or right
            if (lvl.positions[i] & 1 == 1) {
                // A right-position node whose sibling is also known is consumed at that sibling
                // (the even node below, which skips forward past this one), so reaching here means
                // the left sibling isn't in currentNodes and must come from the proof.
                lvl.nodes[lvlPos.nextNodesFreeSlot] = hasher(
                    [proof.proofSiblings[lvlPos.proofSiblingsReadPos], lvl.nodes[i]]
                );
                lvl.positions[lvlPos.nextNodesFreeSlot] = lvl.positions[i] >> 1;

                unchecked {
                    ++lvlPos.nextNodesFreeSlot;
                    ++lvlPos.proofSiblingsReadPos;
                }
            } else {
                // make sure node index is not at the edge because edges should be carried up a level
                // TODO these variable names are so long the auto format makes the code unreadable
                if (lvl.positions[i] != lvlPos.edgePos) {
                    if ((i + 1) < lvlPos.currentNodesFreeSlot && (lvl.positions[i + 1] == (lvl.positions[i] + 1))) {
                        // the right sibling is the next node in currentNodes, so hash the pair
                        // here and skip it (avoids reading a left neighbor on the next iteration)
                        lvl.nodes[lvlPos.nextNodesFreeSlot] = hasher([lvl.nodes[i], lvl.nodes[i + 1]]);
                        lvl.positions[lvlPos.nextNodesFreeSlot] = lvl.positions[i] >> 1;
                        // up counter to skip next node since we already hashed it.
                        unchecked {
                            ++i;
                        }
                    } else {
                        lvl.nodes[lvlPos.nextNodesFreeSlot] = hasher(
                            [lvl.nodes[i], proof.proofSiblings[lvlPos.proofSiblingsReadPos]]
                        );
                        lvl.positions[lvlPos.nextNodesFreeSlot] = lvl.positions[i] >> 1;

                        unchecked {
                            ++lvlPos.proofSiblingsReadPos;
                        }
                    }
                } else {
                    lvl.nodes[lvlPos.nextNodesFreeSlot] = lvl.nodes[i];
                    lvl.positions[lvlPos.nextNodesFreeSlot] = lvl.positions[i] >> 1;
                }
                ++lvlPos.nextNodesFreeSlot;
            }
        }

        // per level updates
        lvlPos.edgePos >>= 1;

        // parents were written in place into the low slots; that prefix is the next level.
        lvlPos.currentNodesFreeSlot = lvlPos.nextNodesFreeSlot;
        lvlPos.nextNodesFreeSlot = 0;
        return (lvl, lvlPos);
    }

    // would save 2 array in memory, more importantly stack pressure
    function _proofManyToRoot(
        uint256[] calldata leaves,
        MultiProof memory proof,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        uint256 leafCount = leaves.length;
        if (leafCount == 0 || leafCount != proof.leafIndexes.length) {
            revert WrongMultiProof();
        }

        MultiProofLevel memory lvl = MultiProofLevel(new uint256[](leafCount), new uint256[](leafCount));

        MultiProofArrLevelPositions memory lvlPos = MultiProofArrLevelPositions(0, 0, 0, proof.edgeIndex, 0);

        // Seed every proven leaf at level 0, at its real index. Each leaf is then hashed up
        // from the bottom, so an internal-node value or a wrong index simply produces a
        // non-matching root — nothing can enter above level 0 un-hashed. Dangling is resolved
        // while climbing (the edge-carry in _hashMultiProofLevel), derived from `edgeIndex`.
        for (uint256 i = 0; i < leafCount; i++) {
            lvl.nodes[i] = leaves[i];
            lvl.positions[i] = proof.leafIndexes[i];
        }
        lvlPos.currentNodesFreeSlot = leafCount;

        for (uint256 level = 0; level < proof.treeDepth; ) {
            lvlPos.level = level;
            (lvl, lvlPos) = _hashMultiProofLevel(proof, lvl, lvlPos, hasher);

            unchecked {
                ++level;
            }
        }

        // all proof siblings need to be read and validated.
        // Very strict but now this function verifies leaves + indexes + proof siblings
        if (lvlPos.proofSiblingsReadPos != proof.proofSiblings.length) {
            revert WrongMultiProof();
        }
        return lvl.nodes[0];
    }

    // Per-level scalars for the batch-update fold. Bundled into a struct (mutated in place, like
    // MultiProofLevelState) so _updateManyLevel takes few enough arguments to stay under the stack limit.
    struct UpdateManyLevel {
        uint256 count; // number of known nodes at this level (live prefix of the state arrays)
        /// TODO make more human readable, audit etc
        uint256 edgePos; // position of the dangling right edge at this level (treeSize-1 >> level)
        uint256 level; // current level
    }

    /// @dev _updateMany cant re-use _hashMultiProofLevel like in skinny-imt since it assumes a merkle proof exists
    /// this function efficiently walks up one level of the hash path of multiple nodes in an update
    /// it loops
    function _updateManyLevel(
        FatIMTData storage self,
        MultiProofLevel memory lvl,
        UpdateManyLevel memory lvlPos,
        function(uint256[2] memory) view returns (uint256) hasher
    ) private returns (MultiProofLevel memory, UpdateManyLevel memory) {
        uint256 writeSlot = 0;
        for (uint256 i = 0; i < lvlPos.count; ) {
            uint256 nodeIndex = lvl.positions[i];
            uint256 parent;

            if (nodeIndex & 1 == 1) {
                // right child: its left sibling is never a known node here, read it from storage
                parent = hasher([_getNode(self, nodeIndex - 1, lvlPos.level), lvl.nodes[i]]);
            } else if (nodeIndex == lvlPos.edgePos) {
                // dangling right edge: no sibling, carried up unchanged
                parent = lvl.nodes[i];
            } else if (i + 1 < lvlPos.count && lvl.positions[i + 1] == nodeIndex + 1) {
                // the right sibling is the next known node: joined paths meet, hash the pair once
                parent = hasher([lvl.nodes[i], lvl.nodes[i + 1]]);
                unchecked {
                    ++i;
                }
            } else {
                // left child whose right sibling is untouched: read it from storage
                parent = hasher([lvl.nodes[i], _getNode(self, nodeIndex + 1, lvlPos.level)]);
            }

            uint256 parentPos = nodeIndex >> 1;
            _setNode(self, parentPos, parent, lvlPos.level + 1);
            lvl.nodes[writeSlot] = parent;
            lvl.positions[writeSlot] = parentPos;

            unchecked {
                ++writeSlot;
                ++i;
            }
        }

        // advance to the next level
        lvlPos.count = writeSlot;
        lvlPos.edgePos >>= 1;
        lvlPos.level += 1;
        return (lvl, lvlPos);
    }

    /// @dev Seeds level 0 of a batch update: validates each index, records the old leaf, writes the
    /// new leaf, and fills `state` with the new leaves at their indexes. Split into its own frame so
    /// `_updateMany` stays under the 16-slot stack limit.
    /// @return oldLeaves The values the leaves held before the update.
    function _seedUpdateMany(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        MultiProofLevel memory lvl,
        uint256 treeSize
    ) private returns (uint256[] memory) {
        uint256[] memory oldLeaves = new uint256[](newLeaves.length);
        for (uint256 i = 0; i < newLeaves.length; ) {
            uint256 leafIndex = leafIndexes[i];
            if (leafIndex >= treeSize) {
                revert LeafDoesNotExist();
            }
            // Must be strictly ascending (no dupes) so joined siblings sit adjacent. Skinny caught a
            // bad order via its old-root check; here we just rebuild and write the root, so a wrong
            // order isn't caught — it would persist a wrong root. Hence enforce it.
            if (i != 0 && leafIndex <= leafIndexes[i - 1]) {
                revert WrongMultiProof();
            }
            oldLeaves[i] = _getNode(self, leafIndex, 0);
            lvl.nodes[i] = newLeaves[i];
            lvl.positions[i] = leafIndex;
            _setNode(self, leafIndex, newLeaves[i], 0);
            unchecked {
                ++i;
            }
        }
        return oldLeaves;
    }

    /// @dev Updates many leaves and re-hashes their paths to the root in one bottom-up pass, reading
    /// every sibling straight from storage — no merkle proof and no caller-supplied oldLeaves. Unlike
    /// updating each leaf on its own, this folds all paths together level by level, so a node shared
    /// by several updated paths is hashed exactly once.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param newLeaves: The new values to write (parallel to leafIndexes).
    /// @param leafIndexes: The indexes of the leaves to update; must be strictly ascending.
    /// @return newRoot The new root after all updates.
    /// @return oldLeaves The values the leaves held before the update (for the event).
    /// @notice Reverts with WrongMultiProof on an empty batch, length mismatch, or non-ascending
    /// indexes, or LeafDoesNotExist if any index is out of range.
    function _updateMany(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256[] memory) {
        uint256 leafCount = newLeaves.length;
        if (leafCount == 0 || leafCount != leafIndexes.length) {
            revert WrongMultiProof();
        }
        // init check moved to the Event layer (folded into the treeId read the event already does)

        uint256 treeSize = self.size;

        // Known nodes for the current level. Seeded with the new leaves at their indexes; the fold
        // rewrites parents into the low slots of these arrays each level.
        MultiProofLevel memory lvl = MultiProofLevel(new uint256[](leafCount), new uint256[](leafCount));
        uint256[] memory oldLeaves = _seedUpdateMany(self, newLeaves, leafIndexes, lvl, treeSize);

        UpdateManyLevel memory lvlPos = UpdateManyLevel(leafCount, treeSize - 1, 0);
        uint256 treeDepth = self.depth;
        for (lvlPos.level = 0; lvlPos.level < treeDepth; ) {
            // note: _updateManyLevel does ++lvlPos.level (this to safe on stack size)
            (lvl, lvlPos) = _updateManyLevel(self, lvl, lvlPos, hasher);
        }

        // paths all converged to the single top node; return it with the pre-update leaves
        return (lvl.nodes[0], oldLeaves);
    }

    /// @dev Retrieves the root of the tree from the 'nodes' mapping using the
    /// current tree depth. The root is the single node at the top level.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @return The root hash of the tree.
    function _root(FatIMTData storage self) internal view returns (uint256) {
        return self.nodes[self.depth][0];
    }
}

// @notes contract size limit work around: use _hashMultiProofLevel for both proofManyToRoot as updateMany
// same with plain update
// _hashMultiProofLevel uses 2 arrays for tracking nodes. currentLevel and nextLevel. You can prob just do it in 1
// same for insertMany probably, but that is vivians code so i would rather keep it as similar as possible
// and ofc we can just split into multiple contracts that export these internal functions. example move verify functions
// outside of FatIMTPoseidon2WriteArchiveNode

// old unused code
// this is not used because it only adds to contract size and gas of these functions.
// it does read easier and more consistently with the other implementation
//------------ update and proofToRoot written with hashLevel pattern like updateMany and proofManyToRoot -------------
// /// @dev Updates the value of an existing leaf and recalculates hashes
// /// to maintain tree integrity.
// /// @param self: A storage reference to the 'FatIMTData' struct.
// /// @param oldLeaf: The value of the leaf that is to be updated.
// /// @param newLeaf: The new value that will replace the oldLeaf in the tree.
// /// @param leafIndex: The index of the leaf to be updated.
// /// @param proofSiblings: An array of sibling nodes that are necessary to recalculate the path to the root.
// /// @return The new hash of the updated node after the leaf has been updated.
// /// @notice Requires collision-resistant hashing: `if (self.sideNodes[level] == oldRoot)` identifies
// /// which sideNode to refresh by hash equality,
// /// so a collision between two distinct subtree roots would corrupt tree state silently.
// /// @notice Contracts using this function with snark based hash functions,
// /// need to check that the old and newLeaf and proofSiblings are within the snark scalar field.
// function _update(
//     FatIMTData storage self,
//     uint256 oldLeaf,
//     uint256 newLeaf,
//     uint256 leafIndex,
//     uint256[] calldata proofSiblings,
//     function(uint256[2] memory) view returns (uint256) hasher
// ) internal returns (uint256) {
//     if (_isInitialized(self) == false) {
//         revert NotInitialized();
//     }
//     // Cache tree depth to optimize gas
//     uint256 treeDepth = self.depth;
//     if (proofSiblings.length > treeDepth) {
//         revert WrongSiblingNodes();
//     }

//     uint256 treeSize = self.size;

//     // 2 vars to store intermediate hashes, to hash up to oldRoot and newRoot
//     uint256 newNode = newLeaf;
//     uint256 oldNode = oldLeaf;

//     ProofLevelPositions memory oldLevelPos = ProofLevelPositions(
//         leafIndex, // nodeIndex
//         treeSize - 1, // edgeIndex
//         treeSize, // nextInsertIndex
//         0, // proofSiblingReadIndex
//         0, // newSideNode
//         false // isNewSideNode
//     );
//     ProofLevelPositions memory newLevelPos = ProofLevelPositions(
//         leafIndex, // nodeIndex
//         treeSize - 1, // edgeIndex
//         treeSize, // nextInsertIndex
//         0, // proofSiblingReadIndex
//         0, // newSideNode
//         false // isNewSideNode
//     );
//     for (uint256 level = 0; level < treeDepth; ) {
//         // oldNode is just inclusion proof, so trackSideNodes=false, and we will use the same positions for newNode
//         // so trackPositions=false
//         (oldNode, oldLevelPos) = _hashProofLevel(oldNode, oldLevelPos, proofSiblings, hasher);
//         (newNode, newLevelPos) = _hashProofLevel(newNode, newLevelPos, proofSiblings, hasher);
//         if (newLevelPos.isNewSideNode) {
//             self.sideNodes[level] = newLevelPos.newSideNode;
//         }
//         unchecked {
//             ++level;
//         }
//     }

//     if (oldNode != _root(self)) {
//         revert WrongSiblingNodes();
//     }

//     self.sideNodes[treeDepth] = newNode;

//     return newNode;
// }

// struct ProofLevelPositions {
//     uint256 nodeIndex;
//     uint256 edgeIndex;
//     uint256 nextInsertIndex;
//     uint256 siblingIndex;
//     uint256 newSideNode;
//     bool isNewSideNode;
// }

// function _hashProofLevel(
//     uint256 node,
//     ProofLevelPositions memory levelPos,
//     uint256[] calldata proofSiblings,
//     function(uint256[2] memory) view returns (uint256) hasher
// ) internal view returns (uint256, ProofLevelPositions memory) {
//     // The sideNode at this level is the node at position nextInsertIndex - 1, and only when this level
//     // is live (nextInsertIndex is odd). For a single-leaf update the one node we recompute (`node`, at
//     // position nodeIndex) is that sideNode exactly when nodeIndex == nextInsertIndex - 1. Write the result
//     // into the struct so the caller sees it; reset the flag each level since `levelPos` is reused.
//     if (levelPos.nextInsertIndex & 1 == 1 && (levelPos.nextInsertIndex - 1) == levelPos.nodeIndex) {
//         levelPos.newSideNode = node;
//         levelPos.isNewSideNode = true;
//     } else {
//         levelPos.isNewSideNode = false;
//     }
//     if (levelPos.nodeIndex & 1 == 1) {
//         node = hasher([proofSiblings[levelPos.siblingIndex], node]);
//         unchecked {
//             ++levelPos.siblingIndex;
//         }
//     } else {
//         // make sure node index is not at the edge @TODO explain
//         if (levelPos.nodeIndex != levelPos.edgeIndex) {
//             node = hasher([node, proofSiblings[levelPos.siblingIndex]]);

//             unchecked {
//                 ++levelPos.siblingIndex;
//             }
//         }
//     }

//     levelPos.nodeIndex >>= 1;
//     levelPos.edgeIndex >>= 1;
//     levelPos.nextInsertIndex >>= 1;

//     return (node, levelPos);
// }

// /// @dev Hashes merkle proof and returns the root the leaf belongs to
// /// @param leafIndex: The leaf to proof inclusion of
// /// @param leafIndex: The index of the leaf within the tree.
// /// @param proofSiblings: The sibling nodes along the path from the leaf to the root.
// /// @return The root obtained from hashing the leaf with the provided siblings.
// /// @notice Contracts using this function with snark based hash functions,
// /// need to check that the leaf and proofSiblings are within the snark scalar field.
// function _proofToRoot(
//     uint256 treeDepth,
//     uint256 treeSize,
//     uint256 leaf,
//     uint256 leafIndex,
//     uint256[] calldata proofSiblings,
//     function(uint256[2] memory) view returns (uint256) hasher
// ) internal view returns (uint256) {
//     if (treeSize == 0) {
//         revert TreeEmpty();
//     }

//     uint256 node = leaf;
//     ProofLevelPositions memory levelPos = ProofLevelPositions(
//         leafIndex, // nodeIndex
//         // index of the very last leaf in the tree
//         // tracking this index up the tree, follows the indexes of the nodes in self.sidNodes
//         treeSize - 1, // edgeIndex
//         // index of the next insert in the tree, tracking this up to tree to determine
//         // what sideNode is needed to store
//         treeSize, // nextInsertIndex
//         // because leanIMT is not balanced proofSiblings.length can be smaller then tree depth
//         // we cant just use level so we separately track those 2
//         0, // proofSiblingReadIndex
//         0, // newSideNode
//         false // isNewSideNode
//     );
//     for (uint256 level = 0; level < treeDepth; ) {
//         // no need for sideNodes so trackSideNodes=false
//         (node, levelPos) = _hashProofLevel(node, levelPos, proofSiblings, hasher);

//         unchecked {
//             ++level;
//         }
//     }
//     return node;
// }
//---------------------------------------------------------------------------------------------------------------------
