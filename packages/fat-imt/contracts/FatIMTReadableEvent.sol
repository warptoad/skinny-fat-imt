// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTDataEvent, InternalFatIMTEvent, NotInitialized} from "./InternalFatIMTEvent.sol";

/// @title FatIMTReadableEvent
/// @dev Inheritable interface so any contract holding an event-variant fat tree (`FatIMTDataEvent`,
/// no `leaves` array) has a common read ABI for client side libs — `getFatLeaves` / `getFatNodes` /
/// `getFatSize` / `getFatDepth`.
///
/// The event variant keeps every node in the `nodes` mapping, and level 0 of that mapping *is* the
/// leaves, so `getFatLeaves` is `getFatNodes(..., 0)` here. A consumer that also keeps the leaves in
/// consecutive slots inherits `FatIMTReadableStorage`, which is this base plus the readers only a
/// `leaves` array can serve — so this is the base every fat consumer ends up with, directly or not.
/// There is deliberately no base-slot reader here: nothing in this variant lives in consecutive
/// slots, so a slot to read raw storage from would be of no use to a client.
///
/// The tree is an *input*: the consumer resolves `treeId` by implementing `_getFatEventTree`, so a
/// single tree, a fixed array, or a mapping all work and nothing here assumes a tree sits at one
/// fixed slot. (External functions can't take a `storage` reference as a parameter, so the
/// id-plus-resolver is how a tree gets "passed in" across the ABI boundary.) A single-tree consumer
/// just ignores the id: `return data;`.
///
/// Hash-function agnostic — reading stored nodes never hashes — so a single base serves
/// poseidon / poseidon2 / sha256. The consumer still wires the hash-specific operations itself.
///
/// Every name is family-prefixed, external ABI included, so this base and its skinny counterpart can
/// be inherited by the same contract with nothing to reconcile: an ABI has room for one
/// `getLeaves(uint256,uint256,uint256)` selector, and the id itself cannot say which family it names
/// once the type is erased at the ABI boundary. Prefixing sidesteps that, and each family keeps its
/// own id space. Within *one* family that escape hatch doesn't exist — see the note on
/// `FatIMTReadableStorage._getFatEventTree` for how a consumer holding both variants routes them.
abstract contract FatIMTReadableEvent {
    /// @dev Resolves `treeId` to the consumer's tree storage. Single-tree consumers may ignore `treeId`.
    function _getFatEventTree(uint256 treeId) internal view virtual returns (FatIMTDataEvent storage);

    /// @dev Resolves `treeId` and rejects a tree that was never initialized. A mapping always resolves
    /// — an unwritten key yields an all-zero struct — so without this a caller asking for a tree that
    /// doesn't exist would get an empty array and read it as "this tree is empty". `_init` sets
    /// `treeId` to `slot + 1`, so a zero `treeId` means uninitialized.
    /// @notice Storage cannot distinguish a never-written key from one written to zero or `delete`d,
    /// so all three surface as the same error; there is no finer distinction available to detect.
    function _initializedFatEventTree(uint256 treeId) internal view returns (FatIMTDataEvent storage) {
        FatIMTDataEvent storage tree = _getFatEventTree(treeId);
        if (tree.treeId == 0) {
            revert NotInitialized();
        }
        return tree;
    }

    /// @notice Returns tree `treeId`'s leaves in the half-open range [firstIndex, endIndex).
    /// @dev The leaves are level 0 of the `nodes` mapping. `virtual` because the storage variant
    /// serves the same selector off its `leaves` array instead. Meant for off-chain `eth_call` (no
    /// gas paid); for large ranges page it, since the return array is bounded by the node's
    /// `eth_call` gas/response limits.
    function getFatLeaves(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view virtual returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(_initializedFatEventTree(treeId), firstIndex, endIndex, 0);
    }

    /// @notice Returns tree `treeId`'s nodes at `level` in the half-open range [firstIndex, endIndex).
    /// Level 0 is the leaves.
    /// @dev Fat-IMT specific: every internal node is materialized in storage, so a client can resync
    /// level by level without rehashing. Page it for the same `eth_call` limits as above.
    function getFatNodes(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex,
        uint256 level
    ) external view returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(_initializedFatEventTree(treeId), firstIndex, endIndex, level);
    }

    function getFatSize(uint256 treeId) external view returns (uint256) {
        return _initializedFatEventTree(treeId).size;
    }

    function getFatDepth(uint256 treeId) external view returns (uint256) {
        return _initializedFatEventTree(treeId).depth;
    }
}
