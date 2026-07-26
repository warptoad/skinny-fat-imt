// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FatIMTPoseidonWriteStorage} from "../FatIMTPoseidonWriteStorage.sol";
import {FatIMTPoseidonRead} from "../FatIMTPoseidonRead.sol";
import {FatIMTDataStorage} from "../../InternalFatIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the Storage lib (leaves stored in a storage array + events).
contract FatIMTPoseidonStorageTest {
    FatIMTDataStorage internal data;

    constructor() {
        FatIMTPoseidonWriteStorage.init(data);
    }

    function reset() external {
        FatIMTPoseidonWriteStorage.reset(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidonWriteStorage.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidonWriteStorage.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidonWriteStorage.insertManyRepeated(data, value, amount);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidonWriteStorage.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidonWriteStorage.updateMany(data, newLeaves, leafIndexes);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidonRead.root(data.treeData);
    }
}
