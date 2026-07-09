// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SNARK_SCALAR_FIELD} from "./Constants.sol";

// TODO optimize duplicate inserts by adding hashed from 0 level nodes
struct SkinnyIMTData {
    // Tracks the current number of leaves in the tree.
    uint256 size;
    // Represents the current depth of the tree, which can increase as new leaves are inserted.
    uint256 depth;
    // A mapping from each level of the tree to the node value of the last even position at that level.
    // Used for efficient inserts, updates and root calculations.
    mapping(uint256 => uint256) sideNodes;
    //@TODO use since it can be retrieved extremely fast with debug_storageRangeAt
    //uint256[] public leaves;
    uint256 treeId;
    // Memoizes `hasher(x, x)` for any `x`. Used to lift repeated-subtree roots
    // up one level: with H being the tree's hash function, the depth-(L+1) root
    // of an all-`v` subtree is `H(depth-L root, depth-L root)`. Since both
    // inputs are the same value, the cache only needs a single uint256 key.
    // Populated lazily by `_insertManyRepeated` and eagerly by
    // `_precomputeRepeatedCache`. Entries are valid across all values and levels —
    // any two chains that happen to coincide at some node share the same entry.
    // Sentinel: a stored 0 means "not yet cached". Relies on cryptographic
    // hashes never landing on 0 — a re-hash would be triggered if they did, which
    // is a perf hiccup but not a correctness bug.
    mapping(uint256 => uint256) repeatedHashCache;
}

// added storage of the leaves to allow syncing with full nodes for leaves older then 1 year
struct SkinnyIMTFullNodeData {
    // arrays cost more but store in consecutive slots which allows for usage of debug_storageRangeAt
    // to read this extremely fast
    uint256[] leaves;
    SkinnyIMTData skinnyData;
}

struct MultiProof {
    uint256 treeDepth;
    uint256 edgeIndex;
    uint256[] leaves;
    uint256[] leafIndexes;
    uint256[] proofSiblings;
}

error WrongSiblingNodes();
error LeafDoesNotExist();
error NotInitialized();
error AlreadyInitialized();
error LeafGreaterThanSnarkScalarField();
error WrongMultiProof();
error TreeEmpty();

/// @title Skinny Incremental binary Merkle tree.
/// @dev The SkinnyIMT is an optimized version of the BinaryIMT.
/// This implementation eliminates the use of zeroes, and make the tree depth dynamic.
/// When a node doesn't have the right child, instead of using a zero hash as in the BinaryIMT,
/// the node's value becomes that of its left child. Furthermore, rather than utilizing a static tree depth,
/// it is updated based on the number of leaves in the tree. This approach
/// results in the calculation of significantly fewer hashes, making the tree more efficient.
library InternalSkinnyIMT {
    /// @dev Checks whether the tree has been initialized.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return True if the tree has been initialized, false otherwise.
    function _isInitialized(SkinnyIMTData storage self) internal view returns (bool) {
        return self.treeId != 0;
    }

    /// @dev Reverts with `LeafGreaterThanSnarkScalarField` if `v` is not in the BN254 scalar field.
    function _requireInField(uint256 v) internal pure {
        if (v >= SNARK_SCALAR_FIELD) {
            revert LeafGreaterThanSnarkScalarField();
        }
    }

    /// @dev Initializes the tree by assigning it a non-zero `treeId` derived from its storage slot.
    /// Reverts if the tree has already been initialized.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The newly assigned tree id.
    function _init(SkinnyIMTData storage self) internal returns (uint256) {
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

    /// @dev Inserts a new leaf into the incremental merkle tree.
    /// @notice Contracts using this function with snark based hash functions,
    // need to check that the leaf is within the snark scalar field.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the new leaf to be inserted into the tree.
    /// @return root, index
    function _insert(
        SkinnyIMTData storage self,
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

        for (uint256 level = 0; level < treeDepth; ) {
            if ((index >> level) & 1 == 1) {
                // hash right
                node = hasher([self.sideNodes[level], node]);
            } else {
                // leave to dangle:
                // node is used in next iter, becomes it's own parent.
                if (((index + 1) >> level) & 1 == 1) {
                    // only store it if the next insert actually needs it
                    // that is when the next index is a right node at this level. That is when it reads from sideNodes
                    // in the case above
                    self.sideNodes[level] = node;
                }
            }

            unchecked {
                ++level;
            }
        }

        self.sideNodes[treeDepth] = node;
        // original did self.size = index++ above
        // since self.leaves[leaf] = index + 1. But that is no longer true
        self.size = index + 1;
        return (node, index);
    }

    // @TODO should also return start and endIndex, but stack limit is too close for that rn
    /// @dev Inserts many leaves into the incremental merkle tree.
    /// @notice Contracts using this function with snark based hash functions,
    // need to check that the leafs are within the snark scalar field.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaves: The values of the new leaves to be inserted into the tree.
    /// @return The root after the leaves have been inserted.
    function _insertMany(
        SkinnyIMTData storage self,
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

        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;

        // Calculate the depth of the tree after adding the new values.
        // Unlike the 'insert' function, we need a while here as
        // N insertions can increase the tree's depth more than once.
        while (2 ** treeDepth < oldTreeSize + leaves.length) {
            ++treeDepth;
        }
        self.depth = treeDepth;

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
            for (uint256 i = 0; i < nextLevelSize - nextLevelStartIndex; ) {
                // packing left and right node in one array saves on the stack size
                uint256[2] memory hasherInput;

                // Assign the left node using the saved path or the position in the array.
                if ((i + nextLevelStartIndex) * 2 < currentLevelStartIndex) {
                    hasherInput[0] = self.sideNodes[level];
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

            // Update the `sideNodes` variable.
            // sideNodes are always at the edge of the tree, and are always the leftChild
            //
            // If `currentLevelSize` is odd, the saved value will be the last value of the array
            // if it is even and there are more than 1 element in `currentLevelNewNodes`, the saved value
            // will be the value before the last one.
            // If it is even and there is only one element, there is no need to save anything because
            // the correct value for this level was already saved before.
            // Only refresh the sideNode at levels live for the new tree (set bits of the
            // new leaf count). At the other levels the next insert overwrites the slot
            // before reading it, so the store would be dead. (Computed inline rather than
            // cached in a local — the surrounding function is at the 16-slot stack limit.)
            if (((oldTreeSize + leaves.length) >> level) & 1 == 1) {
                if (currentLevelSize & 1 == 1) {
                    // currentLevelSize % 2 == 1, is odd
                    // currentLevelSize = treeSize + leaves.length
                    // currentLevelSize = (currentLevelSize - 1) / 2 + 1
                    self.sideNodes[level] = currentLevelNewNodes[currentLevelNewNodes.length - 1];
                } else if (currentLevelNewNodes.length > 1) {
                    self.sideNodes[level] = currentLevelNewNodes[currentLevelNewNodes.length - 2];
                }
            }

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

        // Update tree size
        self.size = oldTreeSize + leaves.length;

        self.sideNodes[treeDepth] = currentLevelNewNodes[0];

        return currentLevelNewNodes[0];
    }

    /// @dev Returns `hasher(currentNode, currentNode)`, reading the cache when
    /// warm and computing+storing on a miss. Generic memoizer for `f(x) = H(x, x)`:
    /// any chain that reaches `currentNode` at any level for any starting value
    /// shares the same entry. Factored out of the main loop to keep the
    /// per-iteration stack under Solidity's 16-slot limit.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param value: The value to hash with itself.
    /// @return `hasher(currentNode, currentNode)`.
    function _hashWithCache(
        SkinnyIMTData storage self,
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
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param value: The leaf value to insert `amount` copies of.
    /// @param amount: The number of leaves to append.
    /// @return root after the leaves have been appended.
    /// @return firstIndex index of the first appended leaf (inclusive).
    /// @return lastIndex index of the last appended leaf (inclusive).
    function _insertManyRepeated(
        SkinnyIMTData storage self,
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
            uint256 oldSideNode = self.sideNodes[level];
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

            // something happened, store it — but only at levels live for the new tree
            // (set bits of newSize == lastIndex + 1). Dead levels are overwritten by the
            // next insert before they're read, so refreshing them would be a wasted store.
            if (newSideNode != oldSideNode && ((lastIndex + 1) >> level) & 1 == 1) {
                self.sideNodes[level] = newSideNode;
            }

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
        self.sideNodes[newTreeDepth] = root;
        return (root, firstIndex, lastIndex);
    }

    /// @dev Warms the `(value, level)` cache for levels 1..`upToLevel` so that
    /// subsequent `_insertManyRepeated(value, ...)` calls hit the cache instead of
    /// re-hashing. Idempotent: levels already cached are not rewritten.
    /// @notice Useful when you know in advance the maximum depth a tree will reach
    /// for a particular `value` (e.g. zero) — pay the SSTOREs once, then every
    /// subsequent bulk-insert of that value reads cheaply from storage.
    /// @notice Reverts if the tree has not been initialized.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param value: The leaf value whose repeated-subtree chain to precompute.
    /// @param upToLevel: The highest level (inclusive) to populate the cache for.
    function _precomputeRepeatedCache(
        SkinnyIMTData storage self,
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
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param oldLeaf: The value of the leaf that is to be updated.
    /// @param newLeaf: The new value that will replace the oldLeaf in the tree.
    /// @param leafIndex: The index of the leaf to be updated.
    /// @param proofSiblings: An array of sibling nodes that are necessary to recalculate the path to the root.
    /// @return The new hash of the updated node after the leaf has been updated.
    /// @notice Requires collision-resistant hashing: `if (self.sideNodes[level] == oldRoot)` identifies
    /// which sideNode to refresh by hash equality,
    /// so a collision between two distinct subtree roots would corrupt tree state silently.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the old and newLeaf and proofSiblings are within the snark scalar field.
    function _update(
        SkinnyIMTData storage self,
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

        // verify merkle proof of oldLeaf from proofSiblings
        // and at the same time calculate the newRoot

        // note: this is basically just _proofToRoot twice on old and new leaf, then assert root from oldLeaf is
        // the current root. Difference is that self.sideNodes[level] = newNode gets assigned when newNode is an
        // edge node. Thats when newNode is left.
        for (uint256 level = 0; level < treeDepth; ) {
            // leafIndex is odd / is right
            if ((leafIndex >> level) & 1 == 1) {
                // no newNode to store in sideNodes to store here, the next insert does not need it if it already
                // has a sibling
                newNode = hasher([proofSiblings[siblingIndex], newNode]);
                oldNode = hasher([proofSiblings[siblingIndex], oldNode]);

                unchecked {
                    ++siblingIndex;
                }
            } else {
                if (leafIndex >> level != edgeIndex >> level) {
                    // does the index of newNode at the current level,
                    // share a parent with the lastIndex at the current level?
                    // So newNode/lastIndex current index == index >> level, then add +1 to level to get the parent

                    // @notice used to be simple self.sideNodes[level] == oldNode equality check in leanIMT,
                    // but duplicate values occurring break this assumption
                    //
                    // The geometry test (shares a parent with the last leaf) says this node IS the one
                    // stored in sideNodes[level]. The extra `(treeSize >> level) & 1 == 1` is a liveness
                    // filter: the slot is only read again if the next appended leaf lands as a right child
                    // at this level (a set bit of the leaf count). Otherwise the next insert overwrites the
                    // slot before reading, so refreshing it here would be a dead write.
                    if ((treeSize >> level) & 1 == 1 && leafIndex >> (level + 1) == edgeIndex >> (level + 1)) {
                        // because the leanIMT structure creates a unbalanced tree which hoist internal nodes or leafs
                        // up if the size is not even after a insert.
                        // the sideNodes being stored is not always at edgeIndex. At size 5 for example. Index 4 needs
                        // the grand parent of 0,1,2,3. And 4 is hoisted up to that level and hashed with
                        // that grand parent. Which is hash(grandParent, index_4).
                        // This only happens if the next node above is a edgeNode. That's why we check:
                        // leafIndex >> (level + 1) == edgeIndex >> (level + 1)
                        // But that stores every node that happens to have a left sibling that is an edge node.
                        // But we don't need all of those, because the next insert only needs siblings that are left
                        // to the insert. So we do
                        // (treeSize >> level) & 1 == 1
                        // treeSize == nextInsertIndex. And we check if the next insert of the index lays to the left
                        // thus needs to do hash(sidNodes,insertedNode). Which is the only case we actually need to
                        // have this side node
                        self.sideNodes[level] = newNode;
                    }

                    newNode = hasher([newNode, proofSiblings[siblingIndex]]);
                    oldNode = hasher([oldNode, proofSiblings[siblingIndex]]);

                    unchecked {
                        ++siblingIndex;
                    }
                } else if ((treeSize >> level) & 1 == 1) {
                    // cary up this side node, it dangles (same liveness filter as above)
                    self.sideNodes[level] = newNode;
                }
                // others that aren't leafs get carried up without adding to sideNodes
            }

            unchecked {
                ++level;
            }
        }

        if (oldNode != _root(self)) {
            revert WrongSiblingNodes();
        }

        self.sideNodes[treeDepth] = newNode;

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
        uint256[] currentNodes;
        uint256[] currentPositions;
        uint256[] nextNodes;
        uint256[] nextPositions;
    }

    struct MultiProofArrLevelPositions {
        uint256 currentNodesFreeSlot;
        uint256 nextNodesFreeSlot;
        uint256 proofSiblingsReadPos;
        uint256 edgePos;
        uint256 level;
        uint256 newSideNode;
        bool isNewSideNode;
    }

    /// @dev Folds one tree level: reads the known nodes in `currentNodes` (positions in
    /// `currentPositions`) and writes their parents into `nextNodes` / `nextPositions`,
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
        // The sideNode at this level is, by definition, the node at position (treeSize >> level) - 1,
        // and it only exists (is read by a future insert) when this level is live: (treeSize >> level) & 1 == 1.
        // That position is always even (a left / left-frontier node), so the main loop below always visits it
        // (only odd siblings are skipped via `continue`). When not live, use a sentinel that no position matches.
        // If that exact node is among the ones we recompute, we hand its new value back so the caller can store
        // it into self.sideNodes[level]. This uniformly covers the "shares a parent with the edge" case and the
        // dangling-edge case, and stores the node AT this level (never its parent).
        uint256 treeSize = proof.edgeIndex + 1;
        uint256 frontierPos = ((treeSize >> levelPos.level) & 1 == 1)
            ? (treeSize >> levelPos.level) - 1
            : type(uint256).max;

        for (uint256 i = 0; i < levelPos.currentNodesFreeSlot; i++) {
            if (levelState.currentPositions[i] == frontierPos) {
                levelPos.newSideNode = levelState.currentNodes[i];
                levelPos.isNewSideNode = true;
            } else {
                levelPos.isNewSideNode = false;
            }

            // hash left or right
            if (levelState.currentPositions[i] & 1 == 1) {
                if (i != 0 && (levelState.currentPositions[i - 1] == (levelState.currentPositions[i] - 1))) {
                    // last node in currentNodes is a sibling, skip now so we hashed it already
                    continue;
                }
                levelState.nextNodes[levelPos.nextNodesFreeSlot] = hasher(
                    [proof.proofSiblings[levelPos.proofSiblingsReadPos], levelState.currentNodes[i]]
                );
                levelState.nextPositions[levelPos.nextNodesFreeSlot] = levelState.currentPositions[i] >> 1;

                unchecked {
                    ++levelPos.nextNodesFreeSlot;
                    ++levelPos.proofSiblingsReadPos;
                }
            } else {
                // make sure node index is not at the edge because edges should be carried up a level
                // TODO these variable names are so long the auto format makes the code unreadable
                if (levelState.currentPositions[i] != levelPos.edgePos) {
                    if (
                        (i + 1) < levelPos.currentNodesFreeSlot &&
                        (levelState.currentPositions[i + 1] == (levelState.currentPositions[i] + 1))
                    ) {
                        // sibling is in currentNodes to the left, so use that instead
                        levelState.nextNodes[levelPos.nextNodesFreeSlot] = hasher(
                            [levelState.currentNodes[i], levelState.currentNodes[i + 1]]
                        );
                        levelState.nextPositions[levelPos.nextNodesFreeSlot] = levelState.currentPositions[i] >> 1;
                    } else {
                        levelState.nextNodes[levelPos.nextNodesFreeSlot] = hasher(
                            [levelState.currentNodes[i], proof.proofSiblings[levelPos.proofSiblingsReadPos]]
                        );
                        levelState.nextPositions[levelPos.nextNodesFreeSlot] = levelState.currentPositions[i] >> 1;

                        unchecked {
                            ++levelPos.proofSiblingsReadPos;
                        }
                    }
                } else {
                    levelState.nextNodes[levelPos.nextNodesFreeSlot] = levelState.currentNodes[i];
                    levelState.nextPositions[levelPos.nextNodesFreeSlot] = levelState.currentPositions[i] >> 1;
                }
                ++levelPos.nextNodesFreeSlot;
            }
        }

        // per level updates
        levelPos.edgePos >>= 1;

        for (uint256 k = 0; k < levelPos.nextNodesFreeSlot; k++) {
            levelState.currentNodes[k] = levelState.nextNodes[k];
            levelState.currentPositions[k] = levelState.nextPositions[k];
        }
        levelPos.currentNodesFreeSlot = levelPos.nextNodesFreeSlot;
        levelPos.nextNodesFreeSlot = 0;
        return (levelState, levelPos);
    }

    // would save 2 array in memory, more importantly stack pressure
    function _proofManyToRoot(
        MultiProof memory proof,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        uint256 leafCount = proof.leaves.length;
        if (leafCount == 0 || leafCount != proof.leafIndexes.length) {
            revert WrongMultiProof();
        }

        MultiProofLevelState memory levelState = MultiProofLevelState(
            new uint256[](leafCount),
            new uint256[](leafCount),
            new uint256[](leafCount),
            new uint256[](leafCount)
        );

        MultiProofArrLevelPositions memory levelPositions = MultiProofArrLevelPositions(
            0,
            0,
            0,
            proof.edgeIndex,
            0,
            0,
            false
        );

        // Seed every proven leaf at level 0, at its real index. Each leaf is then hashed up
        // from the bottom, so an internal-node value or a wrong index simply produces a
        // non-matching root — nothing can enter above level 0 un-hashed. Dangling is resolved
        // while climbing (the edge-carry in _hashMultiProofLevel), derived from `edgeIndex`.
        for (uint256 i = 0; i < leafCount; i++) {
            levelState.currentNodes[i] = proof.leaves[i];
            levelState.currentPositions[i] = proof.leafIndexes[i];
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
        return levelState.currentNodes[0];
    }

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function _root(SkinnyIMTData storage self) internal view returns (uint256) {
        return self.sideNodes[self.depth];
    }
}

// @notes contract size limit work around: use _hashMultiProofLevel for both proofManyToRoot as updateMany
// same with plain update
// _hashMultiProofLevel uses 2 arrays for tracking nodes. currentLevel and nextLevel. You can prob just do it in 1
// same for insertMany probably, but that is vivians code so i would rather keep it as similar as possible
// and ofc we can just split into multiple contracts that export these internal functions. example move verify functions
// outside of SkinnyIMTPoseidon2

// old unused code
// this is not used because it only adds to contract size and gas of these functions.
// it does read easier and more consistently with the other implementation
//------------ update and proofToRoot written with hashLevel pattern like updateMany and proofManyToRoot -------------
// /// @dev Updates the value of an existing leaf and recalculates hashes
// /// to maintain tree integrity.
// /// @param self: A storage reference to the 'SkinnyIMTData' struct.
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
//     SkinnyIMTData storage self,
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
