// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTPoseidon2FullNode} from "../FatIMTPoseidon2FullNode.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract FatIMTPoseidon2FullNodeTest {
    FatIMTDataFullNode internal data;

    constructor() {
        FatIMTPoseidon2FullNode.init(data);
    }

    function reset() external {
        FatIMTPoseidon2FullNode.reset(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidon2FullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidon2FullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidon2FullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidon2FullNode.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidon2FullNode.updateMany(data, newLeaves, leafIndexes);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidon2FullNode.root(data);
    }
}
