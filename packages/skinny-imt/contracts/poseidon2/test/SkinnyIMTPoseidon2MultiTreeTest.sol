// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon2WriteStorage} from "../SkinnyIMTPoseidon2WriteStorage.sol";
import {SkinnyIMTPoseidon2Read} from "../SkinnyIMTPoseidon2Read.sol";
import {SkinnyIMTReadableStorage} from "../../SkinnyIMTReadableStorage.sol";
import {SkinnyIMTDataStorage} from "../../InternalSkinnyIMTStorage.sol";

/// Exercises SkinnyIMTReadableStorage against a *mapping* of trees — the multi-tree layout the base
/// must support without assuming a tree sits at one fixed slot. The readers must work off whatever
/// `_tree` resolves, not a single fixed `data` slot.
contract SkinnyIMTPoseidon2MultiTreeTest is SkinnyIMTReadableStorage {
    mapping(uint256 => SkinnyIMTDataStorage) internal trees;

    function _getSkinnyStorageTree(uint256 treeId) internal view override returns (SkinnyIMTDataStorage storage) {
        return trees[treeId];
    }

    function init(uint256 treeId) external returns (uint256) {
        return SkinnyIMTPoseidon2WriteStorage.init(trees[treeId]);
    }

    function reset(uint256 treeId) external {
        SkinnyIMTPoseidon2WriteStorage.reset(trees[treeId]);
    }

    function insert(uint256 treeId, uint256 leaf) external {
        SkinnyIMTPoseidon2WriteStorage.insert(trees[treeId], leaf);
    }

    function insertMany(uint256 treeId, uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2WriteStorage.insertMany(trees[treeId], leaves);
    }

    // skinny's update still consumes a merkle proof (oldLeaf + proofSiblings), unlike fat's proof-less update
    function update(
        uint256 treeId,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidon2WriteStorage.update(trees[treeId], oldLeaf, newLeaf, leafIndex, proofSiblings);
    }

    function root(uint256 treeId) external view returns (uint256) {
        return SkinnyIMTPoseidon2Read.root(trees[treeId].treeData);
    }

    function size(uint256 treeId) external view returns (uint256) {
        return trees[treeId].treeData.size;
    }
}
