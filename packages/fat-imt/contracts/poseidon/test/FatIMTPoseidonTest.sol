// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon, FatIMTData} from "../FatIMTPoseidon.sol";

contract FatIMTPoseidonTest {
    FatIMTData internal data;

    constructor() {
        FatIMTPoseidon.init(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidon.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidon.insertMany(data, leaves);
    }

    function insertManyZeros(uint256 amount) external {
        FatIMTPoseidon.insertManyZeros(data, amount);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidon.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        FatIMTPoseidon.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function leafs(uint256 firstIndex, uint256 lastIndex) external view returns (uint256[] memory) {
        return FatIMTPoseidon.leafs(data, firstIndex, lastIndex);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidon.update(data, newLeaf, index);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external view returns (bool) {
        return FatIMTPoseidon.verify(data, leaf, index, siblingsNodes);
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidon.root(data);
    }
}
