// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalFatIMTEvent, FatIMTData} from "./InternalFatIMTEvent.sol";
import {_emitUpdatedMany, _requireInField, _requireAllInField} from "./FatIMTUtils.sol";

// added storage of the leaves to allow syncing with full nodes for leaves older then 1 year
struct FatIMTDataFullNode {
    // arrays cost more but store in consecutive slots which allows for usage of debug_storageRangeAt
    // to read this extremely fast
    uint256[] leaves;
    FatIMTData treeData;
}

library InternalFatIMTStorage {
    function _reset(FatIMTDataFullNode storage self) internal {
        // the FullNode variant also stores leaves in a pushed array, so it must be cleared here;
        // InternalFatIMTEvent._reset only zeroes size/depth in the core.
        delete self.leaves;
        InternalFatIMTEvent._reset(self.treeData);
    }

    /// helper function for clients that don't have debug_storageRangeAt
    /// @param self: A storage reference to the 'FatIMTDataFullNode' struct.
    /// @param firstIndex: first leaf index to get (inclusive)
    /// @param endIndex: last leaf index to stop retrieving at (exclusive)
    function _getLeaves(
        FatIMTDataFullNode storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) internal view returns (uint256[] memory) {
        uint256[] memory leaves = new uint256[](endIndex - firstIndex);
        for (uint256 i = 0; i < leaves.length; i++) {
            leaves[i] = self.leaves[firstIndex + i];
        }
        return leaves;
    }

    function _getNodes(
        FatIMTDataFullNode storage self,
        uint256 firstIndex,
        uint256 endIndex,
        uint256 level
    ) internal view returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(self.treeData, firstIndex, endIndex, level);
    }

    function _init(FatIMTDataFullNode storage self) internal returns (uint256) {
        return InternalFatIMTEvent._init(self.treeData);
    }

    function _insert(
        FatIMTDataFullNode storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        self.leaves.push(leaf);
        return InternalFatIMTEvent._insert(self.treeData, leaf, hasher);
    }

    function _insertBN254(
        FatIMTDataFullNode storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        self.leaves.push(leaf);
        return InternalFatIMTEvent._insertBN254(self.treeData, leaf, hasher);
    }

    function _insertMany(
        FatIMTDataFullNode storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        for (uint256 i = 0; i < leaves.length; i++) {
            self.leaves.push(leaves[i]);
        }
        return InternalFatIMTEvent._insertMany(self.treeData, leaves, hasher);
    }

    function _insertManyBN254(
        FatIMTDataFullNode storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        for (uint256 i = 0; i < leaves.length; i++) {
            self.leaves.push(leaves[i]);
        }
        return InternalFatIMTEvent._insertManyBN254(self.treeData, leaves, hasher);
    }

    function _insertManyRepeated(
        FatIMTDataFullNode storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // leaves are stored here; NewLeaf/RepeatedLeafs events are emitted by the Event layer.
        for (uint256 i = 0; i < amount; i++) {
            self.leaves.push(value);
        }
        return InternalFatIMTEvent._insertManyRepeated(self.treeData, value, amount, hasher);
    }

    function _insertManyRepeatedBN254(
        FatIMTDataFullNode storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // leaves are stored here; NewLeaf/RepeatedLeafs events are emitted by the Event layer.
        for (uint256 i = 0; i < amount; i++) {
            self.leaves.push(value);
        }
        return InternalFatIMTEvent._insertManyRepeatedBN254(self.treeData, value, amount, hasher);
    }

    function _precomputeRepeatedCache(
        FatIMTDataFullNode storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        return InternalFatIMTEvent._precomputeRepeatedCache(self.treeData, value, upToLevel, hasher);
    }

    function _precomputeRepeatedCacheBN254(
        FatIMTDataFullNode storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        return InternalFatIMTEvent._precomputeRepeatedCacheBN254(self.treeData, value, upToLevel, hasher);
    }

    function _update(
        FatIMTDataFullNode storage self,
        uint256 newLeaf,
        uint256 leafIndex,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        self.leaves[leafIndex] = newLeaf;
        return InternalFatIMTEvent._update(self.treeData, newLeaf, leafIndex, hasher);
    }

    function _updateBN254(
        FatIMTDataFullNode storage self,
        uint256 newLeaf,
        uint256 leafIndex,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        self.leaves[leafIndex] = newLeaf;
        return InternalFatIMTEvent._updateBN254(self.treeData, newLeaf, leafIndex, hasher);
    }

    function _updateMany(
        FatIMTDataFullNode storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256[] memory) {
        for (uint256 i = 0; i < newLeaves.length; i++) {
            self.leaves[leafIndexes[i]] = newLeaves[i];
        }
        return InternalFatIMTEvent._updateMany(self.treeData, newLeaves, leafIndexes, hasher);
    }

    function _updateManyBN254(
        FatIMTDataFullNode storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256[] memory) {
        for (uint256 i = 0; i < newLeaves.length; i++) {
            self.leaves[leafIndexes[i]] = newLeaves[i];
        }
        return InternalFatIMTEvent._updateManyBN254(self.treeData, newLeaves, leafIndexes, hasher);
    }

    function _root(FatIMTDataFullNode storage self) internal view returns (uint256) {
        return InternalFatIMTEvent._root(self.treeData);
    }

    function _proofToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        return InternalFatIMTEvent._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function _proofToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        return InternalFatIMTEvent._proofToRootBN254(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function _proofManyToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        return InternalFatIMTEvent._proofManyToRoot(treeDepth, treeSize, leaves, leafIndexes, proofSiblings, hasher);
    }

    function _proofManyToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        return
            InternalFatIMTEvent._proofManyToRootBN254(treeDepth, treeSize, leaves, leafIndexes, proofSiblings, hasher);
    }
}
