// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2WriteEvent} from "../FatIMTPoseidon2WriteEvent.sol";
import {FatIMTPoseidon2Read} from "../FatIMTPoseidon2Read.sol";
import {FatIMTReadableEvent} from "../../FatIMTReadableEvent.sol";
import {FatIMTDataEvent} from "../../InternalFatIMTEvent.sol";

/// Exercises FatIMTReadableEvent against a *mapping* of event-variant trees — no `leaves` array, so
/// the leaf reader has to come off level 0 of the `nodes` mapping — and against the multi-tree layout
/// the base must support without assuming a tree sits at one fixed slot.
contract FatIMTPoseidon2EventMultiTreeTest is FatIMTReadableEvent {
    mapping(uint256 => FatIMTDataEvent) internal trees;

    function _getFatEventTree(uint256 treeId) internal view override returns (FatIMTDataEvent storage) {
        return trees[treeId];
    }

    function init(uint256 treeId) external returns (uint256) {
        return FatIMTPoseidon2WriteEvent.init(trees[treeId]);
    }

    function reset(uint256 treeId) external {
        FatIMTPoseidon2WriteEvent.reset(trees[treeId]);
    }

    function insertMany(uint256 treeId, uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteEvent.insertMany(trees[treeId], leaves);
    }

    function update(uint256 treeId, uint256 newLeaf, uint256 leafIndex) external {
        FatIMTPoseidon2WriteEvent.update(trees[treeId], newLeaf, leafIndex);
    }

    function root(uint256 treeId) external view returns (uint256) {
        return FatIMTPoseidon2Read.root(trees[treeId]);
    }
}
