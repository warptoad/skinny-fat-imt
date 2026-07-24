// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTSha256WriteFullNode} from "../SkinnyIMTSha256WriteFullNode.sol";
import {SkinnyIMTSha256Read} from "../SkinnyIMTSha256Read.sol";
import {SkinnyIMTDataFullNode} from "../../InternalSkinnyIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract SkinnyIMTSha256FullNodeTest {
    SkinnyIMTDataFullNode internal data;

    constructor() {
        SkinnyIMTSha256WriteFullNode.init(data);
    }

    function reset() external {
        SkinnyIMTSha256WriteFullNode.reset(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTSha256WriteFullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTSha256WriteFullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTSha256WriteFullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTSha256WriteFullNode.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTSha256WriteFullNode.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTSha256Read.root(data.treeData);
    }
}
