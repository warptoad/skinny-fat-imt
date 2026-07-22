// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTSha256FullNode} from "../FatIMTSha256FullNode.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract FatIMTSha256FullNodeTest {
    FatIMTDataFullNode internal data;

    constructor() {
        FatIMTSha256FullNode.init(data);
    }

    function insert(uint256 leaf) external {
        FatIMTSha256FullNode.insert(data, leaf);
    }
    function insertMany(uint256[] calldata leaves) external {
        FatIMTSha256FullNode.insertMany(data, leaves);
    }
    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTSha256FullNode.insertManyRepeated(data, value, amount);
    }
    function update(uint256 newLeaf, uint256 index) external {
        FatIMTSha256FullNode.update(data, newLeaf, index);
    }
    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTSha256FullNode.updateMany(data, newLeaves, leafIndexes);
    }
    function size() external view returns (uint256) {
        return data.skinnyData.size;
    }
    function root() public view returns (uint256) {
        return FatIMTSha256FullNode.root(data);
    }
}
