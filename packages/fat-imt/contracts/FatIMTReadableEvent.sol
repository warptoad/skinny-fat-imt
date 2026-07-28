// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FatIMTDataEvent, InternalFatIMTEvent, NotInitialized} from "./InternalFatIMTEvent.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IFatIMTReadableEvent} from "./interfaces/IFatIMTReadableEvent.sol";

abstract contract FatIMTReadableEvent is ERC165, IFatIMTReadableEvent {
    /// @dev Resolves `treeId` to the consumer's tree storage. Single-tree consumers may ignore `treeId`.
    function _getFatEventTree(uint256 treeId) internal view virtual returns (FatIMTDataEvent storage);

    function _initializedFatEventTree(uint256 treeId) internal view returns (FatIMTDataEvent storage) {
        FatIMTDataEvent storage tree = _getFatEventTree(treeId);
        if (tree.treeId == 0) {
            revert NotInitialized();
        }
        return tree;
    }

    /// @dev `supportsInterface` is the one name in this base that cannot carry the `Fat` prefix —
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
        return interfaceId == type(IFatIMTReadableEvent).interfaceId || super.supportsInterface(interfaceId);
    }

    function getFatLeaves(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view virtual override returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(_initializedFatEventTree(treeId), firstIndex, endIndex, 0);
    }

    function getFatNodes(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex,
        uint256 level
    ) external view virtual override returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(_initializedFatEventTree(treeId), firstIndex, endIndex, level);
    }

    function getFatRoot(uint256 treeId) external view virtual override returns (uint256) {
        return InternalFatIMTEvent._root(_initializedFatEventTree(treeId));
    }

    function getFatSize(uint256 treeId) external view virtual override returns (uint256) {
        return _initializedFatEventTree(treeId).size;
    }

    function getFatDepth(uint256 treeId) external view virtual override returns (uint256) {
        return _initializedFatEventTree(treeId).depth;
    }
}
