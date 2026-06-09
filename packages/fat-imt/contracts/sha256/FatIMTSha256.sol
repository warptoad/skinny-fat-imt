// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalFatIMT, FatIMTData} from "../InternalFatIMT.sol";

event NewLeaf(uint256 indexed treeId, uint256 startIndex, uint256 leaves);
event UpdatedLeaf(uint256 indexed treeId, uint256 indexed index, uint256 indexed leaf);
// unused since insertManyRepeated does not scale well anymore, so emittin an event for every leaf isn't that
// horrible for scaling anymore
//event RepeatedLeafs(uint256 indexed startIndex, uint256 indexed endIndex, uint256 indexed leaf);
event NewTree(uint256 indexed treeId);

library FatIMTSha256 {
    // sha256 is a built-in precompile (address 0x02); no external deployment needed.
    function hasher(uint256[2] memory leaves) internal pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(leaves[0], leaves[1])));
    }

    using InternalFatIMT for *;

    /// @dev Initializes the tree by assigning it a non-zero `treeId` derived from its storage slot.
    /// Reverts if the tree has already been initialized.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @return The newly assigned tree id.
    function init(FatIMTData storage self) public returns (uint256) {
        return InternalFatIMT._init(self);
    }

    /// @dev Inserts a new leaf into the incremental merkle tree.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param leaf: The value of the new leaf to be inserted into the tree.
    /// @return The new hash of the node after the leaf has been inserted.
    function insert(FatIMTData storage self, uint256 leaf) public returns (uint256) {
        return InternalFatIMT._insert(self, leaf, hasher);
    }

    /// @dev Inserts many leaves into the incremental merkle tree.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param leaves: The values of the new leaves to be inserted into the tree.
    /// @return The root after the leaves have been inserted.
    function insertMany(FatIMTData storage self, uint256[] calldata leaves) public returns (uint256) {
        uint256 treeSize = self.size;

        uint256 treeId = self.treeId;
        for (uint256 i = 0; i < leaves.length; ) {
            emit NewLeaf(treeId, treeSize + i, leaves[i]);

            unchecked {
                ++i;
            }
        }
        return InternalFatIMT._insertMany(self, leaves, hasher);
    }

    /// @notice Appends `amount` copies of `value` to the tree.
    /// @dev O(log(size + amount)) hashes — see `InternalFatIMT._insertManyRepeated`.
    /// Calldata is O(1) (just `value` and `amount`). Subsequent calls with the same
    /// `value` are cheaper because the per-level repeated-subtree cache persists
    /// in storage; use `precomputeRepeatedCache` to warm the cache ahead of time.
    /// No per-leaf events are emitted; callers reconstruct ranges off-chain from
    /// `(size, depth)` and the constant `value`.
    /// Reverts if `value` is not within the snark scalar field.
    /// @param self A storage reference to the `FatIMTData` struct.
    /// @param leaf The leaf value to insert `amount` copies of.
    /// @param amount The number of leaves to append.
    /// @return _root The new root after the leaves have been appended.
    /// @return _startIndex The index of the first inserted leaf.
    /// @return _endIndex The index of the last inserted leaf.
    function insertManyRepeated(
        FatIMTData storage self,
        uint256 leaf,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        uint256 treeId = self.treeId;
        uint256 treeSize = self.size;
        for (uint256 i = 0; i < amount; ) {
            emit NewLeaf(treeId, treeSize + i, leaf);
            unchecked {
                ++i;
            }
        }
        return InternalFatIMT._insertManyRepeated(self, leaf, amount, hasher);
    }

    /// @dev Convenience wrapper for the common `value == 0` case.
    /// @notice No scalar-field check: zero is always in-field.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param amount: The number of zero leaves to append.
    /// @return _root The new root after the leaves have been appended.
    /// @return _startIndex The index of the first inserted leaf.
    /// @return _endIndex The index of the last inserted leaf.
    function insertManyZeros(FatIMTData storage self, uint256 amount) public returns (uint256, uint256, uint256) {
        uint256 treeId = self.treeId;
        uint256 treeSize = self.size;
        for (uint256 i = 0; i < amount; ) {
            emit NewLeaf(treeId, treeSize + i, 0);
            unchecked {
                ++i;
            }
        }
        return InternalFatIMT._insertManyRepeated(self, 0, amount, hasher);
    }

    /// @dev Pre-populates the repeated-subtree cache for `value` up to `upToLevel`.
    /// Once cached, future `insertManyRepeated(value, ...)` calls skip those hashes
    /// and pay only one SLOAD per level instead.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param value: The leaf value whose repeated-subtree chain to precompute.
    /// @param upToLevel: The highest level (inclusive) to populate the cache for.
    function precomputeRepeatedCache(FatIMTData storage self, uint256 value, uint256 upToLevel) public {
        InternalFatIMT._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    /// @dev Updates the value of an existing leaf and recalculates hashes
    /// to maintain tree integrity. Sibling nodes are read directly from the
    /// stored tree, so no merkle proof needs to be supplied.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param newLeaf: The new value that will replace the leaf at `index`.
    /// @param index: The index of the leaf to be updated.
    /// @return The new hash of the updated node after the leaf has been updated.
    function update(FatIMTData storage self, uint256 newLeaf, uint256 index) public returns (uint256) {
        return InternalFatIMT._update(self, newLeaf, index, hasher);
    }

    /// @dev Checks if a leaf exists in the tree.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param leaf: The value of the leaf to check for existence.
    /// @param index: The index of the leaf in the tree.
    /// @param siblingNodes: An array of sibling nodes used to recompute the root for the given leaf.
    /// @return A boolean value indicating whether the leaf exists in the tree.
    function verify(
        FatIMTData storage self,
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) public view returns (bool) {
        return InternalFatIMT._verify(self, leaf, index, siblingNodes, hasher);
    }

    /// @dev Retrieves the root of the tree from the node storage using the
    /// current tree depth.
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @return The root hash of the tree.
    function root(FatIMTData storage self) public view returns (uint256) {
        return InternalFatIMT._root(self);
    }
}
