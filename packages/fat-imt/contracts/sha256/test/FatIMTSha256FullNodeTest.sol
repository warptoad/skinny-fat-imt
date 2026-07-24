// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTSha256WriteFullNode} from "../FatIMTSha256WriteFullNode.sol";
import {FatIMTSha256Read} from "../FatIMTSha256Read.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract FatIMTSha256FullNodeTest {
    FatIMTDataFullNode internal data;

    constructor() {
        FatIMTSha256WriteFullNode.init(data);
    }

    function reset() external {
        FatIMTSha256WriteFullNode.reset(data);
    }

    function insert(uint256 leaf) external {
        FatIMTSha256WriteFullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTSha256WriteFullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTSha256WriteFullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTSha256WriteFullNode.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTSha256WriteFullNode.updateMany(data, newLeaves, leafIndexes);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return FatIMTSha256Read.root(data.treeData);
    }
}
