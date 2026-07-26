// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTDataStorage, InternalSkinnyIMTStorage} from "./InternalSkinnyIMTStorage.sol";
import {SkinnyIMTDataEvent, InternalSkinnyIMTEvent} from "./InternalSkinnyIMTEvent.sol";
import {NotInitialized} from "./InternalSkinnyIMTEvent.sol";
import {SkinnyIMTReadableEvent} from "./SkinnyIMTReadableEvent.sol";

/// @title SkinnyIMTReadableStorage
/// @dev inheritable interface so any contract with a skinny tree has a common interface for clients side libs to read
///
/// Same shape as `SkinnyIMTReadableEvent`, plus the two readers that only the storage variant can
/// serve: `getSkinnyLeaves` off its `leaves` array, and `getSkinnyLeavesBaseSlot` for clients that
/// read that array straight out of storage.
abstract contract SkinnyIMTReadableStorage is SkinnyIMTReadableEvent {
    /// @dev Resolves `treeId` to the consumer's tree storage. Single-tree consumers may ignore `treeId`.
    function _getSkinnyStorageTree(uint256 treeId) internal view virtual returns (SkinnyIMTDataStorage storage);

    /// @dev Override this if you have both a storage and a event tree
    function _getSkinnyEventTree(uint256 treeId) internal view virtual override returns (SkinnyIMTDataEvent storage) {
        return _getSkinnyStorageTree(treeId).treeData;
    }

    function _initializedSkinnyStorageTree(uint256 treeId) internal view returns (SkinnyIMTDataStorage storage) {
        SkinnyIMTDataStorage storage tree = _getSkinnyStorageTree(treeId);
        if (tree.treeData.treeId == 0) {
            revert NotInitialized();
        }
        return tree;
    }

    function getSkinnyLeaves(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view returns (uint256[] memory) {
        return InternalSkinnyIMTStorage._getLeaves(_initializedSkinnyStorageTree(treeId), firstIndex, endIndex);
    }

    function getSkinnyLeavesBaseSlot(uint256 treeId) external view returns (uint256) {
        SkinnyIMTDataStorage storage tree = _initializedSkinnyStorageTree(treeId);
        uint256 slot;
        assembly {
            slot := tree.slot
        }
        return slot;
    }
}
