// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon2WriteEvent} from "../SkinnyIMTPoseidon2WriteEvent.sol";
import {SkinnyIMTPoseidon2WriteStorage} from "../SkinnyIMTPoseidon2WriteStorage.sol";
import {SkinnyIMTReadableStorage} from "../../SkinnyIMTReadableStorage.sol";
import {SkinnyIMTDataStorage} from "../../InternalSkinnyIMTStorage.sol";
import {SkinnyIMTDataEvent} from "../../InternalSkinnyIMTEvent.sol";

/// Holds an event-variant *and* a storage-variant tree set of the SAME family, which is the case the
/// two readable bases cannot solve by prefixing: `getSkinnySize(uint256)` is one selector, and an id
/// alone cannot say which variant it names. So the two share one id space and the consumer routes,
/// by overriding the one hook the storage base leaves `virtual`.
///
/// The trees live in arrays, so the read ABI's id is simply an index the contract hands out — nothing
/// to pick and nothing encoded in the number. It is not the tree's own `treeId` field, which `_init`
/// derives from the storage slot and which is what the events carry.
contract SkinnyIMTPoseidon2MixedVariantTest is SkinnyIMTReadableStorage {
    /// Which variant each index names. Both tree arrays grow with it, so an index is addressable in
    /// whichever one holds it; the entry belonging to the other variant is never written.
    bool[] internal isStorageTree;
    SkinnyIMTDataEvent[] internal eventTrees;
    SkinnyIMTDataStorage[] internal storageTrees;

    function _getSkinnyStorageTree(uint256 treeIndex) internal view override returns (SkinnyIMTDataStorage storage) {
        return storageTrees[treeIndex];
    }

    /// The routing hook. Without this override every inherited reader would resolve to `storageTrees`
    /// and the event trees would be unreachable through the ABI. Nothing to route for the leaf
    /// readers: an event tree keeps no leaves, so `getSkinnyLeaves` reverting for those indexes says
    /// exactly what is true.
    function _getSkinnyEventTree(uint256 treeIndex) internal view override returns (SkinnyIMTDataEvent storage) {
        if (isStorageTree[treeIndex]) {
            return storageTrees[treeIndex].treeData;
        }
        return eventTrees[treeIndex];
    }

    function initEvent() external returns (uint256) {
        uint256 treeIndex = _appendTree(false);
        SkinnyIMTPoseidon2WriteEvent.init(eventTrees[treeIndex]);
        return treeIndex;
    }

    function initStorage() external returns (uint256) {
        uint256 treeIndex = _appendTree(true);
        SkinnyIMTPoseidon2WriteStorage.init(storageTrees[treeIndex]);
        return treeIndex;
    }

    function insertManyEvent(uint256 treeIndex, uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2WriteEvent.insertMany(eventTrees[treeIndex], leaves);
    }

    function insertManyStorage(uint256 treeIndex, uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2WriteStorage.insertMany(storageTrees[treeIndex], leaves);
    }

    function treeCount() external view returns (uint256) {
        return isStorageTree.length;
    }

    /// Grows all three arrays by one so the new index addresses the same tree in every one of them.
    /// Appending an unused struct only bumps a length slot — the members stay unwritten.
    function _appendTree(bool isStorage) private returns (uint256) {
        isStorageTree.push(isStorage);
        eventTrees.push();
        storageTrees.push();
        return isStorageTree.length - 1;
    }
}
