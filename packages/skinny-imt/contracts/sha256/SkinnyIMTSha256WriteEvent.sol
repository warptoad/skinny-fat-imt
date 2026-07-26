// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTEvent, SkinnyIMTDataEvent} from "../InternalSkinnyIMTEvent.sol";

library SkinnyIMTSha256WriteEvent {
    // sha256 is a built-in precompile (address 0x02); no external deployment needed.
    // These trees use the non-field-checked (non-BN254) variants: sha256 outputs span the
    // full uint256 range, so leaves and siblings are never required to be in the snark field.
    function hasher(uint256[2] memory input) private pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(input[0], input[1])));
    }

    function init(SkinnyIMTDataEvent storage self) public returns (uint256) {
        return InternalSkinnyIMTEvent._init(self);
    }

    function reset(SkinnyIMTDataEvent storage self) internal {
        InternalSkinnyIMTEvent._reset(self);
    }

    function insert(SkinnyIMTDataEvent storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalSkinnyIMTEvent._insert(self, leaf, hasher);
    }

    function insertMany(
        SkinnyIMTDataEvent storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTEvent._insertMany(self, leaves, hasher);
    }

    function insertManyRepeated(
        SkinnyIMTDataEvent storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTEvent._insertManyRepeated(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(SkinnyIMTDataEvent storage self, uint256 value, uint256 upToLevel) internal {
        return InternalSkinnyIMTEvent._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function update(
        SkinnyIMTDataEvent storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTEvent._update(self, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
    }

    function updateMany(
        SkinnyIMTDataEvent storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTEvent._updateMany(self, oldLeaves, newLeaves, leafIndexes, proofSiblings, hasher);
    }
}
