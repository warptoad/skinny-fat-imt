// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMT, SkinnyIMTData} from "./InternalSkinnyIMT.sol";

library SkinnyIMT {
    using InternalSkinnyIMT for *;

    function insert(SkinnyIMTData storage self, uint256 leaf) public returns (uint256) {
        return InternalSkinnyIMT._insert(self, leaf);
    }

    function insertMany(SkinnyIMTData storage self, uint256[] calldata leaves) public returns (uint256) {
        return InternalSkinnyIMT._insertMany(self, leaves);
    }

    function update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 index,
        uint256[] calldata siblingNodes
    ) public returns (uint256) {
        return InternalSkinnyIMT._update(self, oldLeaf, newLeaf, index, siblingNodes);
    }

    function has(SkinnyIMTData storage self, uint256 leaf, uint256 index) public view returns (bool) {
        return InternalSkinnyIMT._has(self, leaf, index);
    }

    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMT._root(self);
    }

    function sideNode(SkinnyIMTData storage self, uint256 index) public view returns (uint256) {
        return InternalSkinnyIMT._sideNode(self, index);
    }
}
