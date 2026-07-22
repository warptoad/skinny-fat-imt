// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTPoseidonFullNode} from "../SkinnyIMTPoseidonFullNode.sol";
import {SkinnyIMTDataFullNode} from "../../InternalSkinnyIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract SkinnyIMTPoseidonFullNodeTest {
    SkinnyIMTDataFullNode internal data;

    constructor() {
        SkinnyIMTPoseidonFullNode.init(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTPoseidonFullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTPoseidonFullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTPoseidonFullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTPoseidonFullNode.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidonFullNode.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function size() external view returns (uint256) {
        return data.skinnyData.size;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTPoseidonFullNode.root(data);
    }
}
