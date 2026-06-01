// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon, SkinnyIMTData} from "../SkinnyIMTPoseidon.sol";

contract SkinnyIMTPoseidonTest {
    SkinnyIMTData internal data;

    constructor() {
        SkinnyIMTPoseidon.init(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTPoseidon.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTPoseidon.insertMany(data, leaves);
    }

    function insertManyZeros(uint256 amount) external {
        SkinnyIMTPoseidon.insertManyZeros(data, amount);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTPoseidon.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        SkinnyIMTPoseidon.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTPoseidon.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external view returns (bool) {
        return SkinnyIMTPoseidon.verify(data, leaf, index, siblingsNodes);
    }

    function root() public view returns (uint256) {
        return SkinnyIMTPoseidon.root(data);
    }
}
