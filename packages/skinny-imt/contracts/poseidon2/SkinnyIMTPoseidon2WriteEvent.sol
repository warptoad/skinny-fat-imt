// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibPoseidon2Yul} from "poseidon2-evm/src/bn254/yul/LibPoseidon2Yul.sol";
import {InternalSkinnyIMTEvent, SkinnyIMTDataEvent} from "../InternalSkinnyIMTEvent.sol";

library SkinnyIMTPoseidon2WriteEvent {
    function hasher(uint256[2] memory leaves) private pure returns (uint256) {
        return LibPoseidon2Yul.hash_2(leaves[0], leaves[1]);
    }

    function init(SkinnyIMTDataEvent storage self) public returns (uint256) {
        return InternalSkinnyIMTEvent._init(self);
    }

    function reset(SkinnyIMTDataEvent storage self) internal {
        InternalSkinnyIMTEvent._reset(self);
    }

    function insert(SkinnyIMTDataEvent storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalSkinnyIMTEvent._insertBN254(self, leaf, hasher);
    }

    function insertMany(
        SkinnyIMTDataEvent storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTEvent._insertManyBN254(self, leaves, hasher);
    }

    function insertManyRepeated(
        SkinnyIMTDataEvent storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTEvent._insertManyRepeatedBN254(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(SkinnyIMTDataEvent storage self, uint256 value, uint256 upToLevel) internal {
        return InternalSkinnyIMTEvent._precomputeRepeatedCacheBN254(self, value, upToLevel, hasher);
    }

    function update(
        SkinnyIMTDataEvent storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTEvent._updateBN254(self, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
    }

    function updateMany(
        SkinnyIMTDataEvent storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTEvent._updateManyBN254(self, oldLeaves, newLeaves, leafIndexes, proofSiblings, hasher);
    }
}
