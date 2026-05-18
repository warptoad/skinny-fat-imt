// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";
import {SNARK_SCALAR_FIELD} from "./Constants.sol";

struct SkinnyIMTData {
    // Tracks the current number of leaves in the tree.
    uint256 size;
    // Represents the current depth of the tree, which can increase as new leaves are inserted.
    uint256 depth;
    // A mapping from each level of the tree to the node value of the last even position at that level.
    // Used for efficient inserts, updates and root calculations.
    mapping(uint256 => uint256) sideNodes;
    // A mapping of leaf = leaves[index].
    // This facilitates checks for leaf existence and retrieval of all leaves.
    mapping(uint256 => uint256) leaves;

    //@TODO use since it can be retrieved extremely fast with debug_storageRangeAt
    //uint256[] public leaves;
}

error WrongSiblingNodes();
error LeafGreaterThanSnarkScalarField();
error LeafDoesNotExist();

/// @title Skinny Incremental binary Merkle tree.
/// @dev The SkinnyIMT is an optimized version of the BinaryIMT.
/// This implementation eliminates the use of zeroes, and make the tree depth dynamic.
/// When a node doesn't have the right child, instead of using a zero hash as in the BinaryIMT,
/// the node's value becomes that of its left child. Furthermore, rather than utilizing a static tree depth,
/// it is updated based on the number of leaves in the tree. This approach
/// results in the calculation of significantly fewer hashes, making the tree more efficient.
library InternalSkinnyIMT {
    function _sideNode(SkinnyIMTData storage self, uint256 index) internal view returns (uint256) {
        return self.sideNodes[index];
    }

    // function _treeDepth(SkinnyIMTData storage self) internal view returns (uint256) {
    //     if (self.sideNodes.length == 0) return 0;
    //     return self.sideNodes.length - 1;
    // }

    // function _amountLeaves(SkinnyIMTData storage self) internal view returns (uint256) {
    //     return self.leaves.length;
    // }

    // function _updateSideNode(SkinnyIMTData storage self, uint256 node, uint256 index) internal {
    //     require(index <= self.sideNodes.length, "out of range");
    //     if (self.sideNodes.length == index) {
    //         self.sideNodes.push(node);
    //     } else {
    //         self.sideNodes[index] = node;
    //     }
    // }

    // function _updateLeaves(SkinnyIMTData storage self, uint256 leaf, uint256 index) internal {
    //     require(index <= self.leaves.length, "out of range");
    //     if (self.leaves.length == index) {
    //         self.leaves.push(leaf);
    //     } else {
    //         self.leaves[index] = leaf;
    //     }
    // }

    /// @dev Inserts a new leaf into the incremental merkle tree.
    /// The function ensures that the leaf is valid according to the
    /// constraints of the tree and then updates the tree's structure accordingly.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the new leaf to be inserted into the tree.
    /// @return The new hash of the node after the leaf has been inserted.
    function _insert(SkinnyIMTData storage self, uint256 leaf) internal returns (uint256) {
        if (leaf >= SNARK_SCALAR_FIELD) {
            revert LeafGreaterThanSnarkScalarField();
        }

        // array
        // uint256 index = self.leaves.length;
        // mapping
        uint256 index = self.size;

        // Cache tree depth to optimize gas
        uint256 treeDepth = self.depth;

        // A new insertion can increase a tree's depth by at most 1,
        // and only if the number of leaves supported by the current
        // depth is less than the number of leaves to be supported after insertion.
        if (2 ** treeDepth < index + 1) {
            ++treeDepth;
        }

        // mapping
        self.depth = treeDepth;

        uint256 node = leaf;

        for (uint256 level = 0; level < treeDepth; ) {
            if ((index >> level) & 1 == 1) {
                node = PoseidonT3.hash([self.sideNodes[level], node]);
            } else {
                // array
                //_updateSideNode(self, node, level);
                // mapping
                self.sideNodes[level] = node;
            }

            unchecked {
                ++level;
            }
        }

        // array code
        //self.sideNodes[treeDepth] = node;
        //@TODO (Claude wrote this): inline branching here — if the tree grew this insert, sideNodes.length == treeDepth so we push; otherwise treeDepth < sideNodes.length and we direct-write self.sideNodes[treeDepth] = node. Skips the helper's require + length read + branch on the hot path.
        // Est. savings: ~100-200 gas per _insert call (one redundant SLOAD on warm sideNodes.length for the require, plus the require string load + compare, plus internal call JUMP overhead). Roughly a 0.2-0.5% dent in a ~50k-gas warm insert.
        // _updateSideNode(self, node, treeDepth);
        // self.leaves.push(leaf);

        // mapping code
        self.sideNodes[treeDepth] = node;
        self.leaves[index] = leaf;
        // original did self.size = index++ above
        // since self.leaves[leaf] = index + 1. But that is no longer true
        self.size = index + 1;

        return node;
    }

    /// @dev Inserts many leaves into the incremental merkle tree.
    /// The function ensures that the leaves are valid according to the
    /// constraints of the tree and then updates the tree's structure accordingly.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaves: The values of the new leaves to be inserted into the tree.
    /// @return The root after the leaves have been inserted.
    function _insertMany(SkinnyIMTData storage self, uint256[] calldata leaves) internal returns (uint256) {
        // Cache tree size to optimize gas
        // array
        // uint256 treeSize = _amountLeaves(self);
        // mapping
        uint256 treeSize = self.size;

        // Check that all the new values are correct to be added.
        for (uint256 i = 0; i < leaves.length; ) {
            if (leaves[i] >= SNARK_SCALAR_FIELD) {
                revert LeafGreaterThanSnarkScalarField();
            }

            // array
            // self.leaves.push(leaves[i]);

            self.leaves[treeSize + i] = leaves[i];

            unchecked {
                ++i;
            }
        }

        // Array to save the nodes that will be used to create the next level of the tree.
        uint256[] memory currentLevelNewNodes;

        currentLevelNewNodes = leaves;

        // Cache tree depth to optimize gas
        // array
        // uint256 treeDepth = _treeDepth(self);
        // mapping
        uint256 treeDepth = self.depth;

        // Calculate the depth of the tree after adding the new values.
        // Unlike the 'insert' function, we need a while here as
        // N insertions can increase the tree's depth more than once.
        while (2 ** treeDepth < treeSize + leaves.length) {
            ++treeDepth;
        }

        // mapping
        self.depth = treeDepth;

        // First index to change in every level.
        uint256 currentLevelStartIndex = treeSize;

        // Size of the level used to create the next level.
        uint256 currentLevelSize = treeSize + leaves.length;

        // The index where changes begin at the next level.
        uint256 nextLevelStartIndex = currentLevelStartIndex >> 1;

        // The size of the next level.
        uint256 nextLevelSize = ((currentLevelSize - 1) >> 1) + 1;

        for (uint256 level = 0; level < treeDepth; ) {
            // The number of nodes for the new level that will be created,
            // only the new values, not the entire level.
            //uint256 numberOfNewNodes = nextLevelSize - nextLevelStartIndex;
            uint256[] memory nextLevelNewNodes = new uint256[](nextLevelSize - nextLevelStartIndex);
            for (uint256 i = 0; i < nextLevelSize - nextLevelStartIndex; ) {
                // packing left and right node in one array saves on the stack size
                uint256[2] memory hasherInput;

                // Assign the left node using the saved path or the position in the array.
                if ((i + nextLevelStartIndex) * 2 < currentLevelStartIndex) {
                    //leftNode = self.sideNodes[level];
                    hasherInput[0] = self.sideNodes[level];
                } else {
                    hasherInput[0] = currentLevelNewNodes[(i + nextLevelStartIndex) * 2 - currentLevelStartIndex];
                }

                uint256 parentNode;

                // Existence of a right child is an index check, not a value check —
                // zero is a valid leaf now, so `hasherInput[1] == 0` can't be used as a proxy.
                // If a right child exists: assign it and hash(left, right). Otherwise: parent = left.
                if ((i + nextLevelStartIndex) * 2 + 1 < currentLevelSize) {
                    hasherInput[1] = currentLevelNewNodes[(i + nextLevelStartIndex) * 2 + 1 - currentLevelStartIndex];
                    parentNode = PoseidonT3.hash(hasherInput);
                } else {
                    parentNode = hasherInput[0];
                }

                nextLevelNewNodes[i] = parentNode;

                unchecked {
                    ++i;
                }
            }

            // Update the `sideNodes` variable.
            // If `currentLevelSize` is odd, the saved value will be the last value of the array
            // if it is even and there are more than 1 element in `currentLevelNewNodes`, the saved value
            // will be the value before the last one.
            // If it is even and there is only one element, there is no need to save anything because
            // the correct value for this level was already saved before.
            if (currentLevelSize & 1 == 1) {
                // array
                //@TODO (Claude wrote this): inline branching — insertMany can grow the tree by multiple levels, so for level >= oldTreeDepth we need push, for level < oldTreeDepth we direct-write. Could cache oldTreeDepth before the while-loop that bumps treeDepth and branch off that, instead of paying the helper's length read every iteration.
                // Est. savings: ~100-200 gas per level iteration. Multiplied by treeDepth (loop runs `treeDepth` times, hitting this branch ~half the iterations on average), expect ~1-3k gas total per _insertMany call for a depth-20 tree.
                //_updateSideNode(self, currentLevelNewNodes[currentLevelNewNodes.length - 1], level);

                self.sideNodes[level] = currentLevelNewNodes[currentLevelNewNodes.length - 1];
            } else if (currentLevelNewNodes.length > 1) {
                //array
                //@TODO (Claude wrote this): same as above — branch on cached oldTreeDepth: push when level >= oldTreeDepth, direct-write otherwise.
                // Est. savings: ~100-200 gas per hit. This branch fires less often than the odd-size one (only on even currentLevelSize with >1 element), so total impact is smaller — typically a few hundred gas per _insertMany.
                //_updateSideNode(self, currentLevelNewNodes[currentLevelNewNodes.length - 2], level);

                // mapping
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
        // mapping
        self.size = treeSize + leaves.length;

        // Update tree root
        // array
        //@TODO (Claude wrote this): inline branching — push when treeDepth == sideNodes.length (root slot doesn't exist yet because the tree grew), direct-write otherwise. Same shape as the _insert root write above.
        // Est. savings: ~100-200 gas per _insertMany call. Negligible relative to the per-level Poseidon hashes (~1-2k gas each), but free if you're already inlining the loop sites above.
        //_updateSideNode(self, currentLevelNewNodes[0], treeDepth);

        // mapping
        self.sideNodes[treeDepth] = currentLevelNewNodes[0];

        return currentLevelNewNodes[0];
    }

    /// @dev Updates the value of an existing leaf and recalculates hashes
    /// to maintain tree integrity.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param oldLeaf: The value of the leaf that is to be updated.
    /// @param newLeaf: The new value that will replace the oldLeaf in the tree.
    /// @param siblingNodes: An array of sibling nodes that are necessary to recalculate the path to the root.
    /// @return The new hash of the updated node after the leaf has been updated.
    /// @notice Requires collision-resistant hashing: `if (self.sideNodes[level] == oldRoot)` identifies
    /// which sideNode to refresh by hash equality, so a collision between two distinct subtree roots would corrupt tree state silently.
    function _update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) internal returns (uint256) {
        if (newLeaf >= SNARK_SCALAR_FIELD) {
            revert LeafGreaterThanSnarkScalarField();
        } else if (!_has(self, oldLeaf, index)) {
            revert LeafDoesNotExist();
        }
        // @TODO we can remove _has here? It's cheap early check, but the siblingNodes is being used to merkle inclusion proof the oldLeaf any way below

        uint256 node = newLeaf;
        uint256 oldRoot = oldLeaf;

        // array
        // uint256 lastIndex = self.leaves.length - 1;

        uint256 lastIndex = self.size - 1;

        uint256 i = 0;

        // Cache tree depth to optimize gas
        // array
        // uint256 treeDepth = _treeDepth(self);

        // mapping
        uint256 treeDepth = self.depth;

        for (uint256 level = 0; level < treeDepth; ) {
            if ((index >> level) & 1 == 1) {
                if (siblingNodes[i] >= SNARK_SCALAR_FIELD) {
                    revert LeafGreaterThanSnarkScalarField();
                }

                node = PoseidonT3.hash([siblingNodes[i], node]);
                oldRoot = PoseidonT3.hash([siblingNodes[i], oldRoot]);

                unchecked {
                    ++i;
                }
            } else {
                if (index >> level != lastIndex >> level) {
                    if (siblingNodes[i] >= SNARK_SCALAR_FIELD) {
                        revert LeafGreaterThanSnarkScalarField();
                    }

                    if (self.sideNodes[level] == oldRoot) {
                        self.sideNodes[level] = node;
                    }

                    node = PoseidonT3.hash([node, siblingNodes[i]]);
                    oldRoot = PoseidonT3.hash([oldRoot, siblingNodes[i]]);

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

        self.leaves[index] = newLeaf;

        return node;
    }

    /// @dev Checks if a leaf exists in the tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the leaf to check for existence.
    /// @return A boolean value indicating whether the leaf exists in the tree.
    function _has(SkinnyIMTData storage self, uint256 leaf, uint256 index) internal view returns (bool) {
        // array
        // if (index >= self.leaves.length) {
        // mapping
        if (index >= self.size) {
            return false;
        } else {
            return self.leaves[index] == leaf;
        }
    }

    // @TODO this instead of _has so we can remove the leaves
    function _rootFromSiblings(
        SkinnyIMTData storage self,
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) internal view returns (uint256) {}

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function _root(SkinnyIMTData storage self) internal view returns (uint256) {
        // array
        // @TODO old leanIMT returned 0 on empty tree. Or should we just error?
        // if (self.leaves.length == 0) {
        //     return 0;
        // } else {
        //     return self.sideNodes[_treeDepth(self)];
        // }

        return self.sideNodes[self.depth];
    }
}
