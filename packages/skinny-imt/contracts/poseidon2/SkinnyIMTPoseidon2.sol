// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMT, SkinnyIMTData} from "../InternalSkinnyIMT.sol";
import {IPoseidon2} from "poseidon2-evm/src/IPoseidon2.sol";

event NewLeaf(uint256 indexed treeId, uint256 startIndex, uint256 leaves);
event UpdatedLeaf(uint256 indexed treeId, uint256 indexed index, uint256 indexed leaf);
event RepeatedLeafs(uint256 indexed startIndex, uint256 indexed endIndex, uint256 indexed leaf);
event NewTree(uint256 indexed treeId);

library SkinnyIMTPoseidon2 {
    // create2 address of our patched Poseidon2YulFixed (see contracts/poseidon2/Poseidon2YulFixed.sol).
    // The upstream zemse Poseidon2Yul overflows 2**256 on some inputs and returns wrong hashes;
    // this address points at the reduction-corrected copy. Deployed deterministically by
    // deploy-imt-poseidon2-test.ts via the poseidon-solidity create2 proxy.
    address internal constant HASHER_ADDRESS = 0xB2542195Ad96AcfBC962C48A97D7640A9F5386D2;
    // The function used for hashing. Passed as a function parameter in functions from InternalLazyIMT.
    function hasher(uint256[2] memory leaves) internal pure returns (uint256) {
        return IPoseidon2(HASHER_ADDRESS).hash_2(leaves[0], leaves[1]);
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
        InternalSkinnyIMT._requireInField(leaf);
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
            InternalSkinnyIMT._requireInField(leaf);
            emit NewLeaf(treeId, treeSize + i, leaf);

            unchecked {
                ++i;
            }
        }
        return InternalSkinnyIMT._insertMany(self, leaves, hasher);
    }

    /// @notice Appends `amount` copies of `value` to the tree.
    /// @dev O(log(size + amount)) hashes — see `InternalSkinnyIMT._insertManyRepeated`.
    /// Calldata is O(1) (just `value` and `amount`). Subsequent calls with the same
    /// `value` are cheaper because the per-level repeated-subtree cache persists
    /// in storage; use `precomputeRepeatedCache` to warm the cache ahead of time.
    /// No per-leaf events are emitted; callers reconstruct ranges off-chain from
    /// `(size, depth)` and the constant `value`.
    /// Reverts if `value` is not within the snark scalar field.
    /// @param self A storage reference to the `SkinnyIMTData` struct.
    /// @param value The leaf value to insert `amount` copies of.
    /// @param amount The number of leaves to append.
    /// @return _root The new root after the leaves have been appended.
    /// @return _startIndex The index of the first inserted leaf.
    /// @return _endIndex The index of the last inserted leaf.
    function insertManyRepeated(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256 _root, uint256 _startIndex, uint256 _endIndex) {
        InternalSkinnyIMT._requireInField(value);
        (_root, _startIndex, _endIndex) = InternalSkinnyIMT._insertManyRepeated(self, value, amount, hasher);
        emit RepeatedLeafs(_startIndex, _endIndex, value);
        return (_root, _startIndex, _endIndex);
    }

    /// @dev Convenience wrapper for the common `value == 0` case.
    /// @notice No scalar-field check: zero is always in-field.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param amount: The number of zero leaves to append.
    /// @return _root The new root after the leaves have been appended.
    /// @return _startIndex The index of the first inserted leaf.
    /// @return _endIndex The index of the last inserted leaf.
    function insertManyZeros(
        SkinnyIMTData storage self,
        uint256 amount
    ) public returns (uint256 _root, uint256 _startIndex, uint256 _endIndex) {
        (_root, _startIndex, _endIndex) = InternalSkinnyIMT._insertManyRepeated(self, 0, amount, hasher);
        emit RepeatedLeafs(_startIndex, _endIndex, 0);
        return (_root, _startIndex, _endIndex);
    }

    /// @dev Pre-populates the repeated-subtree cache for `value` up to `upToLevel`.
    /// Once cached, future `insertManyRepeated(value, ...)` calls skip those hashes
    /// and pay only one SLOAD per level instead.
    /// @notice Checks that `value` is within the snark scalar field.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param value: The leaf value whose repeated-subtree chain to precompute.
    /// @param upToLevel: The highest level (inclusive) to populate the cache for.
    function precomputeRepeatedCache(SkinnyIMTData storage self, uint256 value, uint256 upToLevel) public {
        InternalSkinnyIMT._requireInField(value);
        InternalSkinnyIMT._precomputeRepeatedCache(self, value, upToLevel, hasher);
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
        InternalSkinnyIMT._requireInField(newLeaf);
        // @todo what actually breaks if that is not checked? Maybe not checking siblingNodes is fine?
        for (uint256 i = 0; i < siblingNodes.length; i++) {
            InternalSkinnyIMT._requireInField(siblingNodes[i]);
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
    function verify(
        SkinnyIMTData storage self,
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) public view returns (bool) {
        InternalSkinnyIMT._requireInField(leaf);
        for (uint256 i = 0; i < siblingNodes.length; i++) {
            InternalSkinnyIMT._requireInField(siblingNodes[i]);
        }
        return InternalSkinnyIMT._verify(self, leaf, index, siblingNodes, hasher);
    }

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMT._root(self);
    }
}
