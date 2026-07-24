// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

import {InternalFatIMTEvent} from "../InternalFatIMTEvent.sol";
import {FatIMTData} from "../InternalFatIMTCore.sol";

library FatIMTPoseidonWriteArchiveNode {
    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return PoseidonT3.hash(input);
    }

    function init(FatIMTData storage self) public returns (uint256) {
        return InternalFatIMTEvent._init(self);
    }

    function reset(FatIMTData storage self) internal {
        InternalFatIMTEvent._reset(self);
    }

    // getNodes and getLeaves both live in FatIMTPoseidonRead to keep this library under the EIP-170 size limit.

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

    function precomputeRepeatedCache(FatIMTData storage self, uint256 value, uint256 upToLevel) internal {
        return InternalFatIMTEvent._precomputeRepeatedCacheBN254(self, value, upToLevel, hasher);
    }

    function update(FatIMTData storage self, uint256 newLeaf, uint256 leafIndex) public returns (uint256, uint256) {
        return InternalFatIMTEvent._updateBN254(self, newLeaf, leafIndex, hasher);
    }

    function updateMany(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes
    ) public returns (uint256, uint256[] memory) {
        return InternalFatIMTEvent._updateManyBN254(self, newLeaves, leafIndexes, hasher);
    }
}
