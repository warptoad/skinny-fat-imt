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

error WrongSiblingNodes();
error LeafDoesNotExist();
error NotInitialized();
error AlreadyInitialized();
error LeafGreaterThanSnarkScalarField();
error WrongMultiProof();

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
                // Stored in sideNodes, for when it will have an right sibling eventually
                self.sideNodes[level] = node;
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
            if (currentLevelSize & 1 == 1) {
                // currentLevelSize % 2 == 1, is odd
                // currentLevelSize = treeSize + leaves.length
                // currentLevelSize = (currentLevelSize - 1) / 2 + 1
                self.sideNodes[level] = currentLevelNewNodes[currentLevelNewNodes.length - 1];
            } else if (currentLevelNewNodes.length > 1) {
                self.sideNodes[level] = currentLevelNewNodes[currentLevelNewNodes.length - 2];
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

            // something happened, store it!
            if (newSideNode != oldSideNode) {
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
    /// @param siblingNodes: An array of sibling nodes that are necessary to recalculate the path to the root.
    /// @return The new hash of the updated node after the leaf has been updated.
    /// @notice Requires collision-resistant hashing: `if (self.sideNodes[level] == oldRoot)` identifies
    /// which sideNode to refresh by hash equality,
    /// so a collision between two distinct subtree roots would corrupt tree state silently.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the old and newLeaf and siblingNodes are within the snark scalar field.
    function _update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata siblingNodes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        if (_isInitialized(self) == false) {
            revert NotInitialized();
        }
        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;
        if (siblingNodes.length > treeDepth) {
            revert WrongSiblingNodes();
        }

        // 2 vars to store intermediate hashes, to hash up to oldRoot and newRoot
        uint256 newNode = newLeaf;
        uint256 oldNode = oldLeaf;

        // index of the very last leaf in the tree
        // tracking this index up the tree, follows the indexes of the nodes in self.sidNodes
        uint256 lastIndex = self.size - 1;

        uint256 i = 0;

        // verify merkle proof of oldLeaf from siblingNodes
        // and at the same time calculate the newRoot

        // TODO do _verify instead. Check how much gas that adds
        for (uint256 level = 0; level < treeDepth; ) {
            if ((leafIndex >> level) & 1 == 1) {
                // no newNode to store in sideNodes to store here, the next insert does not need it if it already
                // has a sibling
                newNode = hasher([siblingNodes[i], newNode]);
                oldNode = hasher([siblingNodes[i], oldNode]);

                unchecked {
                    ++i;
                }
            } else {
                if (leafIndex >> level != lastIndex >> level) {
                    // does the index of newNode at the current level,
                    // share a parent with the lastIndex at the current level?
                    // So newNode/lastIndex current index == index >> level, then add +1 to level to get the parent

                    // @notice used to be simple self.sideNodes[level] == oldNode equality check in leanIMT,
                    // but duplicate values occurring break this assumption
                    if (leafIndex >> (level + 1) == lastIndex >> (level + 1)) {
                        // same parent on next level, so newNode is a left sibling of !
                        self.sideNodes[level] = newNode;
                    }

                    newNode = hasher([newNode, siblingNodes[i]]);
                    oldNode = hasher([oldNode, siblingNodes[i]]);

                    unchecked {
                        ++i;
                    }
                } else {
                    self.sideNodes[level] = newNode;
                }
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
    /// @param leaf: The leaf to proof inclusion of
    /// @param index: The index of the leaf within the tree.
    /// @param siblingNodes: The sibling nodes along the path from the leaf to the root.
    /// @return The root obtained from hashing the leaf with the provided siblings.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the leaf and siblingNodes are within the snark scalar field.
    function _proofToRoot(
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        uint256 node = leaf;

        uint256 i = 0;

        uint256 proofDepth = siblingNodes.length;

        for (uint256 level = 0; level < proofDepth; ) {
            if ((index >> level) & 1 == 1) {
                node = hasher([siblingNodes[i], node]);

                unchecked {
                    ++i;
                }
            } else {
                node = hasher([node, siblingNodes[i]]);

                unchecked {
                    ++i;
                }
            }

            unchecked {
                ++level;
            }
        }
        return node;
    }

    // /// @dev The state a multiproof carries as it climbs the tree, one level at a
    // /// time. Passed to `_climbMultiProofLevel` by reference so that helper costs a
    // /// single stack slot instead of three separate ones — the function-type
    // /// `hasher` and the calldata sibling stream already crowd its stack frame.
    // struct MultiProofState {
    //     // The positions, at the current level, of the nodes we already know.
    //     // Always kept in ascending order. As we climb, each entry is overwritten
    //     // with its parent's position: a level never has more parents than
    //     // children, and a parent is always written behind the node we are reading,
    //     // so the in-place overwrite never clobbers a child we still need.
    //     uint256[] knownPositions;
    //     // The values of those known nodes, overwritten with their parents' values
    //     // in lock-step with `knownPositions`.
    //     uint256[] knownValues;
    //     // How many entries of `knownPositions` / `knownValues` are live this level.
    //     uint256 knownCount;
    // }

    // /// @dev Climbs the multiproof up one level: reads the known nodes at the
    // /// current level and writes their parents (in place) for the next level up.
    // ///
    // /// `levelSize` is the number of nodes the whole tree has at this level
    // /// (ceil of size over 2 per level climbed), so it marks where the tree's
    // /// right edge sits. Walking the known nodes from left to right, each one is
    // /// a left child (even position) or a right child (odd position), and its
    // /// sibling is found in one of three places:
    // ///   dangle: the node is the rightmost of the level, so its right-sibling
    // ///           position lands past the edge and no sibling exists. A dangling
    // ///           node has no one to hash with — its parent is the node carried up
    // ///           unchanged (the tree's zero-less parent rule). No sibling spent.
    // ///   pair:   the very next known node is exactly its right sibling. The two
    // ///           combine directly, so again no proof sibling is spent.
    // ///   proof:  anything else — the missing sibling is read from the flat
    // ///           `siblings` stream at `siblingCursor`.
    // /// A right child always lands in the `proof` case: were its left sibling a
    // /// known node, that node (sitting to its left) would have consumed this one
    // /// as its `pair` earlier in the walk.
    // ///
    // /// @param state Climbing state; `state.knownCount` is updated to the parent count.
    // /// @param levelSize Node count of the tree at this level; marks the right edge.
    // /// @param siblingCursor How many entries of `siblings` have been spent so far.
    // /// @param siblings The flat, bottom-up / left-to-right proof-sibling stream.
    // /// @return The sibling cursor after this level's siblings are spent.
    // /// @notice Reverts `WrongMultiProof` if a node needs a proof sibling but the
    // /// stream is already exhausted.
    // function _climbMultiProofLevel(
    //     MultiProofState memory state,
    //     uint256 levelSize,
    //     uint256 siblingCursor,
    //     uint256[] calldata siblings,
    //     function(uint256[2] memory) view returns (uint256) hasher
    // ) private view returns (uint256) {
    //     // `readCursor` walks the known nodes (the children) left to right;
    //     // `parentCount` is where we write the next parent and, at the end, the
    //     // number of parents produced. parentCount always trails readCursor, which
    //     // is why overwriting the arrays in place is safe.
    //     uint256 parentCount = 0;
    //     uint256 readCursor = 0;
    //     while (readCursor < state.knownCount) {
    //         uint256 childPosition = state.knownPositions[readCursor];
    //         uint256 childValue = state.knownValues[readCursor];

    //         if (childPosition & 1 == 0) {
    //             // -------------- left child (even position) --------------
    //             if (childPosition + 1 >= levelSize) {
    //                 // dangle: this is the rightmost node of the level, it has no
    //                 // right sibling, so the parent is just this node carried up.
    //                 state.knownValues[parentCount] = childValue;
    //             } else if (
    //                 readCursor + 1 < state.knownCount &&
    //                 state.knownPositions[readCursor + 1] == childPosition + 1
    //             ) {
    //                 // pair: the next known node is this node's right sibling.
    //                 state.knownValues[parentCount] = hasher([childValue, state.knownValues[readCursor + 1]]);
    //                 // Consume that sibling too, so we don't visit it as its own node.
    //                 unchecked {
    //                     ++readCursor;
    //                 }
    //             } else {
    //                 // proof: the right sibling comes from the flat stream.
    //                 if (siblingCursor >= siblings.length) {
    //                     revert WrongMultiProof();
    //                 }
    //                 state.knownValues[parentCount] = hasher([childValue, siblings[siblingCursor]]);
    //                 unchecked {
    //                     ++siblingCursor;
    //                 }
    //             }
    //         } else {
    //             // -------------- right child (odd position) --------------
    //             // Its left sibling is always a proof sibling: a known left sibling
    //             // would have paired with this node back when we visited it.
    //             if (siblingCursor >= siblings.length) {
    //                 revert WrongMultiProof();
    //             }
    //             state.knownValues[parentCount] = hasher([siblings[siblingCursor], childValue]);
    //             unchecked {
    //                 ++siblingCursor;
    //             }
    //         }

    //         // The parent sits one level up at half this node's position.
    //         state.knownPositions[parentCount] = childPosition >> 1;
    //         unchecked {
    //             ++parentCount;
    //             ++readCursor;
    //         }
    //     }

    //     state.knownCount = parentCount;
    //     return siblingCursor;
    // }

    // /// @dev Recomputes the root a shared (deduplicated) Merkle multiproof implies —
    // /// the many-leaf analog of `_rootFromSiblings`. Whether each node hashes on its
    // /// left or right is read from its index; where nodes dangle (the tree's right
    // /// edge) is read from `size`. It touches no tree state, so the very same proof
    // /// rebuilds whichever root the inputs describe: pass the current `size` (and
    // /// compare against the current root) for a present-day check, or a past `size`
    // /// for a historical root. `siblings` is the flat, bottom-up / left-to-right
    // /// list of exactly the nodes that can't be derived from the supplied leaves.
    // ///
    // /// @notice `indices` must be strictly increasing (which also makes them
    // /// unique); `leaves[proofLeaf]` is the value claimed at `indices[proofLeaf]`.
    // /// @notice Contracts using this function with snark based hash functions,
    // /// need to check that the leaves and siblings are within the snark scalar field.
    // /// @notice Reverts `WrongMultiProof` on a structurally malformed proof (empty
    // /// or length-mismatched inputs, non-increasing or out-of-range indices, or the
    // /// wrong number of siblings). A well-formed proof carrying wrong values simply
    // /// rebuilds a different (non-matching) root.
    // /// @param leaves: The leaf values, ordered by ascending index.
    // /// @param indices: The strictly-increasing indices of `leaves`.
    // /// @param siblings: Flat sibling list, bottom-up and left-to-right.
    // /// @param size: The leaf count of the tree whose root is being rebuilt.
    // /// @return The root implied by the proof.
    // function _rootFromMultiProof(
    //     uint256[] calldata leaves,
    //     uint256[] calldata indices,
    //     uint256[] calldata siblings,
    //     uint256 size,
    //     function(uint256[2] memory) view returns (uint256) hasher
    // ) internal view returns (uint256) {
    //     // Seed the climb's level 0 with the supplied leaves. The leaf and index
    //     // calldata arrays are only read here, so this setup lives in its own block
    //     // and the struct `state` carries everything the climb needs afterwards —
    //     // the same slot-freeing trick `_insertManyRepeated` uses for its counters.
    //     MultiProofState memory state;
    //     {
    //         uint256 leafCount = leaves.length;
    //         if (leafCount == 0 || leafCount != indices.length) {
    //             revert WrongMultiProof();
    //         }
    //         // The largest index must name a leaf that exists in a tree this size.
    //         if (indices[leafCount - 1] >= size) {
    //             revert WrongMultiProof();
    //         }
    //         state.knownPositions = new uint256[](leafCount);
    //         state.knownValues = new uint256[](leafCount);
    //         for (uint256 proofLeaf = 0; proofLeaf < leafCount; ) {
    //             // Strictly increasing indices keep the left-to-right pairing in
    //             // `_climbMultiProofLevel` well defined: siblings sit side by side.
    //             if (proofLeaf != 0 && indices[proofLeaf] <= indices[proofLeaf - 1]) {
    //                 revert WrongMultiProof();
    //             }
    //             state.knownPositions[proofLeaf] = indices[proofLeaf];
    //             state.knownValues[proofLeaf] = leaves[proofLeaf];
    //             unchecked {
    //                 ++proofLeaf;
    //             }
    //         }
    //         state.knownCount = leafCount;
    //     }

    //     // Climb one tree level per iteration. `levelSize` is the node count at the
    //     // current level; it shrinks (rounding up, because an odd node dangles into
    //     // the next level) until the tree holds a single node — the root — at which
    //     // point the known nodes have collapsed onto that same node. `siblingCursor`
    //     // threads through every level so siblings are spent in one continuous order.
    //     uint256 siblingCursor = 0;
    //     uint256 levelSize = size;
    //     while (levelSize > 1) {
    //         siblingCursor = _climbMultiProofLevel(state, levelSize, siblingCursor, siblings, hasher);
    //         levelSize = (levelSize + 1) >> 1;
    //     }

    //     // A valid proof collapses to exactly the root and spends every sibling it
    //     // supplied — a leftover count (too many) or an early stop (too few) both
    //     // mean the proof was malformed.
    //     if (state.knownCount != 1 || siblingCursor != siblings.length) {
    //         revert WrongMultiProof();
    //     }
    //     return state.knownValues[0];
    // }

    function _proofManyToRoot(
        uint256[] calldata leaves,
        uint256[] calldata indexes,
        uint256[] calldata siblings,
        uint256 size,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {}

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function _root(SkinnyIMTData storage self) internal view returns (uint256) {
        return self.sideNodes[self.depth];
    }
}
