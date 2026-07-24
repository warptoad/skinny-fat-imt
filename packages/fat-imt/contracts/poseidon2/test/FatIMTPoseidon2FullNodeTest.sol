// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTPoseidon2WriteFullNode} from "../FatIMTPoseidon2WriteFullNode.sol";
import {FatIMTPoseidon2Read} from "../FatIMTPoseidon2Read.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract FatIMTPoseidon2FullNodeTest {
    FatIMTDataFullNode internal data;

    constructor() {
        FatIMTPoseidon2WriteFullNode.init(data);
    }

    function reset() external {
        FatIMTPoseidon2WriteFullNode.reset(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidon2WriteFullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteFullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidon2WriteFullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidon2WriteFullNode.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidon2WriteFullNode.updateMany(data, newLeaves, leafIndexes);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidon2Read.root(data.treeData);
    }
}
