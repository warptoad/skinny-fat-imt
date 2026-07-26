// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTSha256WriteStorage} from "../FatIMTSha256WriteStorage.sol";
import {FatIMTSha256Read} from "../FatIMTSha256Read.sol";
import {FatIMTDataStorage} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the Storage lib (leaves stored in a storage array + events).
contract FatIMTSha256StorageTest {
    FatIMTDataStorage internal data;

    constructor() {
        FatIMTSha256WriteStorage.init(data);
    }

    function reset() external {
        FatIMTSha256WriteStorage.reset(data);
    }

    function insert(uint256 leaf) external {
        FatIMTSha256WriteStorage.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTSha256WriteStorage.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTSha256WriteStorage.insertManyRepeated(data, value, amount);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTSha256WriteStorage.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTSha256WriteStorage.updateMany(data, newLeaves, leafIndexes);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return FatIMTSha256Read.root(data.treeData);
    }
}
