// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTSha256WriteStorage} from "../SkinnyIMTSha256WriteStorage.sol";
import {SkinnyIMTSha256Read} from "../SkinnyIMTSha256Read.sol";
import {SkinnyIMTDataStorage} from "../../InternalSkinnyIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the Storage lib (leaves stored in a storage array + events).
contract SkinnyIMTSha256StorageTest {
    SkinnyIMTDataStorage internal data;

    constructor() {
        SkinnyIMTSha256WriteStorage.init(data);
    }

    function reset() external {
        SkinnyIMTSha256WriteStorage.reset(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTSha256WriteStorage.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTSha256WriteStorage.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTSha256WriteStorage.insertManyRepeated(data, value, amount);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTSha256WriteStorage.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTSha256WriteStorage.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTSha256Read.root(data.treeData);
    }
}
