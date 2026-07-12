// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

import {InternalFatIMTEvent} from "../InternalFatIMTEvent.sol";
import {FatIMTData} from "../InternalFatIMTCore.sol";

library FatIMTPoseidon {
    using InternalFatIMTEvent for *;

    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return PoseidonT3.hash(input);
    }

    function init(FatIMTData storage self) public returns (uint256) {
        return InternalFatIMTEvent._init(self);
    }

    function insert(FatIMTData storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalFatIMTEvent._insertBN254(self, leaf, hasher);
    }

    function insertMany(FatIMTData storage self, uint256[] calldata leaves) public returns (uint256, uint256, uint256) {
        return InternalFatIMTEvent._insertManyBN254(self, leaves, hasher);
    }

    function insertManyRepeated(
        FatIMTData storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalFatIMTEvent._insertManyRepeatedBN254(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(FatIMTData storage self, uint256 value, uint256 upToLevel) public {
        return InternalFatIMTEvent._precomputeRepeatedCacheBN254(self, value, upToLevel, hasher);
    }

    function update(FatIMTData storage self, uint256 newLeaf, uint256 index) public returns (uint256) {
        return InternalFatIMTEvent._updateBN254(self, newLeaf, index, hasher);
    }

    function updateMany(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes
    ) public returns (uint256) {
        return InternalFatIMTEvent._updateManyBN254(self, newLeaves, leafIndexes, hasher);
    }

    function root(FatIMTData storage self) public view returns (uint256) {
        return InternalFatIMTEvent._root(self);
    }
}
