// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTEvent, SkinnyIMTDataEvent} from "./InternalSkinnyIMTEvent.sol";
import {IIMTEvents} from "./interfaces/IIMTEvents.sol";
import {_emitUpdatedMany, _requireInField, _requireAllInField} from "./SkinnyIMTUtils.sol";

// added storage of the leaves to allow syncing with full nodes for leaves older then 1 year
struct SkinnyIMTDataStorage {
    // arrays cost more but store in consecutive slots which allows for usage of debug_storageRangeAt
    // to read this extremely fast
    uint256[] leaves;
    SkinnyIMTDataEvent treeData;
}

library InternalSkinnyIMTStorage {
    function _reset(SkinnyIMTDataStorage storage self) internal {
        // the Storage variant also stores leaves in a pushed array, so it must be cleared here;
        // InternalSkinnyIMTEvent._reset only zeroes size/depth in the core.
        delete self.leaves;
        InternalSkinnyIMTEvent._reset(self.treeData);
    }

    /// helper function for clients that don't have debug_storageRangeAt
    /// @param self: A storage reference to the 'SkinnyIMTDataStorage' struct.
    /// @param firstIndex: first leaf index to get (inclusive)
    /// @param endIndex: last leaf index to stop retrieving at (exclusive)
    function _getLeaves(
        SkinnyIMTDataStorage storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) internal view returns (uint256[] memory) {
        uint256[] memory leaves = new uint256[](endIndex - firstIndex);
        for (uint256 i = 0; i < leaves.length; i++) {
            leaves[i] = self.leaves[firstIndex + i];
        }
        return leaves;
    }

    function _getSideNodes(
        SkinnyIMTDataStorage storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) internal view returns (uint256[] memory) {
        return InternalSkinnyIMTEvent._getSideNodes(self.treeData, firstIndex, endIndex);
    }

    function _getRepeatedHashes(
        SkinnyIMTDataStorage storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) internal view returns (uint256[] memory) {
        return InternalSkinnyIMTEvent._getRepeatedHashes(self.treeData, firstIndex, endIndex);
    }

    function _init(SkinnyIMTDataStorage storage self) internal returns (uint256) {
        return InternalSkinnyIMTEvent._init(self.treeData);
    }

    function _insert(
        SkinnyIMTDataStorage storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        self.leaves.push(leaf);
        return InternalSkinnyIMTEvent._insert(self.treeData, leaf, hasher);
    }

    function _insertBN254(
        SkinnyIMTDataStorage storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        self.leaves.push(leaf);
        return InternalSkinnyIMTEvent._insertBN254(self.treeData, leaf, hasher);
    }

    function _insertMany(
        SkinnyIMTDataStorage storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        for (uint256 i = 0; i < leaves.length; i++) {
            self.leaves.push(leaves[i]);
        }
        return InternalSkinnyIMTEvent._insertMany(self.treeData, leaves, hasher);
    }

    function _insertManyBN254(
        SkinnyIMTDataStorage storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        for (uint256 i = 0; i < leaves.length; i++) {
            self.leaves.push(leaves[i]);
        }
        return InternalSkinnyIMTEvent._insertManyBN254(self.treeData, leaves, hasher);
    }

    function _insertManyRepeated(
        SkinnyIMTDataStorage storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        uint256 treeSize = self.treeData.size;
        for (uint256 i = 0; i < amount; i++) {
            self.leaves.push(value);
            emit IIMTEvents.NewLeaf(self.treeData.treeId, treeSize + i, value);
        }
        return InternalSkinnyIMTEvent._insertManyRepeated(self.treeData, value, amount, hasher);
    }

    function _insertManyRepeatedBN254(
        SkinnyIMTDataStorage storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        uint256 treeSize = self.treeData.size;
        for (uint256 i = 0; i < amount; i++) {
            self.leaves.push(value);
            emit IIMTEvents.NewLeaf(self.treeData.treeId, treeSize + i, value);
        }
        return InternalSkinnyIMTEvent._insertManyRepeatedBN254(self.treeData, value, amount, hasher);
    }

    function _precomputeRepeatedCache(
        SkinnyIMTDataStorage storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        return InternalSkinnyIMTEvent._precomputeRepeatedCache(self.treeData, value, upToLevel, hasher);
    }

    function _precomputeRepeatedCacheBN254(
        SkinnyIMTDataStorage storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        return InternalSkinnyIMTEvent._precomputeRepeatedCacheBN254(self.treeData, value, upToLevel, hasher);
    }

    function _update(
        SkinnyIMTDataStorage storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        self.leaves[leafIndex] = newLeaf;
        return InternalSkinnyIMTEvent._update(self.treeData, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
    }

    function _updateBN254(
        SkinnyIMTDataStorage storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        self.leaves[leafIndex] = newLeaf;
        return InternalSkinnyIMTEvent._updateBN254(self.treeData, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
    }

    function _updateMany(
        SkinnyIMTDataStorage storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        for (uint256 i = 0; i < newLeaves.length; i++) {
            self.leaves[leafIndexes[i]] = newLeaves[i];
        }
        return
            InternalSkinnyIMTEvent._updateMany(self.treeData, oldLeaves, newLeaves, leafIndexes, proofSiblings, hasher);
    }

    function _updateManyBN254(
        SkinnyIMTDataStorage storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        for (uint256 i = 0; i < newLeaves.length; i++) {
            self.leaves[leafIndexes[i]] = newLeaves[i];
        }
        return
            InternalSkinnyIMTEvent._updateManyBN254(
                self.treeData,
                oldLeaves,
                newLeaves,
                leafIndexes,
                proofSiblings,
                hasher
            );
    }

    function _root(SkinnyIMTDataStorage storage self) internal view returns (uint256) {
        return InternalSkinnyIMTEvent._root(self.treeData);
    }

    function _proofToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        return InternalSkinnyIMTEvent._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function _proofToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        return InternalSkinnyIMTEvent._proofToRootBN254(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function _proofManyToRoot(
        uint256 treeDepth,
        uint256 edgeIndex,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        return
            InternalSkinnyIMTEvent._proofManyToRoot(treeDepth, edgeIndex, leaves, leafIndexes, proofSiblings, hasher);
    }

    function _proofManyToRootBN254(
        uint256 treeDepth,
        uint256 edgeIndex,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        return
            InternalSkinnyIMTEvent._proofManyToRootBN254(
                treeDepth,
                edgeIndex,
                leaves,
                leafIndexes,
                proofSiblings,
                hasher
            );
    }
}
