// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMT, SkinnyIMTData} from "../SkinnyIMT.sol";

contract SkinnyIMTTest {
    SkinnyIMTData public data;

    function insert(uint256 leaf) external {
        SkinnyIMT.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMT.insertMany(data, leaves);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256[] calldata siblingNodes) external {
        SkinnyIMT.update(data, oldLeaf, newLeaf, siblingNodes);
    }

    function remove(uint256 leaf, uint256[] calldata siblingNodes) external {
        SkinnyIMT.remove(data, leaf, siblingNodes);
    }

    function has(uint256 leaf) external view returns (bool) {
        return SkinnyIMT.has(data, leaf);
    }

    function indexOf(uint256 leaf) external view returns (uint256) {
        return SkinnyIMT.indexOf(data, leaf);
    }

    function root() public view returns (uint256) {
        return SkinnyIMT.root(data);
    }
}
