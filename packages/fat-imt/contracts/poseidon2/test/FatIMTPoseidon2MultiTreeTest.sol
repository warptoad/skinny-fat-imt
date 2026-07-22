// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2FullNode} from "../FatIMTPoseidon2FullNode.sol";
import {FatIMTFullNodeReadable} from "../../FatIMTFullNodeReadable.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";

/// Exercises FatIMTFullNodeReadable against a *mapping* of trees — the multi-tree layout the base
/// must support without assuming a tree sits at one fixed slot. `trees` is deliberately not the
/// first state variable slot's only occupant: the readers must work off whatever `_tree` resolves.
contract FatIMTPoseidon2MultiTreeTest is FatIMTFullNodeReadable {
    mapping(uint256 => FatIMTDataFullNode) internal trees;

    function _tree(uint256 treeId) internal view override returns (FatIMTDataFullNode storage) {
        return trees[treeId];
    }

    function init(uint256 treeId) external returns (uint256) {
        return FatIMTPoseidon2FullNode.init(trees[treeId]);
    }

    function insert(uint256 treeId, uint256 leaf) external {
        FatIMTPoseidon2FullNode.insert(trees[treeId], leaf);
    }

    function insertMany(uint256 treeId, uint256[] calldata leaves) external {
        FatIMTPoseidon2FullNode.insertMany(trees[treeId], leaves);
    }

    function update(uint256 treeId, uint256 newLeaf, uint256 leafIndex) external {
        FatIMTPoseidon2FullNode.update(trees[treeId], newLeaf, leafIndex);
    }

    function root(uint256 treeId) external view returns (uint256) {
        return FatIMTPoseidon2FullNode.root(trees[treeId]);
    }

    function size(uint256 treeId) external view returns (uint256) {
        return trees[treeId].skinnyData.size;
    }
}
