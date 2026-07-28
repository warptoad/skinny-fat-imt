// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SkinnyIMTPoseidon2WriteEvent} from "../SkinnyIMTPoseidon2WriteEvent.sol";
import {SkinnyIMTReadableEvent} from "../../SkinnyIMTReadableEvent.sol";
import {SkinnyIMTDataEvent} from "../../InternalSkinnyIMTEvent.sol";

/// Exercises SkinnyIMTReadableEvent against a *mapping* of event-variant trees — these keep no
/// leaves at all, only the side nodes, so the side-node reader is all a client has — and against the
/// multi-tree layout the base must support without assuming a tree sits at one fixed slot.
contract SkinnyIMTPoseidon2EventMultiTreeTest is SkinnyIMTReadableEvent {
    mapping(uint256 => SkinnyIMTDataEvent) internal trees;

    function _getSkinnyEventTree(uint256 treeId) internal view override returns (SkinnyIMTDataEvent storage) {
        return trees[treeId];
    }

    function init(uint256 treeId) external returns (uint256) {
        return SkinnyIMTPoseidon2WriteEvent.init(trees[treeId]);
    }

    function reset(uint256 treeId) external {
        SkinnyIMTPoseidon2WriteEvent.reset(trees[treeId]);
    }

    function insertMany(uint256 treeId, uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2WriteEvent.insertMany(trees[treeId], leaves);
    }

    // skinny's update still consumes a merkle proof (oldLeaf + proofSiblings), unlike fat's proof-less update
    function update(
        uint256 treeId,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidon2WriteEvent.update(trees[treeId], oldLeaf, newLeaf, leafIndex, proofSiblings);
    }
}
