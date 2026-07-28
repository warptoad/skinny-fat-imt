// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SkinnyIMTDataEvent, InternalSkinnyIMTEvent} from "./InternalSkinnyIMTEvent.sol";
import {NotInitialized} from "./InternalSkinnyIMTEvent.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ISkinnyIMTReadableEvent} from "./interfaces/ISkinnyIMTReadableEvent.sol";

/// @title SkinnyIMTReadableEvent
/// @dev inheritable interface so any contract with a skinny tree has a common interface for clients side libs to read
///
/// The event variant keeps no leaves — only the side nodes it needs to insert — so there is no leaf
/// reader and no base-slot reader here: nothing lives in consecutive slots for a client to read raw.
/// A consumer that stores its leaves inherits `SkinnyIMTReadableStorage` instead.
abstract contract SkinnyIMTReadableEvent is ERC165, ISkinnyIMTReadableEvent {
    /// @dev Resolves `treeId` to the consumer's tree storage. Single-tree consumers may ignore `treeId`.
    function _getSkinnyEventTree(uint256 treeId) internal view virtual returns (SkinnyIMTDataEvent storage);

    function _initializedSkinnyEventTree(uint256 treeId) internal view returns (SkinnyIMTDataEvent storage) {
        SkinnyIMTDataEvent storage tree = _getSkinnyEventTree(treeId);
        if (tree.treeId == 0) {
            revert NotInitialized();
        }
        return tree;
    }

    /// @dev `supportsInterface` is the one name in this base that cannot carry the `Skinny` prefix —
    /// ERC-165 fixes its selector — so it is the single point a consumer holding a fat tree *and* a
    /// skinny one has to reconcile, where every other name in the two families is disjoint by
    /// construction. Both families root at OpenZeppelin's `ERC165`, so that reconciliation is the
    /// usual one-liner and the `super` walk covers both:
    ///
    ///     function supportsInterface(
    ///         bytes4 interfaceId
    ///     ) public view override(FatIMTReadableStorage, SkinnyIMTReadableStorage) returns (bool) {
    ///         return super.supportsInterface(interfaceId);
    ///     }
    ///
    /// A consumer of one family inherits the right answer and writes nothing at all.
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(ISkinnyIMTReadableEvent).interfaceId || super.supportsInterface(interfaceId);
    }

    function getSkinnySideNodes(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view virtual override returns (uint256[] memory) {
        return InternalSkinnyIMTEvent._getSideNodes(_initializedSkinnyEventTree(treeId), firstIndex, endIndex);
    }

    function getSkinnyRoot(uint256 treeId) external view virtual override returns (uint256) {
        return InternalSkinnyIMTEvent._root(_initializedSkinnyEventTree(treeId));
    }

    function getSkinnySize(uint256 treeId) external view virtual override returns (uint256) {
        return _initializedSkinnyEventTree(treeId).size;
    }

    function getSkinnyDepth(uint256 treeId) external view virtual override returns (uint256) {
        return _initializedSkinnyEventTree(treeId).depth;
    }
}
