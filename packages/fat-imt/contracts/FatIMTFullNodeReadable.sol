// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalFatIMTStorage, FatIMTDataFullNode} from "./InternalFatIMTStorage.sol";
import {NotInitialized} from "./InternalFatIMTEvent.sol";

/// @title FatIMTFullNodeReadable
/// @dev Optional base for a full-node consumer. Gives off-chain readers (RPC / `eth_call`) a stable
/// read ABI — `getLeaves` / `getNodes` / `leavesBaseSlot` — without dictating how the consumer stores
/// its trees.
///
/// The tree is an *input*: the consumer resolves `treeId` by implementing `_tree`, so a single tree,
/// a fixed array, or a mapping all work and nothing here assumes a tree sits at one fixed slot.
/// (External functions can't take a `storage` reference as a parameter, so the id-plus-resolver is
/// how a tree gets "passed in" across the ABI boundary.)
///
/// Hash-function agnostic — reading stored leaves and nodes never hashes — so a single base serves
/// poseidon / poseidon2 / sha256. The consumer still wires the hash-specific operations itself:
///
///   contract MyTrees is FatIMTFullNodeReadable {
///       using FatIMTPoseidon2WriteFullNode for FatIMTDataFullNode;
///       mapping(uint256 => FatIMTDataFullNode) internal trees;
///
///       function _tree(uint256 treeId) internal view override returns (FatIMTDataFullNode storage) {
///           return trees[treeId];
///       }
///
///       function insert(uint256 treeId, uint256 leaf) external onlyOwner { trees[treeId].insert(leaf); }
///       // ...update / insertMany / root / size, all on `trees[treeId]`...
///   }
///
/// A single-tree consumer just ignores the id: `return data;`.
abstract contract FatIMTFullNodeReadable {
    /// @dev Resolves `treeId` to the consumer's tree storage. Single-tree consumers may ignore `treeId`.
    function _getFatTree(uint256 treeId) internal view virtual returns (FatIMTDataFullNode storage);

    /// @dev Resolves `treeId` and rejects a tree that was never initialized. A mapping always resolves
    /// — an unwritten key yields an all-zero struct — so without this a caller asking for a tree that
    /// doesn't exist would get an empty array (or a slot pointing at zeros) and read it as "this tree
    /// is empty". `_init` sets `treeId` to `slot + 1`, so a zero `treeId` means uninitialized.
    /// @notice Storage cannot distinguish a never-written key from one written to zero or `delete`d,
    /// so all three surface as the same error; there is no finer distinction available to detect.
    function _initializedFatTree(uint256 treeId) internal view returns (FatIMTDataFullNode storage) {
        FatIMTDataFullNode storage tree = _getFatTree(treeId);
        if (tree.treeData.treeId == 0) {
            revert NotInitialized();
        }
        return tree;
    }

    /// @notice Returns tree `treeId`'s leaves in the half-open range [from, to).
    /// @dev Convenience reader for full nodes. Meant for off-chain `eth_call` (no gas paid); for large
    /// ranges page it, since the return array is bounded by the node's `eth_call` gas/response limits.
    function getLeaves(uint256 treeId, uint256 from, uint256 to) external view returns (uint256[] memory) {
        return InternalFatIMTStorage._getLeaves(_initializedFatTree(treeId), from, to);
    }

    /// @notice Returns tree `treeId`'s nodes at `level` in the half-open range [from, to). Level 0 is
    /// the leaves.
    /// @dev Fat-IMT specific: every internal node is materialized in storage, so a full node can be
    /// resynced level by level without rehashing. Page it for the same `eth_call` limits as above.
    function getNodes(
        uint256 treeId,
        uint256 from,
        uint256 to,
        uint256 level
    ) external view returns (uint256[] memory) {
        return InternalFatIMTStorage._getNodes(_initializedFatTree(treeId), from, to, level);
    }

    /// @notice Storage slot of tree `treeId`'s `leaves` array header, used by the skinnyfatJs lib to
    /// read leaves directly (`debug_storageRangeAt` / `eth_getStorageAt`).
    /// @dev `leaves` is the first member of `FatIMTDataFullNode`, so the struct's slot is the array
    /// header slot; elements start at `keccak256(slot)`. Derived from whatever `_tree` returns, so it
    /// stays correct for a mapping (`keccak256(key, mappingSlot)`) or array (`base + 6*i`) layout too.
    function leavesBaseSlot(uint256 treeId) external view returns (uint256) {
        FatIMTDataFullNode storage tree = _initializedFatTree(treeId);
        uint256 slot;
        assembly {
            slot := tree.slot
        }
        return slot;
    }
}
