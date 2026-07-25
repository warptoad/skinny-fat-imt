// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTCore, SkinnyIMTData, MultiProof, TreeEmpty} from "./InternalSkinnyIMTCore.sol";
import {NewTree, TreeReset, NewRoot, NewLeaf, RepeatedLeafs, UpdatedLeaf} from "./interfaces/events.sol";
import {_emitUpdatedMany, _requireInField, _requireAllInField} from "./SkinnyIMTUtils.sol";

error NotInitialized();
error AlreadyInitialized();

library InternalSkinnyIMTEvent {
    function _reset(SkinnyIMTData storage self) internal {
        emit TreeReset(self.treeId);
        InternalSkinnyIMTCore._reset(self);
    }

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
        emit NewTree(id);
        return id;
    }

    function _insert(
        SkinnyIMTData storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        // update tree
        (uint256 newRoot, uint256 index) = InternalSkinnyIMTCore._insert(self, leaf, hasher);
        // emit event
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit NewLeaf(treeId, index, leaf);
        emit NewRoot(treeId, newRoot, self.size);
        return (newRoot, index);
    }

    function _insertBN254(
        SkinnyIMTData storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        // field check
        _requireInField(leaf);
        // update tree
        (uint256 newRoot, uint256 index) = InternalSkinnyIMTCore._insert(self, leaf, hasher);
        // emit event
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit NewLeaf(treeId, index, leaf);
        emit NewRoot(treeId, newRoot, self.size);
        return (newRoot, index);
    }

    function _insertMany(
        SkinnyIMTData storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // update tree
        (uint256 newRoot, uint256 startIndex, uint256 nextIndex) = InternalSkinnyIMTCore._insertMany(
            self,
            leaves,
            hasher
        );

        // emit events
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        for (uint256 i = 0; i < leaves.length; ) {
            uint256 leaf = leaves[i];
            emit NewLeaf(treeId, startIndex + i, leaf);
            unchecked {
                ++i;
            }
        }
        emit NewRoot(treeId, newRoot, nextIndex);
        return (newRoot, startIndex, nextIndex);
    }

    function _insertManyBN254(
        SkinnyIMTData storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // update tree
        (uint256 newRoot, uint256 startIndex, uint256 nextIndex) = InternalSkinnyIMTCore._insertMany(
            self,
            leaves,
            hasher
        );

        // emit events
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        for (uint256 i = 0; i < leaves.length; ) {
            uint256 leaf = leaves[i];
            _requireInField(leaf);
            emit NewLeaf(treeId, startIndex + i, leaf);
            unchecked {
                ++i;
            }
        }
        emit NewRoot(treeId, newRoot, nextIndex);
        return (newRoot, startIndex, nextIndex);
    }

    function _insertManyRepeated(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // update tree (Core returns the authoritative start/next indexes)
        (uint256 newRoot, uint256 startIndex, uint256 nextIndex) = InternalSkinnyIMTCore._insertManyRepeated(
            self,
            value,
            amount,
            hasher
        );
        // emit event
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit RepeatedLeafs(treeId, startIndex, nextIndex, value);
        emit NewRoot(treeId, newRoot, nextIndex);
        return (newRoot, startIndex, nextIndex);
    }

    function _insertManyRepeatedBN254(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // check
        _requireInField(value);
        // update tree (Core returns the authoritative start/next indexes)
        (uint256 newRoot, uint256 startIndex, uint256 nextIndex) = InternalSkinnyIMTCore._insertManyRepeated(
            self,
            value,
            amount,
            hasher
        );
        // emit event
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit RepeatedLeafs(treeId, startIndex, nextIndex, value);
        emit NewRoot(treeId, newRoot, nextIndex);
        return (newRoot, startIndex, nextIndex);
    }

    function _precomputeRepeatedCache(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        // precompute emits no event, so it never reads treeId; guard init explicitly (rare op, cost irrelevant)
        if (self.treeId == 0) {
            revert NotInitialized();
        }
        // update cache
        InternalSkinnyIMTCore._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function _precomputeRepeatedCacheBN254(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        // precompute emits no event, so it never reads treeId; guard init explicitly (rare op, cost irrelevant)
        if (self.treeId == 0) {
            revert NotInitialized();
        }
        // check
        _requireInField(value);
        // update cache
        InternalSkinnyIMTCore._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function _update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        // update tree
        uint256 newRoot = InternalSkinnyIMTCore._update(self, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
        // emit event
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit UpdatedLeaf(treeId, leafIndex, newLeaf, oldLeaf);
        emit NewRoot(treeId, newRoot, self.size);
        return newRoot;
    }

    function _updateBN254(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        // check
        _requireInField(newLeaf);
        _requireAllInField(proofSiblings);
        // update tree
        uint256 newRoot = InternalSkinnyIMTCore._update(self, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
        // emit event
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit UpdatedLeaf(treeId, leafIndex, newLeaf, oldLeaf);
        emit NewRoot(treeId, newRoot, self.size);
        return newRoot;
    }

    function _updateMany(
        SkinnyIMTData storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        // check
        if (self.size == 0) {
            revert TreeEmpty();
        }

        // update tree
        // depth/edgeIndex come from the live tree, never the caller. Built into a local (and the
        // emit loop split into a helper) to keep this frame under the stack-too-deep limit without viaIR.
        MultiProof memory proof = MultiProof(self.depth, self.size - 1, leafIndexes, proofSiblings);
        uint256 newRoot = InternalSkinnyIMTCore._updateMany(self, oldLeaves, newLeaves, proof, hasher);
        // emit event
        // no tree.id == 0 check here, self.size == 0 already does that, also stack limit is too tight
        _emitUpdatedMany(self.treeId, leafIndexes, oldLeaves, newLeaves);
        emit NewRoot(self.treeId, newRoot, self.size);
        return newRoot;
    }

    function _updateManyBN254(
        SkinnyIMTData storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        // check
        if (self.size == 0) {
            revert TreeEmpty();
        }
        _requireAllInField(newLeaves);
        _requireAllInField(proofSiblings);

        // update tree
        // depth/edgeIndex come from the live tree, never the caller. Built into a local (and the
        // emit loop split into a helper) to keep this frame under the stack-too-deep limit without viaIR.
        MultiProof memory proof = MultiProof(self.depth, self.size - 1, leafIndexes, proofSiblings);
        uint256 newRoot = InternalSkinnyIMTCore._updateMany(self, oldLeaves, newLeaves, proof, hasher);
        // emit event
        // no tree.id == 0 check here, self.size == 0 already does that, also stack limit is too tight
        _emitUpdatedMany(self.treeId, leafIndexes, oldLeaves, newLeaves);
        emit NewRoot(self.treeId, newRoot, self.size);
        return newRoot;
    }

    function _root(SkinnyIMTData storage self) internal view returns (uint256) {
        return InternalSkinnyIMTCore._root(self);
    }

    function _proofToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        // verify
        return InternalSkinnyIMTCore._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function _proofToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        // check
        _requireInField(leaf);
        _requireAllInField(proofSiblings);
        // verify
        return InternalSkinnyIMTCore._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function _proofManyToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        // takes treeSize (not edgeIndex) to match _proofToRoot; the core wants edgeIndex == treeSize - 1
        if (treeSize == 0) {
            revert TreeEmpty();
        }
        // verify
        return
            InternalSkinnyIMTCore._proofManyToRoot(
                leaves,
                MultiProof(treeDepth, treeSize - 1, leafIndexes, proofSiblings),
                hasher
            );
    }

    function _proofManyToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        // takes treeSize (not edgeIndex) to match _proofToRoot; the core wants edgeIndex == treeSize - 1
        if (treeSize == 0) {
            revert TreeEmpty();
        }
        // check
        _requireAllInField(leaves);
        _requireAllInField(proofSiblings);
        // verify
        return
            InternalSkinnyIMTCore._proofManyToRoot(
                leaves,
                MultiProof(treeDepth, treeSize - 1, leafIndexes, proofSiblings),
                hasher
            );
    }
}
