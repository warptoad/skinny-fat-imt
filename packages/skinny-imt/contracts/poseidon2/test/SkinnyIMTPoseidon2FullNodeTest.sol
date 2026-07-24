// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon2FullNode} from "../SkinnyIMTPoseidon2FullNode.sol";
import {SkinnyIMTDataFullNode} from "../../InternalSkinnyIMTStorage.sol";

// TEST-ONLY single-tree wrapper around the FullNode lib (leaves stored in a storage array + events).
contract SkinnyIMTPoseidon2FullNodeTest {
    SkinnyIMTDataFullNode internal data;

    constructor() {
        SkinnyIMTPoseidon2FullNode.init(data);
    }

    function reset() external {
        SkinnyIMTPoseidon2FullNode.reset(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTPoseidon2FullNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2FullNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTPoseidon2FullNode.insertManyRepeated(data, value, amount);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTPoseidon2FullNode.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidon2FullNode.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function size() external view returns (uint256) {
        return data.treeData.size;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTPoseidon2FullNode.root(data);
    }
}
