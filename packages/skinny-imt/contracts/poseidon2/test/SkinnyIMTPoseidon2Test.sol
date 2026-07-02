// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon2, SkinnyIMTData} from "../SkinnyIMTPoseidon2.sol";

contract SkinnyIMTPoseidon2Test {
    SkinnyIMTData internal data;

    constructor() {
        SkinnyIMTPoseidon2.init(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTPoseidon2.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2.insertMany(data, leaves);
    }

    function insertManyZeros(uint256 amount) external {
        SkinnyIMTPoseidon2.insertManyZeros(data, amount);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTPoseidon2.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        SkinnyIMTPoseidon2.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTPoseidon2.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external view returns (bool) {
        return SkinnyIMTPoseidon2.verify(data, leaf, index, siblingsNodes);
    }

    function verifyMany(
        uint256[] calldata leaves,
        uint256[] calldata indices,
        uint256[] calldata proofSiblings
    ) external view returns (bool) {
        return SkinnyIMTPoseidon2.verifyMany(data, leaves, indices, proofSiblings);
    }

    function verifyManyAgainstRoot(
        uint256 expectedRoot,
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata indices,
        uint256[] calldata proofSiblings
    ) external view returns (bool) {
        return SkinnyIMTPoseidon2.verifyManyAgainstRoot(expectedRoot, treeSize, leaves, indices, proofSiblings);
    }

    function root() public view returns (uint256) {
        return SkinnyIMTPoseidon2.root(data);
    }
}
