// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTSha256, FatIMTData} from "../FatIMTSha256.sol";

contract FatIMTSha256Test {
    FatIMTData internal data;

    constructor() {
        FatIMTSha256.init(data);
    }

    function insert(uint256 leaf) external {
        FatIMTSha256.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTSha256.insertMany(data, leaves);
    }

    function insertManyZeros(uint256 amount) external {
        FatIMTSha256.insertManyZeros(data, amount);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTSha256.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        FatIMTSha256.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTSha256.update(data, newLeaf, index);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external view returns (bool) {
        return FatIMTSha256.verify(data, leaf, index, siblingsNodes);
    }

    function root() public view returns (uint256) {
        return FatIMTSha256.root(data);
    }
}
