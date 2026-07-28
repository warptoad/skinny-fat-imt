// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FatIMTDataStorage, InternalFatIMTStorage} from "./InternalFatIMTStorage.sol";
import {FatIMTDataEvent, NotInitialized} from "./InternalFatIMTEvent.sol";
import {FatIMTReadableEvent} from "./FatIMTReadableEvent.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IFatIMTReadableEvent} from "./interfaces/IFatIMTReadableEvent.sol";
import {IFatIMTReadableStorage} from "./interfaces/IFatIMTReadableStorage.sol";

/// @title FatIMTReadableStorage
/// @dev
abstract contract FatIMTReadableStorage is FatIMTReadableEvent, IFatIMTReadableStorage {
    /// @dev Resolves `treeId` to the consumer's tree storage. Single-tree consumers may ignore `treeId`.
    function _getFatStorageTree(uint256 treeId) internal view virtual returns (FatIMTDataStorage storage);

    /// @dev Override this if you have both a storage and a event tree
    function _getFatEventTree(uint256 treeId) internal view virtual override returns (FatIMTDataEvent storage) {
        return _getFatStorageTree(treeId).treeData;
    }

    /// @dev Resolves `treeId` and rejects a tree that was never initialized. A mapping always resolves
    /// — an unwritten key yields an all-zero struct — so without this a caller asking for a tree that
    /// doesn't exist would get an empty array (or a slot pointing at zeros) and read it as "this tree
    /// is empty". `_init` sets `treeId` to `slot + 1`, so a zero `treeId` means uninitialized.
    /// @notice Storage cannot distinguish a never-written key from one written to zero or `delete`d,
    /// so all three surface as the same error; there is no finer distinction available to detect.
    function _initializedFatStorageTree(uint256 treeId) internal view returns (FatIMTDataStorage storage) {
        FatIMTDataStorage storage tree = _getFatStorageTree(treeId);
        if (tree.treeData.treeId == 0) {
            revert NotInitialized();
        }
        return tree;
    }

    /// @dev Only the id this base adds; `super` walks on to `FatIMTReadableEvent` for the event id
    /// and OpenZeppelin's `ERC165` for `0x01ffc9a7`. Note this id covers *only* `getFatLeavesBaseSlot`
    /// — `getFatLeaves` is overridden below rather than added, so it stays in the event id, and
    /// inherited functions are excluded from `type(I).interfaceId` — so a client after the whole read
    /// ABI checks the event id too.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(FatIMTReadableEvent, IERC165) returns (bool) {
        return interfaceId == type(IFatIMTReadableStorage).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Returns tree `treeId`'s leaves in the half-open range [firstIndex, endIndex).
    /// @dev Overrides the event variant's reader to serve the same selector off the dedicated
    /// `leaves` array. Meant for off-chain `eth_call` (no gas paid); for large ranges page it, since
    /// the return array is bounded by the node's `eth_call` gas/response limits.
    function getFatLeaves(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view virtual override(FatIMTReadableEvent, IFatIMTReadableEvent) returns (uint256[] memory) {
        return InternalFatIMTStorage._getLeaves(_initializedFatStorageTree(treeId), firstIndex, endIndex);
    }

    /// @notice Storage slot of tree `treeId`'s `leaves` array header, used by the skinnyfatJs lib to
    /// read leaves directly (`debug_storageRangeAt` / `eth_getStorageAt`).
    /// @dev `leaves` is the first member of `FatIMTDataStorage`, so the struct's slot is the array
    /// header slot; elements start at `keccak256(slot)`. Derived from whatever `_getFatStorageTree`
    /// returns, so it stays correct for a mapping (`keccak256(key, mappingSlot)`) or array layout too.
    function getFatLeavesBaseSlot(uint256 treeId) external view virtual override returns (uint256) {
        FatIMTDataStorage storage tree = _initializedFatStorageTree(treeId);
        uint256 slot;
        assembly {
            slot := tree.slot
        }
        return slot;
    }
}
