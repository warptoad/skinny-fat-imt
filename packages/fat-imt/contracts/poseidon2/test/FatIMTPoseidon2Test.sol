// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2, FatIMTData} from "../FatIMTPoseidon2.sol";

contract FatIMTPoseidon2Test {
    FatIMTData internal data;

    constructor() {
        FatIMTPoseidon2.init(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidon2.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidon2.insertMany(data, leaves);
    }

    function insertManyZeros(uint256 amount) external {
        FatIMTPoseidon2.insertManyZeros(data, amount);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidon2.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        FatIMTPoseidon2.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function leafs(uint256 firstIndex, uint256 lastIndex) external view returns (uint256[] memory) {
        return FatIMTPoseidon2.leafs(data, firstIndex, lastIndex);
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidon2.update(data, newLeaf, index);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external view returns (bool) {
        return FatIMTPoseidon2.verify(data, leaf, index, siblingsNodes);
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidon2.root(data);
    }
}
