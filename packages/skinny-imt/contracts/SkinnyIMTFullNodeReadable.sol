// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTStorage, SkinnyIMTDataFullNode} from "./InternalSkinnyIMTStorage.sol";
import {NotInitialized} from "./InternalSkinnyIMTEvent.sol";

/// @title SkinnyIMTFullNodeReadable
/// @dev Optional base for a full-node consumer. Gives off-chain readers (RPC / `eth_call`) a stable
/// read ABI — `getSkinnyLeaves` / `skinnyLeavesBaseSlot` — without dictating how the consumer stores
/// its trees. The FullNode wrappers deliberately do not expose a leaf reader, so this base is the only
/// ready-made one; a consumer needing something else calls `InternalSkinnyIMTStorage._getLeaves`.
///
/// Every name here is family-prefixed, external ABI included, so this base and `FatIMTFullNodeReadable`
/// can be inherited by the same contract with nothing to reconcile — see the note below.
///
/// The tree is an *input*: the consumer resolves `treeId` by implementing `_getSkinnyTree`, so a single tree,
/// a fixed array, or a mapping all work and nothing here assumes a tree sits at one fixed slot.
/// (External functions can't take a `storage` reference as a parameter, so the id-plus-resolver is
/// how a tree gets "passed in" across the ABI boundary.)
///
/// Hash-function agnostic — reading stored leaves never hashes — so a single base serves
/// poseidon / poseidon2 / sha256. The consumer still wires the hash-specific operations itself:
///
///   contract MyTrees is SkinnyIMTFullNodeReadable {
///       using SkinnyIMTPoseidon2WriteFullNode for SkinnyIMTDataFullNode;
///       mapping(uint256 => SkinnyIMTDataFullNode) internal trees;
///
///       function _getSkinnyTree(uint256 treeId) internal view override returns (SkinnyIMTDataFullNode storage) {
///           return trees[treeId];
///       }
///
///       function insert(uint256 treeId, uint256 leaf) external onlyOwner { trees[treeId].insert(leaf); }
///       // ...update / insertMany / root / size, all on `trees[treeId]`...
///   }
///
/// A single-tree consumer just ignores the id: `return data;`.
///
/// Holding *both* a skinny and a fat tree in one contract is why the names are prefixed rather than
/// plain `getLeaves` / `leavesBaseSlot`. An ABI has room for one `getLeaves(uint256,uint256,uint256)`
/// selector, so two same-named readers would have to be collapsed into one function that decides at
/// runtime which family an id names — the id itself cannot say, since the type is erased at the ABI
/// boundary. Prefixing sidesteps that: the two bases share no selector, so a mixed consumer inherits
/// both and writes nothing to reconcile them, and each family keeps its own id space.
///
///   contract MyTrees is SkinnyIMTFullNodeReadable, FatIMTFullNodeReadable {
///       // implement _getSkinnyTree and _getFatTree; both read ABIs are then simply inherited
///   }
abstract contract SkinnyIMTFullNodeReadable {
    /// @dev Resolves `treeId` to the consumer's tree storage. Single-tree consumers may ignore `treeId`.
    function _getSkinnyTree(uint256 treeId) internal view virtual returns (SkinnyIMTDataFullNode storage);

    /// @dev Resolves `treeId` and rejects a tree that was never initialized. A mapping always resolves
    /// — an unwritten key yields an all-zero struct — so without this a caller asking for a tree that
    /// doesn't exist would get an empty array (or a slot pointing at zeros) and read it as "this tree
    /// is empty". `_init` sets `treeId` to `slot + 1`, so a zero `treeId` means uninitialized.
    /// @notice Storage cannot distinguish a never-written key from one written to zero or `delete`d,
    /// so all three surface as the same error; there is no finer distinction available to detect.
    function _initializedSkinnyTree(uint256 treeId) internal view returns (SkinnyIMTDataFullNode storage) {
        SkinnyIMTDataFullNode storage tree = _getSkinnyTree(treeId);
        if (tree.treeData.treeId == 0) {
            revert NotInitialized();
        }
        return tree;
    }

    /// @notice Returns tree `treeId`'s leaves in the half-open range [from, to).
    /// @dev Convenience reader for full nodes. Meant for off-chain `eth_call` (no gas paid); for large
    /// ranges page it, since the return array is bounded by the node's `eth_call` gas/response limits.
    function getSkinnyLeaves(uint256 treeId, uint256 from, uint256 to) external view returns (uint256[] memory) {
        return InternalSkinnyIMTStorage._getLeaves(_initializedSkinnyTree(treeId), from, to);
    }

    /// @notice Storage slot of tree `treeId`'s `leaves` array header, used by the skinnyfatJs lib to
    /// read leaves directly (`debug_storageRangeAt` / `eth_getStorageAt`).
    /// @dev `leaves` is the first member of `SkinnyIMTDataFullNode`, so the struct's slot is the array
    /// header slot; elements start at `keccak256(slot)`. Derived from whatever `_getSkinnyTree` returns, so it
    /// stays correct for a mapping (`keccak256(key, mappingSlot)`) or array (`base + 6*i`) layout too.
    function skinnyLeavesBaseSlot(uint256 treeId) external view returns (uint256) {
        SkinnyIMTDataFullNode storage tree = _initializedSkinnyTree(treeId);
        uint256 slot;
        assembly {
            slot := tree.slot
        }
        return slot;
    }
}
