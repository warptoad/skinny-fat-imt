// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMTSha256, SkinnyIMTData} from "../SkinnyIMTSha256.sol";

contract SkinnyIMTSha256Test {
    SkinnyIMTData internal data;

    constructor() {
        SkinnyIMTSha256.init(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTSha256.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTSha256.insertMany(data, leaves);
    }

    function insertManyZeros(uint256 amount) external {
        SkinnyIMTSha256.insertManyZeros(data, amount);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTSha256.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        SkinnyIMTSha256.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTSha256.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external view returns (bool) {
        return SkinnyIMTSha256.verify(data, leaf, index, siblingsNodes);
    }

    function root() public view returns (uint256) {
        return SkinnyIMTSha256.root(data);
    }
}
