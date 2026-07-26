// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTPoseidon2WriteStorage} from "../FatIMTPoseidon2WriteStorage.sol";
import {FatIMTPoseidon2Read} from "../FatIMTPoseidon2Read.sol";
import {FatIMTDataStorage} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the Storage lib (leaves stored in a storage array + events).
contract FatIMTPoseidon2StorageTest {
    FatIMTDataStorage internal data;

    constructor() {
        FatIMTPoseidon2WriteStorage.init(data);
    }

    function reset() external {
        FatIMTPoseidon2WriteStorage.reset(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidon2WriteStorage.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteStorage.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidon2WriteStorage.insertManyRepeated(data, value, amount);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidon2WriteStorage.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidon2WriteStorage.updateMany(data, newLeaves, leafIndexes);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidon2Read.root(data.treeData);
    }
}
