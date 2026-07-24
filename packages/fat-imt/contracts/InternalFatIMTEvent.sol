// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalFatIMTCore, FatIMTData, MultiProof, TreeEmpty} from "./InternalFatIMTCore.sol";
import {NewTree, NewRoot, NewLeaf, RepeatedLeafs, UpdatedLeaf} from "./interfaces/events.sol";
import {_emitUpdatedMany, _requireInField, _requireAllInField} from "./FatIMTUtils.sol";

error EndIndexOutOfRange();
error LevelOutOfRange();
error NotInitialized();
error AlreadyInitialized();

library InternalFatIMTEvent {
    function _reset(FatIMTData storage self) internal {
        InternalFatIMTCore._reset(self);
    }

    /// @dev Checks whether the tree has been initialized.
    function _isInitialized(FatIMTData storage self) internal view returns (bool) {
        return self.treeId != 0;
    }

    /// @dev Initializes the tree by assigning it a non-zero `treeId` derived from its storage slot.
    /// `self.treeId` stores `self.slot + 1` so upgradeable contracts that move the slot keep their id.
    function _init(FatIMTData storage self) internal returns (uint256) {
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
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit NewLeaf(treeId, index, leaf);
        emit NewRoot(treeId, newRoot, self.size);
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
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit NewLeaf(treeId, index, leaf);
        emit NewRoot(treeId, newRoot, self.size);
        return (newRoot, index);
    }

    function _insertMany(
        FatIMTData storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // update tree (Core now owns start/next, like _insertManyRepeated)
        (uint256 newRoot, uint256 startIndex, uint256 nextIndex) = InternalFatIMTCore._insertMany(self, leaves, hasher);

        // emit events
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        for (uint256 i = 0; i < leaves.length; ) {
            emit NewLeaf(treeId, startIndex + i, leaves[i]);
            unchecked {
                ++i;
            }
        }
        emit NewRoot(treeId, newRoot, nextIndex);
        return (newRoot, startIndex, nextIndex);
    }

    function _insertManyBN254(
        FatIMTData storage self,
        uint256[] calldata leaves,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // check all leaves are in field before mutating the tree
        _requireAllInField(leaves);

        // update tree (Core now owns start/next, like _insertManyRepeated)
        (uint256 newRoot, uint256 startIndex, uint256 nextIndex) = InternalFatIMTCore._insertMany(self, leaves, hasher);

        // emit events
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        for (uint256 i = 0; i < leaves.length; ) {
            emit NewLeaf(treeId, startIndex + i, leaves[i]);
            unchecked {
                ++i;
            }
        }
        emit NewRoot(treeId, newRoot, nextIndex);
        return (newRoot, startIndex, nextIndex);
    }

    function _insertManyRepeated(
        FatIMTData storage self,
        uint256 value,
        uint256 amount,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256, uint256) {
        // update tree
        (uint256 newRoot, uint256 startIndex, uint256 nextIndex) = InternalFatIMTCore._insertManyRepeated(
            self,
            value,
            amount,
            hasher
        );
        // emit events. fat-imt stores every node anyway, so a NewLeaf per leaf costs it nothing extra.
        // (skinny keeps only RepeatedLeafs here, since there per-leaf events would wreck its scaling.)
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        for (uint256 i = 0; i < amount; ) {
            emit NewLeaf(treeId, startIndex + i, value);
            unchecked {
                ++i;
            }
        }
        emit RepeatedLeafs(treeId, startIndex, nextIndex, value);
        emit NewRoot(treeId, newRoot, nextIndex);
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
        (uint256 newRoot, uint256 startIndex, uint256 nextIndex) = InternalFatIMTCore._insertManyRepeated(
            self,
            value,
            amount,
            hasher
        );
        // emit events. fat-imt stores every node anyway, so a NewLeaf per leaf costs it nothing extra.
        // (skinny keeps only RepeatedLeafs here, since there per-leaf events would wreck its scaling.)
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        for (uint256 i = 0; i < amount; ) {
            emit NewLeaf(treeId, startIndex + i, value);
            unchecked {
                ++i;
            }
        }
        emit RepeatedLeafs(treeId, startIndex, nextIndex, value);
        emit NewRoot(treeId, newRoot, nextIndex);
        return (newRoot, startIndex, nextIndex);
    }

    function _precomputeRepeatedCache(
        FatIMTData storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        // precompute emits no event, so it never reads treeId; guard init explicitly (rare op)
        if (self.treeId == 0) {
            revert NotInitialized();
        }
        // update cache
        InternalFatIMTCore._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function _precomputeRepeatedCacheBN254(
        FatIMTData storage self,
        uint256 value,
        uint256 upToLevel,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal {
        // precompute emits no event, so it never reads treeId; guard init explicitly (rare op)
        if (self.treeId == 0) {
            revert NotInitialized();
        }
        // check
        _requireInField(value);
        // update cache
        InternalFatIMTCore._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function _update(
        FatIMTData storage self,
        uint256 newLeaf,
        uint256 leafIndex,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        // update tree
        (uint256 newRoot, uint256 oldLeaf) = InternalFatIMTCore._update(self, newLeaf, leafIndex, hasher);
        // emit event
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit UpdatedLeaf(treeId, leafIndex, newLeaf, oldLeaf);
        emit NewRoot(treeId, newRoot, self.size);
        return (newRoot, oldLeaf);
    }

    function _updateBN254(
        FatIMTData storage self,
        uint256 newLeaf,
        uint256 leafIndex,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256) {
        // check
        _requireInField(newLeaf);
        // update tree
        (uint256 newRoot, uint256 oldLeaf) = InternalFatIMTCore._update(self, newLeaf, leafIndex, hasher);
        // emit event
        uint256 treeId = self.treeId;
        if (treeId == 0) {
            revert NotInitialized();
        }
        emit UpdatedLeaf(treeId, leafIndex, newLeaf, oldLeaf);
        emit NewRoot(treeId, newRoot, self.size);
        return (newRoot, oldLeaf);
    }

    function _updateMany(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256[] memory) {
        // check: guards the edgeIndex (size - 1) underflow in the core on an empty tree
        if (self.size == 0) {
            revert TreeEmpty();
        }

        // update tree
        (uint256 newRoot, uint256[] memory oldLeaves) = InternalFatIMTCore._updateMany(
            self,
            newLeaves,
            leafIndexes,
            hasher
        );
        // emit event
        // no tree.id == 0 check here, self.size == 0 already does that, also stack limit is too tight
        _emitUpdatedMany(self.treeId, leafIndexes, oldLeaves, newLeaves);
        emit NewRoot(self.treeId, newRoot, self.size);
        return (newRoot, oldLeaves);
    }

    function _updateManyBN254(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal returns (uint256, uint256[] memory) {
        // check: guards the edgeIndex (size - 1) underflow in the core on an empty tree
        if (self.size == 0) {
            revert TreeEmpty();
        }
        _requireAllInField(newLeaves);

        // update tree
        (uint256 newRoot, uint256[] memory oldLeaves) = InternalFatIMTCore._updateMany(
            self,
            newLeaves,
            leafIndexes,
            hasher
        );
        // emit event
        // no tree.id == 0 check here, self.size == 0 already does that, also stack limit is too tight
        _emitUpdatedMany(self.treeId, leafIndexes, oldLeaves, newLeaves);
        emit NewRoot(self.treeId, newRoot, self.size);
        return (newRoot, oldLeaves);
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
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings,
        function(uint256[2] memory) view returns (uint256) hasher
    ) internal view returns (uint256) {
        // takes treeSize (like _proofToRoot); Core's MultiProof works off edgeIndex == treeSize - 1
        if (treeSize == 0) {
            revert TreeEmpty();
        }
        // verify
        return
            InternalFatIMTCore._proofManyToRoot(
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
        // check
        _requireAllInField(leaves);
        _requireAllInField(proofSiblings);
        // takes treeSize (like _proofToRoot); Core's MultiProof works off edgeIndex == treeSize - 1
        if (treeSize == 0) {
            revert TreeEmpty();
        }
        // verify
        return
            InternalFatIMTCore._proofManyToRoot(
                leaves,
                MultiProof(treeDepth, treeSize - 1, leafIndexes, proofSiblings),
                hasher
            );
    }
}
