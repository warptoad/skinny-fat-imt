// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMT, SkinnyIMTFullNodeData} from "../InternalSkinnyIMT.sol";
// import {IPoseidon2} from "poseidon2-evm/src/IPoseidon2.sol";
import {LibPoseidon2Yul} from "poseidon2-evm/src/bn254/yul/LibPoseidon2Yul.sol";
import {NewTree, NewLeaf, UpdatedLeaf} from "../interfaces/events.sol";

/// @title SkinnyIMTFullNodePoseidon2
/// @author Jim Jim Valkema
/// @notice stores all leafs on-chain so full nodes can retrieve them even after events are pruned (older than 1 year)
library SkinnyIMTFullNodePoseidon2 {
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
    function init(SkinnyIMTFullNodeData storage self) public returns (uint256) {
        uint256 treeId = InternalSkinnyIMT._init(self.skinnyData);
        emit NewTree(treeId);
        return treeId;
    }

    /// @dev Inserts a new leaf into the incremental merkle tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the new leaf to be inserted into the tree.
    /// @return root, index
    /// @notice Checks that the leaf are within the snark scalar field
    function insert(SkinnyIMTFullNodeData storage self, uint256 leaf) public returns (uint256, uint256) {
        InternalSkinnyIMT._requireInField(leaf);

        // update tree
        (uint256 _root, uint256 _index) = InternalSkinnyIMT._insert(self.skinnyData, leaf, hasher);

        // emit event, store leaf
        emit NewLeaf(self.skinnyData.treeId, _index, leaf);
        self.leaves.push(leaf);

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
        SkinnyIMTFullNodeData storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        uint256 _startIndex = self.skinnyData.size;
        uint256 _nextIndex = _startIndex + leaves.length;

        // emit events, store leafs, checks
        uint256 treeId = self.skinnyData.treeId;
        for (uint256 i = 0; i < leaves.length; ) {
            uint256 leaf = leaves[i];
            InternalSkinnyIMT._requireInField(leaf);
            emit NewLeaf(treeId, _startIndex + i, leaf);

            self.leaves.push(leaf);
            unchecked {
                ++i;
            }
        }

        // update tree
        uint256 _root = InternalSkinnyIMT._insertMany(self.skinnyData, leaves, hasher);

        return (_root, _startIndex, _nextIndex);
    }

    /// @notice Appends `amount` copies of `value` to the tree.
    /// @notice FullNode version stores all leafs, so a `NewLeaf` is emitted per leaf
    /// instead of a single `RepeatedLeafs`.
    /// @dev Tree hashing is O(log(size + amount)) (see `InternalSkinnyIMT._insertManyRepeated`),
    /// but storing + emitting every leaf makes this O(amount) overall — not cheap for large `amount`.
    /// Subsequent calls with the same `value` hash cheaper via the per-level cache;
    /// use `precomputeRepeatedCache` to warm it.
    /// Reverts if `value` is not within the snark scalar field.
    /// @param self A storage reference to the `SkinnyIMTData` struct.
    /// @param leaf The leaf value to insert `amount` copies of.
    /// @param amount The number of leaves to append.
    /// @return _root The new root after the leaves have been appended.
    /// @return _startIndex The index of the first inserted leaf (inclusive).
    /// @return _nextIndex The index for the next insert after this call (exclusive).
    function insertManyRepeated(
        SkinnyIMTFullNodeData storage self,
        uint256 leaf,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        // check
        InternalSkinnyIMT._requireInField(leaf);

        // update tree
        (uint256 _root, uint256 _startIndex, ) = InternalSkinnyIMT._insertManyRepeated(
            self.skinnyData,
            leaf,
            amount,
            hasher
        );
        uint256 _nextIndex = _startIndex + amount;
        // add leafs, emit event
        uint256 _treeId = self.skinnyData.treeId;
        for (uint256 _index = _startIndex; _index < _nextIndex; ) {
            emit NewLeaf(_treeId, _index, leaf);
            self.leaves.push(leaf);
            unchecked {
                ++_index;
            }
        }

        return (_root, _startIndex, _nextIndex);
    }

    /// @dev Convenience wrapper for the common `value == 0` case.
    /// @notice No scalar-field check: zero is always in-field.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param amount: The number of zero leaves to append.
    /// @return _root The new root after the leaves have been appended.
    /// @return _startIndex The index of the first inserted leaf (inclusive).
    /// @return _nextIndex The index for the next insert after this call (exclusive).
    function insertManyZeros(
        SkinnyIMTFullNodeData storage self,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        // update tree
        (uint256 _root, uint256 _startIndex, ) = InternalSkinnyIMT._insertManyRepeated(
            self.skinnyData,
            0,
            amount,
            hasher
        );
        uint256 _nextIndex = _startIndex + amount;

        // add leafs, emit event
        uint256 _treeId = self.skinnyData.treeId;
        for (uint256 _index = _startIndex; _index < _nextIndex; ) {
            emit NewLeaf(_treeId, _index, 0);
            self.leaves.push(0);
            unchecked {
                ++_index;
            }
        }

        return (_root, _startIndex, _nextIndex);
    }

    /// @dev Pre-populates the repeated-subtree cache for `value` up to `upToLevel`.
    /// Once cached, future `insertManyRepeated(value, ...)` calls skip those hashes
    /// and pay only one SLOAD per level instead.
    /// @notice Checks that `value` is within the snark scalar field.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param value: The leaf value whose repeated-subtree chain to precompute.
    /// @param upToLevel: The highest level (inclusive) to populate the cache for.
    function precomputeRepeatedCache(SkinnyIMTFullNodeData storage self, uint256 value, uint256 upToLevel) public {
        InternalSkinnyIMT._requireInField(value);
        InternalSkinnyIMT._precomputeRepeatedCache(self.skinnyData, value, upToLevel, hasher);
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
        SkinnyIMTFullNodeData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) public returns (uint256) {
        // check
        InternalSkinnyIMT._requireInField(newLeaf);
        // @todo what actually breaks if that is not checked? Maybe not checking siblingNodes is fine?
        for (uint256 i = 0; i < siblingNodes.length; i++) {
            InternalSkinnyIMT._requireInField(siblingNodes[i]);
        }

        // update tree
        uint256 _root = InternalSkinnyIMT._update(self.skinnyData, oldLeaf, newLeaf, index, siblingNodes, hasher);

        // emit event store new leaf
        emit UpdatedLeaf(self.skinnyData.treeId, index, newLeaf, oldLeaf);
        self.leaves[index] = newLeaf;

        return _root;
    }

    /// @dev Checks if a leaf exists in the tree.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @param leaf: The value of the leaf to check for existence.
    /// @param index: The index of the leaf in the tree.
    /// @param siblingNodes: An array of sibling nodes used to recompute the root for the given leaf.
    /// @return A boolean value indicating whether the leaf exists in the tree.
    /// @notice Checks that the leaf and siblingNodes are within the snark scalar field
    function verify(
        SkinnyIMTFullNodeData storage self,
        uint256 leaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) public view returns (bool) {
        InternalSkinnyIMT._requireInField(leaf);
        for (uint256 i = 0; i < siblingNodes.length; i++) {
            InternalSkinnyIMT._requireInField(siblingNodes[i]);
        }
        uint256 _currentRoot = InternalSkinnyIMT._root(self.skinnyData);
        uint256 _provenRoot = InternalSkinnyIMT._proofToRoot(leaf, index, siblingNodes, hasher);
        return _currentRoot == _provenRoot;
    }

    /// @dev Retrieves the root of the tree from the 'sideNodes' mapping using the
    /// current tree depth.
    /// @param self: A storage reference to the 'SkinnyIMTData' struct.
    /// @return The root hash of the tree.
    function root(SkinnyIMTFullNodeData storage self) public view returns (uint256) {
        return InternalSkinnyIMT._root(self.skinnyData);
    }
}
