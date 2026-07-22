// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTPoseidonFullNode} from "../FatIMTPoseidonFullNode.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract FatIMTPoseidonFullNodeTest {
    FatIMTDataFullNode internal data;

    constructor() {
        FatIMTPoseidonFullNode.init(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidonFullNode.insert(data, leaf);
    }
    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidonFullNode.insertMany(data, leaves);
    }
    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidonFullNode.insertManyRepeated(data, value, amount);
    }
    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidonFullNode.update(data, newLeaf, index);
    }
    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidonFullNode.updateMany(data, newLeaves, leafIndexes);
    }
    function size() external view returns (uint256) {
        return data.skinnyData.size;
    }
    function root() public view returns (uint256) {
        return FatIMTPoseidonFullNode.root(data);
    }
}
