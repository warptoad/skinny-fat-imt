// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMT, SkinnyIMTData} from "./InternalSkinnyIMT.sol";
import {SNARK_SCALAR_FIELD} from "./Constants.sol";
import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

error LeafGreaterThanSnarkScalarField();

event NewLeaf(uint256 indexed treeId, uint256 startIndex, uint256 leaves);
event UpdatedLeaf(uint256 indexed treeId, uint256 indexed index, uint256 indexed leaf);
event NewTree(uint256 indexed treeId);

library SkinnyIMT {
    // The function used for hashing. Passed as a function parameter in functions from InternalLazyIMT
    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return PoseidonT3.hash(input);
    }

    using InternalSkinnyIMT for *;

    /// @dev Initializes the tree by assigning it a non-zero `treeId` derived from its storage slot.
    /// Reverts if the tree has already been initialized.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The newly assigned tree id.
    function init(SkinnyIMTData storage self) public returns (uint256) {
        return InternalSkinnyIMT._init(self);
    }

    /// @dev Inserts a new leaf into the incremental merkle tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the new leaf to be inserted into the tree.
    /// @return The new hash of the node after the leaf has been inserted.
    /// @notice Checks that the leaf are within the snark scalar field
    function insert(SkinnyIMTData storage self, uint256 leaf) public returns (uint256) {
        if (leaf >= SNARK_SCALAR_FIELD) {
            revert LeafGreaterThanSnarkScalarField();
        }

        return InternalSkinnyIMT._insert(self, leaf, hasher);
    }

    /// @dev Inserts many leaves into the incremental merkle tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaves: The values of the new leaves to be inserted into the tree.
    /// @return The root after the leaves have been inserted.
    /// @notice Checks that the leafs are within the snark scalar field
    function insertMany(SkinnyIMTData storage self, uint256[] calldata leaves) public returns (uint256) {
        uint256 treeSize = self.size;

        uint256 treeId = self.treeId;
        for (uint256 i = 0; i < leaves.length; ) {
            uint256 leaf = leaves[i];
            if (leaf >= SNARK_SCALAR_FIELD) {
                revert LeafGreaterThanSnarkScalarField();
            }
            emit NewLeaf(treeId, treeSize + i, leaf);

            unchecked {
                ++i;
            }
        }
        return InternalSkinnyIMT._insertMany(self, leaves, hasher);
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
    /// @notice Checks that the leaf and siblingNodes are within the snark scalar field
    function update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) public returns (uint256) {
        if (newLeaf >= SNARK_SCALAR_FIELD) {
            revert LeafGreaterThanSnarkScalarField();
        }
        // @todo what actually breaks if that is not checked? Maybe not checking siblingNodes is fine?
        for (uint256 i = 0; i < siblingNodes.length; i++) {
            if (siblingNodes[i] >= SNARK_SCALAR_FIELD) {
                revert LeafGreaterThanSnarkScalarField();
            }
        }
        return InternalSkinnyIMT._update(self, oldLeaf, newLeaf, index, siblingNodes, hasher);
    }

    /// @dev Checks if a leaf exists in the tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the leaf to check for existence.
    /// @param index: The index of the leaf in the tree.
    /// @param siblingNodes: An array of sibling nodes used to recompute the root for the given leaf.
    /// @return A boolean value indicating whether the leaf exists in the tree.
    /// @notice Checks that the leaf and siblingNodes are within the snark scalar field
    function has(
        SkinnyIMTData storage self,
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) public view returns (bool) {
        if (leaf >= SNARK_SCALAR_FIELD) {
            revert LeafGreaterThanSnarkScalarField();
        }
        for (uint256 i = 0; i < siblingNodes.length; i++) {
            if (siblingNodes[i] >= SNARK_SCALAR_FIELD) {
                revert LeafGreaterThanSnarkScalarField();
            }
        }
        return InternalSkinnyIMT._has(self, leaf, index, siblingNodes, hasher);
    }

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMT._root(self);
    }
}
