// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2WriteStorage} from "../FatIMTPoseidon2WriteStorage.sol";
import {FatIMTPoseidon2Read} from "../FatIMTPoseidon2Read.sol";
import {FatIMTReadableStorage} from "../../FatIMTReadableStorage.sol";
import {FatIMTDataStorage} from "../../InternalFatIMTStorage.sol";

/// Exercises FatIMTReadableStorage against a *mapping* of trees — the multi-tree layout the base
/// must support without assuming a tree sits at one fixed slot. `trees` is deliberately not the
/// first state variable slot's only occupant: the readers must work off whatever `_tree` resolves.
contract FatIMTPoseidon2MultiTreeTest is FatIMTReadableStorage {
    mapping(uint256 => FatIMTDataStorage) internal trees;

    function _getFatStorageTree(uint256 treeId) internal view override returns (FatIMTDataStorage storage) {
        return trees[treeId];
    }

    function init(uint256 treeId) external returns (uint256) {
        return FatIMTPoseidon2WriteStorage.init(trees[treeId]);
    }

    function reset(uint256 treeId) external {
        FatIMTPoseidon2WriteStorage.reset(trees[treeId]);
    }

    function insert(uint256 treeId, uint256 leaf) external {
        FatIMTPoseidon2WriteStorage.insert(trees[treeId], leaf);
    }

    function insertMany(uint256 treeId, uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteStorage.insertMany(trees[treeId], leaves);
    }

    function update(uint256 treeId, uint256 newLeaf, uint256 leafIndex) external {
        FatIMTPoseidon2WriteStorage.update(trees[treeId], newLeaf, leafIndex);
    }

    function root(uint256 treeId) external view returns (uint256) {
        return FatIMTPoseidon2Read.root(trees[treeId].treeData);
    }

    function size(uint256 treeId) external view returns (uint256) {
        return trees[treeId].treeData.size;
    }
}
