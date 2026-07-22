// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTSha256FullNode} from "../SkinnyIMTSha256FullNode.sol";
import {SkinnyIMTDataFullNode} from "../../InternalSkinnyIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract SkinnyIMTSha256FullNodeTest {
    SkinnyIMTDataFullNode internal data;

    constructor() {
        SkinnyIMTSha256FullNode.init(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTSha256FullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTSha256FullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTSha256FullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTSha256FullNode.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTSha256FullNode.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function size() external view returns (uint256) {
        return data.skinnyData.size;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTSha256FullNode.root(data);
    }
}
