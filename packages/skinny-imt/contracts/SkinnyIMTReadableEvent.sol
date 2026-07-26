// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTDataEvent, InternalSkinnyIMTEvent} from "./InternalSkinnyIMTEvent.sol";
import {NotInitialized} from "./InternalSkinnyIMTEvent.sol";

/// @title SkinnyIMTReadableEvent
/// @dev inheritable interface so any contract with a skinny tree has a common interface for clients side libs to read
///
/// The event variant keeps no leaves — only the side nodes it needs to insert — so there is no leaf
/// reader and no base-slot reader here: nothing lives in consecutive slots for a client to read raw.
/// A consumer that stores its leaves inherits `SkinnyIMTReadableStorage` instead.
abstract contract SkinnyIMTReadableEvent {
    /// @dev Resolves `treeId` to the consumer's tree storage. Single-tree consumers may ignore `treeId`.
    function _getSkinnyEventTree(uint256 treeId) internal view virtual returns (SkinnyIMTDataEvent storage);

    function _initializedSkinnyEventTree(uint256 treeId) internal view returns (SkinnyIMTDataEvent storage) {
        SkinnyIMTDataEvent storage tree = _getSkinnyEventTree(treeId);
        if (tree.treeId == 0) {
            revert NotInitialized();
        }
        return tree;
    }

    function getSkinnySideNodes(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view returns (uint256[] memory) {
        return InternalSkinnyIMTEvent._getSideNodes(_initializedSkinnyEventTree(treeId), firstIndex, endIndex);
    }

    function getSkinnySize(uint256 treeId) external view returns (uint256) {
        return _initializedSkinnyEventTree(treeId).size;
    }

    function getSkinnyDepth(uint256 treeId) external view returns (uint256) {
        return _initializedSkinnyEventTree(treeId).depth;
    }
}
