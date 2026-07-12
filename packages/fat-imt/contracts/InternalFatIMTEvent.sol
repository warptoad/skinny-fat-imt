// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalFatIMTCore, FatIMTData, MultiProof, TreeEmpty} from "./InternalFatIMTCore.sol";
import {NewTree, NewLeaf, RepeatedLeafs, UpdatedLeaf} from "./interfaces/events.sol";
import {_emitUpdatedMany, _requireInField, _requireAllInField} from "./FatIMTUtils.sol";

error EndIndexOutOfRange();
error LevelOutOfRange();

library InternalFatIMTEvent {
    function _init(FatIMTData storage self) internal returns (uint256) {
        uint256 treeId = InternalFatIMTCore._init(self);
        emit NewTree(treeId);
        return treeId;
    }

    /// helper function for clients to retrieve nodes in a batch
    /// @notice set level 0 to get the leaves
    /// @param self: A storage reference to the 'FatIMTData' struct.
    /// @param firstIndex: first node index to get (inclusive)
    /// @param endIndex: last node index to stop retrieving at (exclusive)
    /// @param level: the tree level to read from (0 == leaves)
    function _getNodes(
        FatIMTData storage self,
        uint256 firstIndex,
        uint256 endIndex,
        uint256 level
    ) internal view returns (uint256[] memory) {
        if (level > self.depth) {
            revert LevelOutOfRange();
        }
        // number of nodes at this level = ceil(size / 2**level); the rightmost may be a dangling node
        uint256 nodeCountAtLevel = (self.size + (1 << level) - 1) >> level;
        if (endIndex > nodeCountAtLevel) {
            revert EndIndexOutOfRange();
        }
        uint256[] memory nodes = new uint256[](endIndex - firstIndex);
        for (uint256 i = 0; i < nodes.length; i++) {
            nodes[i] = self.nodes[level][firstIndex + i];
        }
        return nodes;
    }

    function _insert(
        FatIMTData storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        // update tree
        (uint256 newRoot, uint256 index) = InternalFatIMTCore._insert(self, leaf, hasher);
        // emit event
        emit NewLeaf(self.treeId, index, leaf);
        return (newRoot, index);
    }

    function _insertBN254(
        FatIMTData storage self,
        uint256 leaf,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        // field check
        _requireInField(leaf);
        // update tree
        (uint256 newRoot, uint256 index) = InternalFatIMTCore._insert(self, leaf, hasher);
        // emit event
        emit NewLeaf(self.treeId, index, leaf);
        return (newRoot, index);
    }

    function _insertMany(
        FatIMTData storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        uint256 startIndex = self.size;
        uint256 nextIndex = startIndex + leaves.length;

        // emit events
        uint256 treeId = self.treeId;
        for (uint256 i = 0; i < leaves.length; ) {
            uint256 leaf = leaves[i];
            emit NewLeaf(treeId, startIndex + i, leaf);
            unchecked {
                ++i;
            }
        }

        // update tree
        uint256 newRoot = InternalFatIMTCore._insertMany(self, leaves, hasher);

        return (newRoot, startIndex, nextIndex);
    }

    function _insertManyBN254(
        FatIMTData storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        uint256 startIndex = self.size;
        uint256 nextIndex = startIndex + leaves.length;

        // emit events
        uint256 treeId = self.treeId;
        for (uint256 i = 0; i < leaves.length; ) {
            uint256 leaf = leaves[i];
            _requireInField(leaf);
            emit NewLeaf(treeId, startIndex + i, leaf);
            unchecked {
                ++i;
            }
        }

        // update tree
        uint256 newRoot = InternalFatIMTCore._insertMany(self, leaves, hasher);

        return (newRoot, startIndex, nextIndex);
    }

    function _insertManyRepeated(
        FatIMTData storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // update tree
        (uint256 newRoot, uint256 startIndex, ) = InternalFatIMTCore._insertManyRepeated(self, value, amount, hasher);
        // emit event
        uint256 nextIndex = startIndex + amount;
        emit RepeatedLeafs(self.treeId, startIndex, nextIndex, value);
        return (newRoot, startIndex, nextIndex);
    }

    function _insertManyRepeatedBN254(
        FatIMTData storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // check
        _requireInField(value);
        // update tree
        (uint256 newRoot, uint256 startIndex, ) = InternalFatIMTCore._insertManyRepeated(self, value, amount, hasher);
        // emit event
        uint256 nextIndex = startIndex + amount;
        emit RepeatedLeafs(self.treeId, startIndex, nextIndex, value);
        return (newRoot, startIndex, nextIndex);
    }

    function _precomputeRepeatedCache(
        FatIMTData storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        // update cache
        InternalFatIMTCore._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function _precomputeRepeatedCacheBN254(
        FatIMTData storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        // check
        _requireInField(value);
        // update cache
        InternalFatIMTCore._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function _update(
        FatIMTData storage self,
        uint256 newLeaf,
        uint256 index,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        // update tree
        (uint256 oldLeaf, uint256 newRoot) = InternalFatIMTCore._update(self, newLeaf, index, hasher);
        // emit event
        emit UpdatedLeaf(self.treeId, index, newLeaf, oldLeaf);
        return newRoot;
    }

    function _updateBN254(
        FatIMTData storage self,
        uint256 newLeaf,
        uint256 index,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        // check
        _requireInField(newLeaf);
        // update tree
        (uint256 oldLeaf, uint256 newRoot) = InternalFatIMTCore._update(self, newLeaf, index, hasher);
        // emit event
        emit UpdatedLeaf(self.treeId, index, newLeaf, oldLeaf);
        return newRoot;
    }

    function _updateMany(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        // check: guards the edgeIndex (size - 1) underflow in the core on an empty tree
        if (self.size == 0) {
            revert TreeEmpty();
        }

        // update tree
        (uint256[] memory oldLeaves, uint256 newRoot) = InternalFatIMTCore._updateMany(
            self,
            newLeaves,
            leafIndexes,
            hasher
        );
        // emit event
        _emitUpdatedMany(self.treeId, leafIndexes, oldLeaves, newLeaves);
        return newRoot;
    }

    function _updateManyBN254(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256) {
        // check: guards the edgeIndex (size - 1) underflow in the core on an empty tree
        if (self.size == 0) {
            revert TreeEmpty();
        }
        _requireAllInField(newLeaves);

        // update tree
        (uint256[] memory oldLeaves, uint256 newRoot) = InternalFatIMTCore._updateMany(
            self,
            newLeaves,
            leafIndexes,
            hasher
        );
        // emit event
        _emitUpdatedMany(self.treeId, leafIndexes, oldLeaves, newLeaves);
        return newRoot;
    }

    function _root(FatIMTData storage self) internal view returns (uint256) {
        return InternalFatIMTCore._root(self);
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
        return InternalFatIMTCore._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
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
        return InternalFatIMTCore._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function _proofManyToRoot(
        uint256 treeDepth,
        uint256 edgeIndex,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        // verify
        return
            InternalFatIMTCore._proofManyToRoot(
                leaves,
                MultiProof(treeDepth, edgeIndex, leafIndexes, proofSiblings),
                hasher
            );
    }

    function _proofManyToRootBN254(
        uint256 treeDepth,
        uint256 edgeIndex,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        // check
        _requireAllInField(leaves);
        _requireAllInField(proofSiblings);
        // verify
        return
            InternalFatIMTCore._proofManyToRoot(
                leaves,
                MultiProof(treeDepth, edgeIndex, leafIndexes, proofSiblings),
                hasher
            );
    }
}
