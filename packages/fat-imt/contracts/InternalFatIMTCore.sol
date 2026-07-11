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
    // root lives at nodes[depth][0]. Unlike the skinny sideNodes mapping (which only kept the
    // left-frontier node per level), the fat tree stores every node so any node can be looked
    // up directly, without needing merkle proofs to reconstruct a path.
    mapping(uint256 => mapping(uint256 => uint256)) nodes;
    //@TODO use since it can be retrieved extremely fast with debug_storageRangeAt
    //uint256[] public leaves;
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
error NotInitialized();
error AlreadyInitialized();
error WrongMultiProof();
error TreeEmpty();

/// @title Fat Incremental binary Merkle tree.
/// @dev The FatIMT is an optimized version of the BinaryIMT.
/// This implementation eliminates the use of zeroes, and make the tree depth dynamic.
/// When a node doesn't have the right child, instead of using a zero hash as in the BinaryIMT,
/// the node's value becomes that of its left child. Furthermore, rather than utilizing a static tree depth,
/// it is updated based on the number of leaves in the tree. This approach
/// results in the calculation of significantly fewer hashes, making the tree more efficient.
library InternalFatIMTCore {
    /// @dev Checks whether the tree has been initialized.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @return True if the tree has been initialized, false otherwise.
    function _isInitialized(FatIMTData storage self) internal view returns (bool) {
        return self.treeId != 0;
    }

    /// @dev Initializes the tree by assigning it a non-zero `treeId` derived from its storage slot.
    /// Reverts if the tree has already been initialized.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @return The newly assigned tree id.
    function _init(FatIMTData storage self) internal returns (uint256) {
        if (_isInitialized(self)) {
            revert AlreadyInitialized();
        }
        uint256 slot;
        assembly {
            slot := self.slot
        }
        uint256 id = slot + 1;
        self.treeId = id;
        return id;
    }

    /// @dev Reads a single node by its position. Factored into a helper so the double-mapping
    /// lookup happens in its own stack frame, keeping hot loops under Solidity's 16-slot limit.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param level: The tree level (0 == leaves).
    /// @param index: The node index within that level.
    function _getNode(FatIMTData storage self, uint256 level, uint256 index) internal view returns (uint256) {
        return self.nodes[level][index];
    }

    /// @dev Writes a single node by its position. Factored into a helper for the same stack reason
    /// as _getNode.
    function _setNode(FatIMTData storage self, uint256 level, uint256 index, uint256 value) private {
        self.nodes[level][index] = value;
    }

    /// @dev Writes a whole contiguous run of nodes (`levelNodes[i]` goes to index `startIndex + i`)
    /// on one level. The loop lives in this helper's own frame so callers under the 16-slot stack
    /// limit can persist a level without the loop counter adding to their pressure.
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

    /// @dev Materializes every node of a repeated-insert block on one level at its real index.
    /// The block spans positions `[leftPos, rightPos]`: the two ends are the boundary/edge nodes
    /// (`leftVal`/`rightVal`, which may mix in existing-tree values), and every position strictly
    /// between them is the same repeated-subtree root for this level (`centerVal`). When the block
    /// has collapsed to a single node (`leftPos == rightPos`) both ends are that node. The loop
    /// lives in its own frame so `_insertManyRepeated` stays under the 16-slot stack limit.
    function _setRepeatedRange(
        FatIMTData storage self,
        uint256 level,
        uint256 leftIndex,
        uint256 rightIndex,
        uint256 leftVal,
        uint256 centerVal,
        uint256 rightVal
    ) private {
        mapping(uint256 => uint256) storage levelNodes = self.nodes[level];
        levelNodes[leftIndex] = leftVal;
        levelNodes[rightIndex] = rightVal;
        for (uint256 index = leftIndex + 1; index < rightIndex; ) {
            levelNodes[index] = centerVal;
            unchecked {
                ++index;
            }
        }
    }

    /// @dev Inserts a new leaf into the incremental merkle tree.
    /// @notice Contracts using this function with snark based hash functions,
    // need to check that the leaf is within the snark scalar field.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param leaf: The value of the new leaf to be inserted into the tree.
    /// @return root, index
    function _insert(
        FatIMTData storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        if (_isInitialized(self) == false) {
            revert NotInitialized();
        }
        uint256 index = self.size;

        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;

        // A new insertion can increase a tree's depth by at most 1,
        // and only if the number of leaves supported by the current
        // depth is less than the number of leaves to be supported after insertion.
        if (2 ** treeDepth < index + 1) {
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
                // right child: hash with the left sibling, which a previous insert
                // already stored at the index right before this one on this level
                node = hasher([self.nodes[level][nodeIndex - 1], node]);
            }
            // left child (even pos): node dangles and becomes its own parent, carried up unchanged

            // move up a level and store the (new or carried up) parent at its index
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

    // @TODO should also return start and endIndex, but stack limit is too close for that rn
    /// @dev Inserts many leaves into the incremental merkle tree.
    /// @notice Contracts using this function with snark based hash functions,
    // need to check that the leafs are within the snark scalar field.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param leaves: The values of the new leaves to be inserted into the tree.
    /// @return The root after the leaves have been inserted.
    function _insertMany(
        FatIMTData storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        if (_isInitialized(self) == false) {
            revert NotInitialized();
        }
        // cache treeSize
        uint256 oldTreeSize = self.size;

        // Array to save the nodes that will be used to create the next level of the tree.
        uint256[] memory currentLevelNewNodes;

        currentLevelNewNodes = leaves;

        // store the new leaves at level 0
        for (uint256 i = 0; i < leaves.length; ) {
            self.nodes[0][oldTreeSize + i] = leaves[i];
            unchecked {
                ++i;
            }
        }

        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;

        // Calculate the depth of the tree after adding the new values.
        // Unlike the 'insert' function, we need a while here as
        // N insertions can increase the tree's depth more than once.
        while (2 ** treeDepth < oldTreeSize + leaves.length) {
            ++treeDepth;
        }
        self.depth = treeDepth;

        // Update tree size up front so `oldTreeSize` is no longer needed inside the level loop below,
        // freeing a stack slot in that already stack-tight loop.
        self.size = oldTreeSize + leaves.length;

        // First index to change in every level.
        uint256 currentLevelStartIndex = oldTreeSize;

        // Size of the level used to create the next level.
        uint256 currentLevelSize = oldTreeSize + leaves.length;

        // The index where changes begin at the next level. currentLevelStartIndex / 2
        uint256 nextLevelStartIndex = currentLevelStartIndex >> 1;

        // The size of the next level. ((currentLevelSize - 1) / 2) + 1
        uint256 nextLevelSize = ((currentLevelSize - 1) >> 1) + 1;

        for (uint256 level = 0; level < treeDepth; ) {
            // The number of nodes for the new level that will be created,
            // only the new values, not the entire level.
            // uint256 numberOfNewNodes = nextLevelSize - nextLevelStartIndex;
            uint256[] memory nextLevelNewNodes = new uint256[](nextLevelSize - nextLevelStartIndex);

            // The only left child that comes from the existing tree (rather than from the new nodes)
            // is the very first new parent's. Read it once here instead of inside the hot loop below,
            // which keeps that loop under Solidity's 16-slot stack limit.
            uint256 boundaryLeftNode = (nextLevelStartIndex * 2 < currentLevelStartIndex)
                ? _getNode(self, level, nextLevelStartIndex * 2)
                : 0;

            for (uint256 i = 0; i < nextLevelSize - nextLevelStartIndex; ) {
                // packing left and right node in one array saves on the stack size
                uint256[2] memory hasherInput;

                // Assign the left node using the existing boundary node or the position in the array.
                if ((i + nextLevelStartIndex) * 2 < currentLevelStartIndex) {
                    hasherInput[0] = boundaryLeftNode;
                } else {
                    hasherInput[0] = currentLevelNewNodes[(i + nextLevelStartIndex) * 2 - currentLevelStartIndex];
                }

                // Existence of a right child by checking index
                // zero is a valid leaf now, so `rightChild == 0` can't be used as a proxy.
                // If a right child exists: assign it and hash(left, right). Otherwise: parent = left.
                if ((i + nextLevelStartIndex) * 2 + 1 < currentLevelSize) {
                    hasherInput[1] = currentLevelNewNodes[(i + nextLevelStartIndex) * 2 + 1 - currentLevelStartIndex];
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

            // Persist every freshly computed parent at its real index. Done in a helper so the
            // double-mapping store stays out of this frame (stack-limit reasons). No extra sideNode
            // bookkeeping is needed: the frontier nodes a future insert reads are just regular stored
            // nodes now.
            _setNodes(self, level + 1, nextLevelStartIndex, nextLevelNewNodes);

            currentLevelStartIndex = nextLevelStartIndex;

            // Calculate the next level startIndex value.
            // It is the position of the parent node which is pos/2.
            nextLevelStartIndex >>= 1;

            // Update the next array that will be used to calculate the next level.
            currentLevelNewNodes = nextLevelNewNodes;

            currentLevelSize = nextLevelSize;

            // Calculate the size of the next level.
            // The size of the next level is (currentLevelSize - 1) / 2 + 1.
            nextLevelSize = ((nextLevelSize - 1) >> 1) + 1;

            unchecked {
                ++level;
            }
        }

        // the loop already stored the root at nodes[treeDepth][0]; keep this explicit
        // we could also store as a safety net for the top of the tree.
        // self.nodes[treeDepth][0] = currentLevelNewNodes[0];

        return currentLevelNewNodes[0];
    }

    /// @dev Returns `hasher(currentNode, currentNode)`, reading the cache when
    /// warm and computing+storing on a miss. Generic memoizer for `f(x) = H(x, x)`:
    /// any chain that reaches `currentNode` at any level for any starting value
    /// shares the same entry. Factored out of the main loop to keep the
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

    /// @dev Appends `amount` leaves all equal to `value` into the tree.
    /// @notice Worst case costs 3*newDepth hashes regardless of `amount`.
    /// Best case cost 1*newDepth
    /// @notice Storage is O(amount): every node of the inserted block is written at its real
    /// index so the whole tree is readable from storage (needed for proof-less `update`).
    /// Only the hashing keeps the O(depth) repeated-subtree optimization.
    ///
    /// Only hashes 3 paths:
    ///  repeatedCenterNode: in the center of the insert,
    ///     these only contain nodes of "a balanced tree with only the same value repeating".
    ///     ex: H(0,0), H(H(0,0),H(0,0)), etc
    ///     Majority of the hashes the same as a repeatedCenterNode at every level.
    ///     Re-using those hashes instead of re-hashing is the core of the optimization here
    ///  lefBoundaryNodes: at the left of the insert who mix with the existing tree.
    ///  rightEdgeNodes: at the right of the insert and tree, tracks potential dangling nodes to to root
    ///         Eventually meets lefBoundaryNodes and creates the root.
    ///
    /// both lefBoundaryNodes and rightEdgeNodes use repeatedCenterNode to attach to the rest of the inserted sub tree.
    /// Best case cost is O(1*newDepth) because both lefBoundaryNodes and rightEdgeNodes,
    /// will use nodes from repeatedCenterNode when ever they can.
    ///  And when a insert results in an balanced tree and previous tree is empty, that is alway the case.
    ///  So it become O(1*newTreeDepth)
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param value: The leaf value to insert `amount` copies of.
    /// @param amount: The number of leaves to append.
    /// @return root after the leaves have been appended.
    /// @return firstIndex index of the first appended leaf (inclusive).
    /// @return lastIndex index of the last appended leaf (inclusive).
    function _insertManyRepeated(
        FatIMTData storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256 root, uint256 firstIndex, uint256 lastIndex) {
        uint256 newTreeDepth = self.depth;
        firstIndex = self.size;
        {
            // `newSize` is only needed for depth growth and the size/lastIndex
            // assignments; scoped to a block so its slot is released before
            // the main loop (Solidity's 16-slot stack is tight here).
            uint256 newSize = firstIndex + amount;
            while (2 ** newTreeDepth < newSize) {
                unchecked {
                    ++newTreeDepth;
                }
            }

            if (_isInitialized(self) == false) {
                revert NotInitialized();
            }
            if (amount == 0) {
                return (_root(self), firstIndex, firstIndex);
            }
            // after above no-op, to prevent underflow
            lastIndex = newSize - 1;
            if (amount == 1) {
                (root, ) = _insert(self, value, hasher);
                return (root, firstIndex, lastIndex);
            }

            self.depth = newTreeDepth;
            self.size = newSize;
        }

        // Nodes at the edges of the insert, and the center where the node only contains zeros:
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
            uint256 oldSideNode = ((firstIndex >> level) & 1 == 1) ? self.nodes[level][(firstIndex >> level) - 1] : 0;
            uint256 newSideNode;
            {
                // calculate the current index of the most left and right node of the insert
                // by doing: index >> level (same as: index / 2^level)
                uint256 rightEdgePosition = lastIndex >> level;
                uint256 leftBoundaryPosition = firstIndex >> level;

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

            // Materialize every node of the inserted block at this level at its real index, so the
            // fat tree stays fully populated — every node readable from storage. This is required
            // now that `update` reads siblings straight from storage instead of taking a merkle
            // proof: any inserted node may later be a sibling on some update path.
            // The block spans positions [firstIndex>>level, lastIndex>>level]; interior positions are
            // all the repeated-subtree root for this level (repeatedCenterNode), the two ends are the
            // boundary/edge nodes. leftBoundaryNode/rightEdgeNode/repeatedCenterNode still hold this
            // level's values here — the hashing below reassigns them to the next level's.
            // Storage is now O(amount) instead of O(depth); the hashing above stays O(depth).
            _setRepeatedRange(
                self,
                level,
                firstIndex >> level,
                lastIndex >> level,
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
                    // uint256 leftBoundaryPosition = firstIndex >> level; over stack limit again :/
                    uint256 nextRightEdgePosition = lastIndex >> (level + 1);
                    uint256 nextLeftEdgePosition = firstIndex >> (level + 1);

                    // we can skip leftBoundaryNode if the next iter rightEdgeNode is at the same position
                    // at that point leftBoundaryNode does the same as rightEdgeNode,
                    // so no need to do things twice
                    if (nextLeftEdgePosition != nextRightEdgePosition) {
                        // if leftBoundaryPosition is right
                        if ((firstIndex >> level) & 1 == 1) {
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
                // rightEdgePosition = (lastIndex / (2**level)) % 2
                if ((lastIndex >> level) & 1 == 1) {
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
        return (root, firstIndex, lastIndex);
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
        if (_isInitialized(self) == false) {
            revert NotInitialized();
        }
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

    /// @dev Updates the value of an existing leaf and recalculates hashes
    /// to maintain tree integrity.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param oldLeaf: The value of the leaf that is to be updated.
    /// @param newLeaf: The new value that will replace the oldLeaf in the tree.
    /// @param leafIndex: The index of the leaf to be updated.
    /// @param proofSiblings: An array of sibling nodes that are necessary to recalculate the path to the root.
    /// @return The new hash of the updated node after the leaf has been updated.
    /// @notice Every recomputed node on the path is written back to self.nodes[level][index], keyed by
    /// its position (derived from leafIndex), so the stored tree stays in sync after the update.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the old and newLeaf and proofSiblings are within the snark scalar field.
    function _update(
        FatIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        if (_isInitialized(self) == false) {
            revert NotInitialized();
        }
        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;
        if (proofSiblings.length > treeDepth) {
            revert WrongSiblingNodes();
        }

        // 2 vars to store intermediate hashes, to hash up to oldRoot and newRoot
        uint256 newNode = newLeaf;
        uint256 oldNode = oldLeaf;

        // index of the very last leaf in the tree
        // tracking this index up the tree, follows the indexes of the nodes in self.sidNodes
        uint256 treeSize = self.size;
        uint256 edgeIndex = treeSize - 1;

        // because leanIMT is not balanced proofSiblings.length can be smaller then tree depth
        // we cant just use level so we separately track those 2
        uint256 siblingIndex = 0;

        // Store the new leaf itself at level 0. For a single-node tree (treeDepth == 0) the leaf IS
        // the root, so writing it here would corrupt the old-root check below; that case is instead
        // covered by the post-verification root store (nodes[treeDepth][0] = newNode).
        if (treeDepth > 0) {
            self.nodes[0][leafIndex] = newLeaf;
        }

        // verify merkle proof of oldLeaf from proofSiblings and at the same time calculate the newRoot.
        // note: this is basically just _proofToRoot twice on old and new leaf, then assert root from oldLeaf is
        // the current root. The difference is that every recomputed node on the new path is written back to
        // self.nodes[level][index] so the stored tree reflects the update.
        for (uint256 level = 0; level < treeDepth; ) {
            // leafIndex is odd / is right
            if ((leafIndex >> level) & 1 == 1) {
                newNode = hasher([proofSiblings[siblingIndex], newNode]);
                oldNode = hasher([proofSiblings[siblingIndex], oldNode]);

                unchecked {
                    ++siblingIndex;
                }
            } else {
                // left child: hash with the right sibling from the proof, unless this node is the
                // dangling edge of the tree (shares no parent with a right neighbour at this level),
                // in which case it carries up unchanged.
                if (leafIndex >> level != edgeIndex >> level) {
                    newNode = hasher([newNode, proofSiblings[siblingIndex]]);
                    oldNode = hasher([oldNode, proofSiblings[siblingIndex]]);

                    unchecked {
                        ++siblingIndex;
                    }
                }
            }

            // Persist the recomputed node one level up, at its index. Defer the root (top level)
            // until after the proof has been verified against the current (old) root below, so
            // _root(self) still reads the old top slot at the check.
            if (level + 1 < treeDepth) {
                self.nodes[level + 1][leafIndex >> (level + 1)] = newNode;
            }

            unchecked {
                ++level;
            }
        }

        if (oldNode != _root(self)) {
            revert WrongSiblingNodes();
        }

        // proof verified: commit the new root at the top level
        self.nodes[treeDepth][0] = newNode;

        return newNode;
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

    struct MultiProofLevelState {
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
        MultiProofLevelState memory levelState,
        MultiProofArrLevelPositions memory levelPos,
        function(uint256[2] memory) view returns (uint256) hasher
    ) private view returns (MultiProofLevelState memory, MultiProofArrLevelPositions memory) {
        for (uint256 i = 0; i < levelPos.currentNodesFreeSlot; i++) {
            // hash left or right
            if (levelState.positions[i] & 1 == 1) {
                // A right-position node whose sibling is also known is consumed at that sibling
                // (the even node below, which skips forward past this one), so reaching here means
                // the left sibling isn't in currentNodes and must come from the proof.
                levelState.nodes[levelPos.nextNodesFreeSlot] = hasher(
                    [proof.proofSiblings[levelPos.proofSiblingsReadPos], levelState.nodes[i]]
                );
                levelState.positions[levelPos.nextNodesFreeSlot] = levelState.positions[i] >> 1;

                unchecked {
                    ++levelPos.nextNodesFreeSlot;
                    ++levelPos.proofSiblingsReadPos;
                }
            } else {
                // make sure node index is not at the edge because edges should be carried up a level
                // TODO these variable names are so long the auto format makes the code unreadable
                if (levelState.positions[i] != levelPos.edgePos) {
                    if (
                        (i + 1) < levelPos.currentNodesFreeSlot &&
                        (levelState.positions[i + 1] == (levelState.positions[i] + 1))
                    ) {
                        // the right sibling is the next node in currentNodes, so hash the pair
                        // here and skip it (avoids reading a left neighbor on the next iteration)
                        levelState.nodes[levelPos.nextNodesFreeSlot] = hasher(
                            [levelState.nodes[i], levelState.nodes[i + 1]]
                        );
                        levelState.positions[levelPos.nextNodesFreeSlot] = levelState.positions[i] >> 1;
                        // up counter to skip next node since we already hashed it.
                        unchecked {
                            ++i;
                        }
                    } else {
                        levelState.nodes[levelPos.nextNodesFreeSlot] = hasher(
                            [levelState.nodes[i], proof.proofSiblings[levelPos.proofSiblingsReadPos]]
                        );
                        levelState.positions[levelPos.nextNodesFreeSlot] = levelState.positions[i] >> 1;

                        unchecked {
                            ++levelPos.proofSiblingsReadPos;
                        }
                    }
                } else {
                    levelState.nodes[levelPos.nextNodesFreeSlot] = levelState.nodes[i];
                    levelState.positions[levelPos.nextNodesFreeSlot] = levelState.positions[i] >> 1;
                }
                ++levelPos.nextNodesFreeSlot;
            }
        }

        // per level updates
        levelPos.edgePos >>= 1;

        // parents were written in place into the low slots; that prefix is the next level.
        levelPos.currentNodesFreeSlot = levelPos.nextNodesFreeSlot;
        levelPos.nextNodesFreeSlot = 0;
        return (levelState, levelPos);
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

        MultiProofLevelState memory levelState = MultiProofLevelState(
            new uint256[](leafCount),
            new uint256[](leafCount)
        );

        MultiProofArrLevelPositions memory levelPositions = MultiProofArrLevelPositions(0, 0, 0, proof.edgeIndex, 0);

        // Seed every proven leaf at level 0, at its real index. Each leaf is then hashed up
        // from the bottom, so an internal-node value or a wrong index simply produces a
        // non-matching root — nothing can enter above level 0 un-hashed. Dangling is resolved
        // while climbing (the edge-carry in _hashMultiProofLevel), derived from `edgeIndex`.
        for (uint256 i = 0; i < leafCount; i++) {
            levelState.nodes[i] = leaves[i];
            levelState.positions[i] = proof.leafIndexes[i];
        }
        levelPositions.currentNodesFreeSlot = leafCount;

        for (uint256 level = 0; level < proof.treeDepth; ) {
            levelPositions.level = level;
            (levelState, levelPositions) = _hashMultiProofLevel(proof, levelState, levelPositions, hasher);

            unchecked {
                ++level;
            }
        }

        // all proof siblings need to be read and validated.
        // Very strict but now this function verifies leaves + indexes + proof siblings
        if (levelPositions.proofSiblingsReadPos != proof.proofSiblings.length) {
            revert WrongMultiProof();
        }
        return levelState.nodes[0];
    }

    // would save 2 array in memory, more importantly stack pressure
    function _updateMany(
        FatIMTData storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        MultiProof memory proof,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        uint256 leafCount = oldLeaves.length;
        if (leafCount == 0 || leafCount != proof.leafIndexes.length || leafCount != newLeaves.length) {
            revert WrongMultiProof();
        }

        MultiProofLevelState memory oldLevelState = MultiProofLevelState(
            new uint256[](leafCount),
            new uint256[](leafCount)
        );

        MultiProofLevelState memory newLevelState = MultiProofLevelState(
            new uint256[](leafCount),
            new uint256[](leafCount)
        );
        MultiProofArrLevelPositions memory newLevelPositions = MultiProofArrLevelPositions(0, 0, 0, proof.edgeIndex, 0);

        MultiProofArrLevelPositions memory oldLevelPositions = MultiProofArrLevelPositions(0, 0, 0, proof.edgeIndex, 0);

        // Seed every proven leaf at level 0, at its real index. Each leaf is then hashed up
        // from the bottom, so an internal-node value or a wrong index simply produces a
        // non-matching root — nothing can enter above level 0 un-hashed. Dangling is resolved
        // while climbing (the edge-carry in _hashMultiProofLevel), derived from `edgeIndex`.
        for (uint256 i = 0; i < leafCount; i++) {
            oldLevelState.nodes[i] = oldLeaves[i];
            newLevelState.nodes[i] = newLeaves[i];
            oldLevelState.positions[i] = proof.leafIndexes[i];
            newLevelState.positions[i] = proof.leafIndexes[i];
            // Store the new leaves at level 0. When treeDepth == 0 a leaf is the root, so defer to
            // the post-verification root store to avoid corrupting the old-root check below.
            if (proof.treeDepth > 0) {
                self.nodes[0][proof.leafIndexes[i]] = newLeaves[i];
            }
        }
        oldLevelPositions.currentNodesFreeSlot = leafCount;
        newLevelPositions.currentNodesFreeSlot = leafCount;

        for (uint256 level = 0; level < proof.treeDepth; ) {
            oldLevelPositions.level = level;
            newLevelPositions.level = level;
            (oldLevelState, oldLevelPositions) = _hashMultiProofLevel(proof, oldLevelState, oldLevelPositions, hasher);
            (newLevelState, newLevelPositions) = _hashMultiProofLevel(proof, newLevelState, newLevelPositions, hasher);

            // Persist every recomputed new node one level up, at its real index. Defer the root
            // (top level) until after the proof is verified, so _root(self) still reads the old
            // top slot at the check below.
            if (level + 1 < proof.treeDepth) {
                for (uint256 j = 0; j < newLevelPositions.currentNodesFreeSlot; ) {
                    self.nodes[level + 1][newLevelState.positions[j]] = newLevelState.nodes[j];
                    unchecked {
                        ++j;
                    }
                }
            }

            unchecked {
                ++level;
            }
        }
        // Verify the old leaves against the current root BEFORE overwriting anything: _root(self) still
        // reads the old top slot here. The loop above only wrote intermediate nodes (levels < treeDepth);
        // the top root slot is written below, once the proof is known good.
        if (_root(self) != oldLevelState.nodes[0]) {
            // TODO say wrong root instead? Also in _update?
            revert WrongMultiProof();
        }

        // all proof siblings need to be read and validated.
        // Very strict but now this function verifies leaves + indexes + proof siblings
        if (oldLevelPositions.proofSiblingsReadPos != proof.proofSiblings.length) {
            revert WrongMultiProof();
        }

        // Store the new top root. An update never changes depth, so proof.treeDepth == self.depth.
        uint256 newRoot = newLevelState.nodes[0];
        self.nodes[proof.treeDepth][0] = newRoot;
        return newRoot;
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
// outside of FatIMTPoseidon2

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
