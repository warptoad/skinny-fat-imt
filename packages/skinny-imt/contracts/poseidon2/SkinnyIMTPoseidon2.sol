// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMT, SkinnyIMTData, MultiProof, TreeEmpty} from "../InternalSkinnyIMT.sol";
// import {IPoseidon2} from "poseidon2-evm/src/IPoseidon2.sol";
import {LibPoseidon2Yul} from "poseidon2-evm/src/bn254/yul/LibPoseidon2Yul.sol";
import {NewTree, NewLeaf, RepeatedLeafs, UpdatedLeaf} from "../interfaces/events.sol";

library SkinnyIMTPoseidon2 {
    // @TODO ask zemse if the wants to make Poseidon2Yul_BN254 an library with public functions, would add 50~150 gas
    // Hardcoded since poseidon2 is deployed as a contract instead of a library
    // This is because author used a gas saving trick with .fallback
    // address internal constant HASHER_ADDRESS = 0xB2542195Ad96AcfBC962C48A97D7640A9F5386D2;
    // The function used for hashing. Passed as a function parameter in functions from InternalLazyIMT.
    // function hasher(uint256[2] memory leaves) internal pure returns (uint256) {
    //     return IPoseidon2(HASHER_ADDRESS).hash_2(leaves[0], leaves[1]);
    // }

    // The function used for hashing. Passed as a function parameter in functions from InternalLazyIMT.
    function hasher(uint256[2] memory leaves) internal pure returns (uint256) {
        return LibPoseidon2Yul.hash_2(leaves[0], leaves[1]);
    }

    using InternalSkinnyIMT for *;

    /// @dev Initializes the tree by assigning it a non-zero `treeId` derived from its storage slot.
    /// Reverts if the tree has already been initialized.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The newly assigned tree id.
    function init(SkinnyIMTData storage self) public returns (uint256) {
        uint256 treeId = InternalSkinnyIMT._init(self);
        emit NewTree(treeId);
        return treeId;
    }

    /// @dev Inserts a new leaf into the incremental merkle tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the new leaf to be inserted into the tree.
    /// @return root, index
    /// @notice Checks that the leaf are within the snark scalar field
    function insert(SkinnyIMTData storage self, uint256 leaf) public returns (uint256, uint256) {
        InternalSkinnyIMT._requireInField(leaf);

        // update tree
        (uint256 _root, uint256 _index) = InternalSkinnyIMT._insert(self, leaf, hasher);

        // emit event
        emit NewLeaf(self.treeId, _index, leaf);

        return (_root, _index);
    }

    /// @dev Inserts many leaves into the incremental merkle tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaves: The values of the new leaves to be inserted into the tree.
    /// @return _root The root after the leaves have been inserted.
    /// @return _startIndex The index of the first inserted leaf (inclusive).
    /// @return _nextIndex The index for the next insert after this call (exclusive).
    /// @notice Checks that the leafs are within the snark scalar field
    function insertMany(
        SkinnyIMTData storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        uint256 _startIndex = self.size;
        uint256 _nextIndex = _startIndex + leaves.length;

        // emit events, checks
        uint256 treeId = self.treeId;
        for (uint256 i = 0; i < leaves.length; ) {
            uint256 leaf = leaves[i];
            InternalSkinnyIMT._requireInField(leaf);
            emit NewLeaf(treeId, _startIndex + i, leaf);
            unchecked {
                ++i;
            }
        }

        // update tree
        uint256 _root = InternalSkinnyIMT._insertMany(self, leaves, hasher);

        return (_root, _startIndex, _nextIndex);
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
    /// @return _startIndex The index of the first inserted leaf (inclusive).
    /// @return _nextIndex The index for the next insert after this call (exclusive).
    function insertManyRepeated(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        // check
        InternalSkinnyIMT._requireInField(value);
        (uint256 _root, uint256 _startIndex, ) = InternalSkinnyIMT._insertManyRepeated(self, value, amount, hasher);
        uint256 _nextIndex = _startIndex + amount;
        emit RepeatedLeafs(self.treeId, _startIndex, _nextIndex, value);
        return (_root, _startIndex, _nextIndex);
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
    /// @param proofSiblings: An array of sibling nodes that are necessary to recalculate the path to the root.
    /// @return The new hash of the updated node after the leaf has been updated.
    /// @notice Requires collision-resistant hashing: `if (self.sideNodes[level] == oldRoot)` identifies
    /// which sideNode to refresh by hash equality, so a collision between two distinct subtree roots would corrupt tree state silently.
    /// @notice Checks that the leaf and siblingNodes are within the snark scalar field
    function update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 index,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        // check
        InternalSkinnyIMT._requireInField(newLeaf);
        // @todo what actually breaks if that is not checked? Maybe not checking siblingNodes is fine?
        for (uint256 i = 0; i < proofSiblings.length; i++) {
            InternalSkinnyIMT._requireInField(proofSiblings[i]);
        }

        // update tree
        uint256 _root = InternalSkinnyIMT._update(self, oldLeaf, newLeaf, index, proofSiblings, hasher);

        // emit event
        emit UpdatedLeaf(self.treeId, index, newLeaf, oldLeaf);

        return _root;
    }

    function proofToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        InternalSkinnyIMT._requireInField(leaf);
        for (uint256 i = 0; i < proofSiblings.length; i++) {
            InternalSkinnyIMT._requireInField(proofSiblings[i]);
        }
        return InternalSkinnyIMT._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

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
        uint256 _currentRoot = InternalSkinnyIMT._root(self);
        uint256 _provenRoot = InternalSkinnyIMT._proofToRoot(self.depth, self.size, leaf, index, siblingNodes, hasher);
        return _currentRoot == _provenRoot;
    }

    function proofManyToRoot(
        uint256 treeDepth,
        uint256 edgeIndex,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        for (uint256 i = 0; i < leaves.length; i++) {
            InternalSkinnyIMT._requireInField(leaves[i]);
        }
        for (uint256 i = 0; i < proofSiblings.length; i++) {
            InternalSkinnyIMT._requireInField(proofSiblings[i]);
        }
        return
            InternalSkinnyIMT._proofManyToRoot(
                MultiProof(treeDepth, edgeIndex, leaves, leafIndexes, proofSiblings),
                hasher
            );
    }

    function verifyMany(
        SkinnyIMTData storage self,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (bool) {
        for (uint256 i = 0; i < leaves.length; i++) {
            InternalSkinnyIMT._requireInField(leaves[i]);
        }
        for (uint256 i = 0; i < proofSiblings.length; i++) {
            InternalSkinnyIMT._requireInField(proofSiblings[i]);
        }
        if (self.size == 0) {
            revert TreeEmpty();
        }
        uint256 computedRoot = InternalSkinnyIMT._proofManyToRoot(
            MultiProof(self.depth, self.size - 1, leaves, leafIndexes, proofSiblings),
            hasher
        );
        return computedRoot == InternalSkinnyIMT._root(self);
    }

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMT._root(self);
    }
}
