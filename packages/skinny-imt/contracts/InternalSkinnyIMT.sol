// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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

error WrongSiblingNodes();
error LeafDoesNotExist();
error NotInitialized();
error AlreadyInitialized();

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
    /// @return The new hash of the node after the leaf has been inserted.
    function _insert(
        SkinnyIMTData storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
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
        return node;
    }

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
        uint256 treeSize = self.size;

        // Array to save the nodes that will be used to create the next level of the tree.
        uint256[] memory currentLevelNewNodes;

        currentLevelNewNodes = leaves;

        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;

        // Calculate the depth of the tree after adding the new values.
        // Unlike the 'insert' function, we need a while here as
        // N insertions can increase the tree's depth more than once.
        while (2 ** treeDepth < treeSize + leaves.length) {
            ++treeDepth;
        }
        self.depth = treeDepth;

        // First index to change in every level.
        uint256 currentLevelStartIndex = treeSize;

        // Size of the level used to create the next level.
        uint256 currentLevelSize = treeSize + leaves.length;

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
            if (currentLevelSize & 1 == 1) { // currentLevelSize % 2 == 1, is odd
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
        self.size = treeSize + leaves.length;

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
    /// @notice Costs `O(log(size + amount))` hashes regardless of `amount`. Instead
    /// of running `_insert` once per leaf (which would walk the tree `amount` times),
    /// this walks once and carries three values up the levels together:
    ///
    ///   - `rightEdgeNode`         — value of the node on the rightmost path of the
    ///                         new tree (the path from the newly-appended last
    ///                         leaf up to the root). This is what a future
    ///                         `_insert` will expect to find in the `sideNodes`
    ///                         of the rightmost spine.
    ///   - `lefEdgeNode`        — value of the node on the path of leaf `oldSize`
    ///                         (the very first new leaf). Needed when the new
    ///                         sideNode subtree straddles the old/new boundary —
    ///                         i.e. it contains some pre-existing leaves on the
    ///                         left of `oldSize` and some new `value` leaves on
    ///                         the right.
    ///   - `repeatedCenterNode` — the root of a fully-populated subtree of `value`s
    ///                         at the current level, defined recursively as
    ///                         `hasher(prev-level root, prev-level root)`.
    ///                         Reused for any sideNode subtree that lies
    ///                         entirely in the new-leaves region.
    ///
    /// `repeatedSubtree` values are cached in storage per `(value, level)` pair,
    /// so subsequent calls with the same `value` skip those hashes entirely. The
    /// first call pays one SSTORE per level; later calls pay only one SLOAD per
    /// level. Use `_precomputeRepeatedCache` to warm the cache up front.
    ///
    /// `amount == 1` falls through to `_insert` because for a single leaf the
    /// per-level overhead of maintaining three values plus the cache would
    /// dominate.
    /// @notice No per-leaf events: callers reconstruct ranges off-chain from
    /// `(size, depth)` and the constant `value`. The wrapper at SkinnyIMT.sol level
    /// matches that contract.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param value: The leaf value to insert `amount` copies of.
    /// @param amount: The number of leaves to append.
    /// @return The root after the leaves have been appended.
    function _insertManyRepeated(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        if (_isInitialized(self) == false) {
            revert NotInitialized();
        }
        if (amount == 0) {
            return _root(self);
        }
        if (amount == 1) {
            return _insert(self, value, hasher);
        }

        uint256 oldSize = self.size;
        uint256 treeDepth = self.depth;
        uint256 lastIndex;
        {
            // `newSize` is only needed for depth growth and the size/lastIndex
            // assignments; scoped to a block so its slot is released before
            // the main loop (Solidity's 16-slot stack is tight here).
            uint256 newSize = oldSize + amount;
            while (2 ** treeDepth < newSize) {
                unchecked {
                    ++treeDepth;
                }
            }
            self.depth = treeDepth;
            self.size = newSize;
            lastIndex = newSize - 1;
        }

        // Initial values at level 0:
        //   rightEdgeNode = at the start does not contain any leafs of existing tree, but later will. Can also have some dangling nodes which also also throws off the cache
        //   leftEdgeNode = The node that potentially mixes with the existing tree. There for are not guaranteed to be in cache
        //   repeatedCenterNode = always balanced and only contains the repeated values. Always cache-able
        uint256 rightEdgeNode = value;
        uint256 lefEdgeNode = value;
        uint256 repeatedCenterNode = value;

        for (uint256 level = 0; level < treeDepth; ) {
            uint256 oldSideNode = self.sideNodes[level];
            uint256 newSideNode;
            {
                // `newPosition` = position of the last leaf's ancestor at this level
                //            (each step up halves the position, so it's `lastIndex / 2^level`).
                // `boundaryPosition` = position of the first new leaf's ancestor at this level.
                uint256 newPosition = lastIndex >> level;
                uint256 boundaryPosition = oldSize >> level;

                // The new sideNode at this level is the subtree whose position
                // is the rightmost path's position rounded down to even — i.e. the
                // left-of-the-pair node containing the rightmost path.
                // Four cases for what that subtree contains:
                if (newPosition & 1 == 0) {
                    // The rightmost path is already at an even position (a left
                    // child). So the rightmost-path node itself IS the sideNode.
                    newSideNode = rightEdgeNode;
                } else if (newPosition - 1 > boundaryPosition) {
                    // The rightmost path is at an odd position (right child), so
                    // the sideNode is its left sibling at `newPosition - 1`. That
                    // sibling sits strictly to the right of the first-new-leaf's
                    // ancestor, meaning its whole subtree is past `oldSize`. Since
                    // the rightmost path is even further right, the sibling
                    // subtree must be fully populated — value is the repeated-subtree root at this level.
                    newSideNode = repeatedCenterNode;
                } else if (newPosition - 1 == boundaryPosition) {
                    // Same right-sibling case, but now the left sibling subtree IS
                    // the one containing leaf `oldSize` — the boundary subtree
                    // with pre-existing leaves on the left and new `value` leaves
                    // on the right. Use the boundary value built up the levels.
                    newSideNode = lefEdgeNode;
                } else {
                    // Same right-sibling case, but the left sibling is strictly
                    // to the left of `oldSize`'s ancestor — its subtree is
                    // entirely pre-existing leaves, so its value cannot have
                    // changed. The stored sideNode is still correct.
                    newSideNode = oldSideNode;
                }
            }

            if (newSideNode != oldSideNode) {
                self.sideNodes[level] = newSideNode;
            }

            // Lift pathValue one level up. The last leaf is in either the left or
            // right child of its parent at this level — check by looking at the
            // parity of its position at this level:
            //   - odd position (right child): combine with the left sibling
            //     (the sideNode we just figured out) to get the parent's value.
            //   - even position (left child): the right sibling has no descendants,
            //     so by the dangling rule the parent's value equals the left
            //     child's value — pathValue is unchanged.
            
            // calculate index of the newSide node at this level and check if it's odd or even
            // oldSize / (2**level) % 2
            // if odd it means rightEdgeNode has a left sibling is not allowed to dangle
            // so it needs to be hashed on this level.

            // @TODO when newPosition & 1 == 0, newSideNode == rightEdgeNode
            // in a lott but not every case rightEdgeNode is a cache-able value
            // in the cases it's not is either because the left edge node started dangling
            // or the left side of the existing tree is mixing in, but that could still be cache-able if the tree had the same repeatingValue in it
            if ((lastIndex >> level) & 1 == 1) {
                rightEdgeNode = hasher([newSideNode, rightEdgeNode]);
            }

            // Lift boundary one level up. Same idea, but for the first-new-leaf's
            // path (leaf `oldSize`):
            //   - `oldSize` is the right child at this level: the left sibling
            //     subtree is entirely pre-existing leaves, so it equals the
            //     OLD stored sideNode.
            //   - `oldSize` is the left child at this level: the right sibling
            //     subtree is entirely in the new-leaves region. While the boundary
            //     and rightmost paths haven't yet merged (the boundary subtree
            //     isn't itself the rightmost subtree), that right sibling is
            //     fully populated, so its value is the repeated-subtree root at this level.
            //
            // Once the two paths converge at the top of the tree, this formula
            // becomes stale (the right sibling may actually be partially
            // populated). At that point `boundary` is no longer read for any
            // sideNode decision, so the stale write is harmless.

            // calculate index of the boundary node at this level and check if it's odd or even
            // oldSize / (2**level) % 2
            if ((oldSize >> level) & 1 == 1) {
                lefEdgeNode = hasher([oldSideNode, lefEdgeNode]);
            } else {
                lefEdgeNode = hasher([lefEdgeNode, repeatedCenterNode]);
            }

            // Advance level first so it doubles as `nextLevel` for the cache lift.
            unchecked {
                ++level;
            }

            // hash(repeatedCenterNode, repeatedCenterNode), via the f(x) = H(x, x)
            // memo cache (fills the cache on miss).
            repeatedCenterNode = _hashWithCache(self, repeatedCenterNode, hasher);
        }

        // `sideNodes[treeDepth]` always stores the root (see `_root`). After the
        // loop, the rightmost path at the top level IS the new root.
        self.sideNodes[treeDepth] = rightEdgeNode;
        return rightEdgeNode;
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
    /// @param index: The index of the leaf to be updated.
    /// @param siblingNodes: An array of sibling nodes that are necessary to recalculate the path to the root.
    /// @return The new hash of the updated node after the leaf has been updated.
    /// @notice Requires collision-resistant hashing: `if (self.sideNodes[level] == oldRoot)` identifies
    /// which sideNode to refresh by hash equality, so a collision between two distinct subtree roots would corrupt tree state silently.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the old and newLeaf and siblingNodes are within the snark scalar field.
    function _update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 index,
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
        uint256 node = newLeaf;
        uint256 oldRoot = oldLeaf;

        uint256 lastIndex = self.size - 1;

        uint256 i = 0;

        // verify merkle proof of oldLeaf from siblingNodes
        // and at the same time calculate the newRoot
        for (uint256 level = 0; level < treeDepth; ) {
            if ((index >> level) & 1 == 1) {
                node = hasher([siblingNodes[i], node]);
                oldRoot = hasher([siblingNodes[i], oldRoot]);

                unchecked {
                    ++i;
                }
            } else {
                if (index >> level != lastIndex >> level) {
                    if (self.sideNodes[level] == oldRoot) {
                        self.sideNodes[level] = node;
                    }

                    node = hasher([node, siblingNodes[i]]);
                    oldRoot = hasher([oldRoot, siblingNodes[i]]);

                    unchecked {
                        ++i;
                    }
                } else {
                    self.sideNodes[level] = node;
                }
            }

            unchecked {
                ++level;
            }
        }

        if (oldRoot != _root(self)) {
            revert WrongSiblingNodes();
        }

        self.sideNodes[treeDepth] = node;

        //self.leaves[index] = newLeaf;

        return node;
    }

    /// @dev Hashes merkle proof and returns the root the leaf belongs to
    /// @param leaf: The leaf to proof inclusion of
    /// @param index: The index of the leaf within the tree.
    /// @param siblingNodes: The sibling nodes along the path from the leaf to the root.
    /// @return The root obtained from hashing the leaf with the provided siblings.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the leaf and siblingNodes are within the snark scalar field.
    function _rootFromSiblings(
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        uint256 oldRoot = leaf;

        uint256 i = 0;

        uint256 proofDepth = siblingNodes.length;

        for (uint256 level = 0; level < proofDepth; ) {
            if ((index >> level) & 1 == 1) {
                oldRoot = hasher([siblingNodes[i], oldRoot]);

                unchecked {
                    ++i;
                }
            } else {
                oldRoot = hasher([oldRoot, siblingNodes[i]]);

                unchecked {
                    ++i;
                }
            }

            unchecked {
                ++level;
            }
        }
        return oldRoot;
    }

    /// @dev Checks if a leaf exists in the tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the leaf to check for existence.
    /// @param index: The index of the leaf in the tree.
    /// @param siblingNodes: An array of sibling nodes used to recompute the root for the given leaf.
    /// @return A boolean value indicating whether the leaf exists in the tree.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the leaf and siblingNodes are within the snark scalar field.
    function _verify(
        SkinnyIMTData storage self,
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (bool) {
        uint256 rootSiblings = _rootFromSiblings(leaf, index, siblingNodes, hasher);
        return rootSiblings == _root(self);
    }

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function _root(SkinnyIMTData storage self) internal view returns (uint256) {
        return self.sideNodes[self.depth];
    }
}
