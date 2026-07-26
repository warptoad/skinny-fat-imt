// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2WriteEvent} from "../FatIMTPoseidon2WriteEvent.sol";
import {FatIMTPoseidon2WriteStorage} from "../FatIMTPoseidon2WriteStorage.sol";
import {FatIMTReadableStorage} from "../../FatIMTReadableStorage.sol";
import {InternalFatIMTStorage, FatIMTDataStorage} from "../../InternalFatIMTStorage.sol";
import {InternalFatIMTEvent, FatIMTDataEvent} from "../../InternalFatIMTEvent.sol";

/// Holds an event-variant *and* a storage-variant tree set of the SAME family, which is the case the
/// two readable bases cannot solve by prefixing: `getFatSize(uint256)` is one selector, and an id
/// alone cannot say which variant it names. So the two share one id space and the consumer routes,
/// by overriding the one hook the storage base leaves `virtual`.
///
/// The trees live in arrays, so the read ABI's id is simply an index the contract hands out — nothing
/// to pick and nothing encoded in the number. It is not the tree's own `treeId` field, which `_init`
/// derives from the storage slot and which is what the events carry.
contract FatIMTPoseidon2MixedVariantTest is FatIMTReadableStorage {
    /// Which variant each index names. Both tree arrays grow with it, so an index is addressable in
    /// whichever one holds it; the entry belonging to the other variant is never written.
    bool[] internal isStorageTree;
    FatIMTDataEvent[] internal eventTrees;
    FatIMTDataStorage[] internal storageTrees;

    function _getFatStorageTree(uint256 treeIndex) internal view override returns (FatIMTDataStorage storage) {
        return storageTrees[treeIndex];
    }

    /// The routing hook. Without this override every inherited reader would resolve to `storageTrees`
    /// and the event trees would be unreachable through the ABI.
    function _getFatEventTree(uint256 treeIndex) internal view override returns (FatIMTDataEvent storage) {
        if (isStorageTree[treeIndex]) {
            return storageTrees[treeIndex].treeData;
        }
        return eventTrees[treeIndex];
    }

    /// The leaf reader defaults to the `leaves` array, which an event tree doesn't have — but a fat
    /// event tree still keeps its leaves at level 0 of `nodes`, so route this one too rather than
    /// letting event indexes revert. (Skinny has nothing to route here: its event variant stores no
    /// leaves at all.)
    function getFatLeaves(
        uint256 treeIndex,
        uint256 firstIndex,
        uint256 endIndex
    ) external view override returns (uint256[] memory) {
        if (isStorageTree[treeIndex]) {
            return InternalFatIMTStorage._getLeaves(_initializedFatStorageTree(treeIndex), firstIndex, endIndex);
        }
        return InternalFatIMTEvent._getNodes(_initializedFatEventTree(treeIndex), firstIndex, endIndex, 0);
    }

    function initEvent() external returns (uint256) {
        uint256 treeIndex = _appendTree(false);
        FatIMTPoseidon2WriteEvent.init(eventTrees[treeIndex]);
        return treeIndex;
    }

    function initStorage() external returns (uint256) {
        uint256 treeIndex = _appendTree(true);
        FatIMTPoseidon2WriteStorage.init(storageTrees[treeIndex]);
        return treeIndex;
    }

    function insertManyEvent(uint256 treeIndex, uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteEvent.insertMany(eventTrees[treeIndex], leaves);
    }

    function insertManyStorage(uint256 treeIndex, uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteStorage.insertMany(storageTrees[treeIndex], leaves);
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
