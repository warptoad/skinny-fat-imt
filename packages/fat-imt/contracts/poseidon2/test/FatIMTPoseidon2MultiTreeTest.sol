// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2WriteFullNode} from "../FatIMTPoseidon2WriteFullNode.sol";
import {FatIMTPoseidon2Read} from "../FatIMTPoseidon2Read.sol";
import {FatIMTFullNodeReadable} from "../../FatIMTFullNodeReadable.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";

/// Exercises FatIMTFullNodeReadable against a *mapping* of trees — the multi-tree layout the base
/// must support without assuming a tree sits at one fixed slot. `trees` is deliberately not the
/// first state variable slot's only occupant: the readers must work off whatever `_tree` resolves.
contract FatIMTPoseidon2MultiTreeTest is FatIMTFullNodeReadable {
    mapping(uint256 => FatIMTDataFullNode) internal trees;

    function _getFatTree(uint256 treeId) internal view override returns (FatIMTDataFullNode storage) {
        return trees[treeId];
    }

    function init(uint256 treeId) external returns (uint256) {
        return FatIMTPoseidon2WriteFullNode.init(trees[treeId]);
    }

    function reset(uint256 treeId) external {
        FatIMTPoseidon2WriteFullNode.reset(trees[treeId]);
    }

    function insert(uint256 treeId, uint256 leaf) external {
        FatIMTPoseidon2WriteFullNode.insert(trees[treeId], leaf);
    }

    function insertMany(uint256 treeId, uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteFullNode.insertMany(trees[treeId], leaves);
    }

    function update(uint256 treeId, uint256 newLeaf, uint256 leafIndex) external {
        FatIMTPoseidon2WriteFullNode.update(trees[treeId], newLeaf, leafIndex);
    }

    function root(uint256 treeId) external view returns (uint256) {
        return FatIMTPoseidon2Read.root(trees[treeId].treeData);
    }

    function size(uint256 treeId) external view returns (uint256) {
        return trees[treeId].treeData.size;
    }
}
