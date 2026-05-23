// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMT, SkinnyIMTData} from "../SkinnyIMT.sol";

contract SkinnyIMTTest {
    SkinnyIMTData internal data;

    constructor() {
        SkinnyIMT.init(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMT.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMT.insertMany(data, leaves);
    }

    function insertManyZeros(uint256 amount) external {
        SkinnyIMT.insertManyZeros(data, amount);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMT.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        SkinnyIMT.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMT.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external view returns (bool) {
        return SkinnyIMT.verify(data, leaf, index, siblingsNodes);
    }

    function root() public view returns (uint256) {
        return SkinnyIMT.root(data);
    }
}
