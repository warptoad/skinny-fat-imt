// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTDataStorage, InternalFatIMTStorage} from "./InternalFatIMTStorage.sol";
import {FatIMTDataEvent, NotInitialized} from "./InternalFatIMTEvent.sol";
import {FatIMTReadableEvent} from "./FatIMTReadableEvent.sol";

/// @title FatIMTReadableStorage
/// @dev Inheritable interface so any contract holding a storage-variant fat tree
/// (`FatIMTDataStorage`, which keeps the leaves in a `leaves` array on top of the `nodes` mapping)
/// has a common read ABI for client side libs.
///
/// `FatIMTReadableEvent` plus the two readers only a `leaves` array can serve: `getFatLeaves` off
/// that array rather than level 0 of `nodes`, and `getFatLeavesBaseSlot` for clients that read the
/// consecutive slots straight out of storage. It *inherits* the event base rather than restating its
/// readers, because both would otherwise declare `getFatSize(uint256)` and a consumer could not
/// inherit the two side by side — an ABI has room for one of each signature.
///
/// The tree is an *input*: the consumer resolves `treeId` by implementing `_getFatStorageTree`, so a
/// single tree, a fixed array, or a mapping all work and nothing here assumes a tree sits at one
/// fixed slot. (External functions can't take a `storage` reference as a parameter, so the
/// id-plus-resolver is how a tree gets "passed in" across the ABI boundary.) A single-tree consumer
/// just ignores the id: `return data;`.
///
/// Hash-function agnostic — reading stored leaves and nodes never hashes — so a single base serves
/// poseidon / poseidon2 / sha256. The consumer still wires the hash-specific operations itself:
///
///   contract MyTrees is FatIMTReadableStorage {
///       using FatIMTPoseidon2WriteStorage for FatIMTDataStorage;
///       mapping(uint256 => FatIMTDataStorage) internal trees;
///
///       function _getFatStorageTree(uint256 treeId) internal view override returns (FatIMTDataStorage storage) {
///           return trees[treeId];
///       }
///
///       function insert(uint256 treeId, uint256 leaf) external onlyOwner { trees[treeId].insert(leaf); }
///       // ...update / insertMany / root / size, all on `trees[treeId]`...
///   }
///
/// Holding *both* a fat and a skinny tree in one contract is why the names are prefixed rather than
/// plain `getLeaves` / `leavesBaseSlot`. An ABI has room for one `getLeaves(uint256,uint256,uint256)`
/// selector, so two same-named readers would have to be collapsed into one function that decides at
/// runtime which family an id names — the id itself cannot say, since the type is erased at the ABI
/// boundary. Prefixing sidesteps that: the two bases share no selector, so a mixed consumer inherits
/// both and writes nothing to reconcile them, and each family keeps its own id space.
///
///   contract MyTrees is SkinnyIMTReadableStorage, FatIMTReadableStorage {
///       // implement _getSkinnyStorageTree and _getFatStorageTree; both read ABIs are then inherited
///   }
abstract contract FatIMTReadableStorage is FatIMTReadableEvent {
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

    /// @notice Returns tree `treeId`'s leaves in the half-open range [firstIndex, endIndex).
    /// @dev Overrides the event variant's reader to serve the same selector off the dedicated
    /// `leaves` array. Meant for off-chain `eth_call` (no gas paid); for large ranges page it, since
    /// the return array is bounded by the node's `eth_call` gas/response limits.
    function getFatLeaves(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view virtual override returns (uint256[] memory) {
        return InternalFatIMTStorage._getLeaves(_initializedFatStorageTree(treeId), firstIndex, endIndex);
    }

    /// @notice Storage slot of tree `treeId`'s `leaves` array header, used by the skinnyfatJs lib to
    /// read leaves directly (`debug_storageRangeAt` / `eth_getStorageAt`).
    /// @dev `leaves` is the first member of `FatIMTDataStorage`, so the struct's slot is the array
    /// header slot; elements start at `keccak256(slot)`. Derived from whatever `_getFatStorageTree`
    /// returns, so it stays correct for a mapping (`keccak256(key, mappingSlot)`) or array layout too.
    function getFatLeavesBaseSlot(uint256 treeId) external view returns (uint256) {
        FatIMTDataStorage storage tree = _initializedFatStorageTree(treeId);
        uint256 slot;
        assembly {
            slot := tree.slot
        }
        return slot;
    }
}
