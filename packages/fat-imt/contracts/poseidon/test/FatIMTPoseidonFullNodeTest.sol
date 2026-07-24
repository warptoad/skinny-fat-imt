// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTPoseidonWriteFullNode} from "../FatIMTPoseidonWriteFullNode.sol";
import {FatIMTPoseidonRead} from "../FatIMTPoseidonRead.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract FatIMTPoseidonFullNodeTest {
    FatIMTDataFullNode internal data;

    constructor() {
        FatIMTPoseidonWriteFullNode.init(data);
    }

    function reset() external {
        FatIMTPoseidonWriteFullNode.reset(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidonWriteFullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidonWriteFullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidonWriteFullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidonWriteFullNode.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidonWriteFullNode.updateMany(data, newLeaves, leafIndexes);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidonRead.root(data.treeData);
    }
}
