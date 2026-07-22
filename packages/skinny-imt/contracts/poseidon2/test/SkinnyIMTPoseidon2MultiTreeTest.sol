// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon2FullNode} from "../SkinnyIMTPoseidon2FullNode.sol";
import {SkinnyIMTFullNodeReadable} from "../../SkinnyIMTFullNodeReadable.sol";
import {SkinnyIMTDataFullNode} from "../../InternalSkinnyIMTStorage.sol";

/// Exercises SkinnyIMTFullNodeReadable against a *mapping* of trees — the multi-tree layout the base
/// must support without assuming a tree sits at one fixed slot. The readers must work off whatever
/// `_tree` resolves, not a single fixed `data` slot.
contract SkinnyIMTPoseidon2MultiTreeTest is SkinnyIMTFullNodeReadable {
    mapping(uint256 => SkinnyIMTDataFullNode) internal trees;

    function _tree(uint256 treeId) internal view override returns (SkinnyIMTDataFullNode storage) {
        return trees[treeId];
    }

    function init(uint256 treeId) external returns (uint256) {
        return SkinnyIMTPoseidon2FullNode.init(trees[treeId]);
    }

    function insert(uint256 treeId, uint256 leaf) external {
        SkinnyIMTPoseidon2FullNode.insert(trees[treeId], leaf);
    }

    function insertMany(uint256 treeId, uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2FullNode.insertMany(trees[treeId], leaves);
    }

    // skinny's update still consumes a merkle proof (oldLeaf + proofSiblings), unlike fat's proof-less update
    function update(
        uint256 treeId,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidon2FullNode.update(trees[treeId], oldLeaf, newLeaf, leafIndex, proofSiblings);
    }

    function root(uint256 treeId) external view returns (uint256) {
        return SkinnyIMTPoseidon2FullNode.root(trees[treeId]);
    }

    function size(uint256 treeId) external view returns (uint256) {
        return trees[treeId].skinnyData.size;
    }
}
