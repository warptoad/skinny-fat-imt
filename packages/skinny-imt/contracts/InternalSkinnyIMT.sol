// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

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
    function _insert(SkinnyIMTData storage self, uint256 leaf) internal returns (uint256) {
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
                node = PoseidonT3.hash([self.sideNodes[level], node]);
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
    function _insertMany(SkinnyIMTData storage self, uint256[] calldata leaves) internal returns (uint256) {
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
                    hasherInput[0] = self.sideNodes[level];
                } else {
                    hasherInput[0] = currentLevelNewNodes[(i + nextLevelStartIndex) * 2 - currentLevelStartIndex];
                }

                uint256 parentNode;

                // Existence of a right child by checking index
                // zero is a valid leaf now, so `rightChild == 0` can't be used as a proxy.
                // If a right child exists: assign it and hash(left, right). Otherwise: parent = left.
                if ((i + nextLevelStartIndex) * 2 + 1 < currentLevelSize) {
                    hasherInput[1] = currentLevelNewNodes[(i + nextLevelStartIndex) * 2 + 1 - currentLevelStartIndex];
                    parentNode = PoseidonT3.hash(hasherInput);
                } else {
                    // leave to dangle:
                    // node is used in next iter, becomes it's own parent.
                    // Stored in sideNodes, for when it will have an right sibling eventually
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
        uint256[] calldata siblingNodes
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
                node = PoseidonT3.hash([siblingNodes[i], node]);
                oldRoot = PoseidonT3.hash([siblingNodes[i], oldRoot]);

                unchecked {
                    ++i;
                }
            } else {
                if (index >> level != lastIndex >> level) {
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

        //self.leaves[index] = newLeaf;

        return node;
    }

    /// @dev Checks if a leaf exists in the tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the leaf to check for existence.
    /// @param index: The index of the leaf in the tree.
    /// @param siblingNodes: An array of sibling nodes used to recompute the root for the given leaf.
    /// @return A boolean value indicating whether the leaf exists in the tree.
    /// @notice Contracts using this function with snark based hash functions,
    /// need to check that the leaf and siblingNodes are within the snark scalar field.
    function _has(
        SkinnyIMTData storage self,
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) internal view returns (bool) {
        uint256 rootSiblings = _rootFromSiblings(leaf, index, siblingNodes);
        return rootSiblings == _root(self);
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
        uint256[] calldata siblingNodes
    ) internal pure returns (uint256) {
        uint256 oldRoot = leaf;

        uint256 i = 0;

        uint256 proofDepth = siblingNodes.length;

        for (uint256 level = 0; level < proofDepth; ) {
            if ((index >> level) & 1 == 1) {
                oldRoot = PoseidonT3.hash([siblingNodes[i], oldRoot]);

                unchecked {
                    ++i;
                }
            } else {
                oldRoot = PoseidonT3.hash([oldRoot, siblingNodes[i]]);

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

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function _root(SkinnyIMTData storage self) internal view returns (uint256) {
        return self.sideNodes[self.depth];
    }
}
