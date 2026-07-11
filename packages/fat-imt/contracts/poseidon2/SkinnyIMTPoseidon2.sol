// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibPoseidon2Yul} from "poseidon2-evm/src/bn254/yul/LibPoseidon2Yul.sol";

import {InternalSkinnyIMTEvent} from "../InternalSkinnyIMTEvent.sol";
import {SkinnyIMTData} from "../InternalSkinnyIMTCore.sol";

library SkinnyIMTPoseidon2 {
    using InternalSkinnyIMTEvent for *;

    function hasher(uint256[2] memory leaves) public pure returns (uint256) {
        return LibPoseidon2Yul.hash_2(leaves[0], leaves[1]);
    }

    function init(SkinnyIMTData storage self) public returns (uint256) {
        return InternalSkinnyIMTEvent._init(self);
    }

    function insert(SkinnyIMTData storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalSkinnyIMTEvent._insertBN254(self, leaf, hasher);
    }

    function insertMany(
        SkinnyIMTData storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTEvent._insertManyBN254(self, leaves, hasher);
    }

    function insertManyRepeated(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTEvent._insertManyRepeatedBN254(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(SkinnyIMTData storage self, uint256 value, uint256 upToLevel) public {
        return InternalSkinnyIMTEvent._precomputeRepeatedCacheBN254(self, value, upToLevel, hasher);
    }

    function update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 index,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTEvent._updateBN254(self, oldLeaf, newLeaf, index, proofSiblings, hasher);
    }

    function updateMany(
        SkinnyIMTData storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTEvent._updateManyBN254(self, oldLeaves, newLeaves, leafIndexes, proofSiblings, hasher);
    }

    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMTEvent._root(self);
    }
}
