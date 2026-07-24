// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTPoseidonWriteFullNode} from "../SkinnyIMTPoseidonWriteFullNode.sol";
import {SkinnyIMTPoseidonRead} from "../SkinnyIMTPoseidonRead.sol";
import {SkinnyIMTDataFullNode} from "../../InternalSkinnyIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract SkinnyIMTPoseidonFullNodeTest {
    SkinnyIMTDataFullNode internal data;

    constructor() {
        SkinnyIMTPoseidonWriteFullNode.init(data);
    }

    function reset() external {
        SkinnyIMTPoseidonWriteFullNode.reset(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTPoseidonWriteFullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTPoseidonWriteFullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTPoseidonWriteFullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTPoseidonWriteFullNode.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidonWriteFullNode.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTPoseidonRead.root(data.treeData);
    }
}
