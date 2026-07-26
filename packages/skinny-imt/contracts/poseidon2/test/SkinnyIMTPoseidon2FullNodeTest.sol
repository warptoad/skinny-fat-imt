// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon2WriteStorage} from "../SkinnyIMTPoseidon2WriteStorage.sol";
import {SkinnyIMTPoseidon2Read} from "../SkinnyIMTPoseidon2Read.sol";
import {SkinnyIMTDataStorage} from "../../InternalSkinnyIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the Storage lib (leaves stored in a storage array + events).
contract SkinnyIMTPoseidon2StorageTest {
    SkinnyIMTDataStorage internal data;

    constructor() {
        SkinnyIMTPoseidon2WriteStorage.init(data);
    }

    function reset() external {
        SkinnyIMTPoseidon2WriteStorage.reset(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTPoseidon2WriteStorage.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2WriteStorage.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTPoseidon2WriteStorage.insertManyRepeated(data, value, amount);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTPoseidon2WriteStorage.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidon2WriteStorage.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTPoseidon2Read.root(data.treeData);
    }
}
