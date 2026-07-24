// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTEvent} from "../InternalSkinnyIMTEvent.sol";
import {SkinnyIMTData} from "../InternalSkinnyIMTCore.sol";

library SkinnyIMTSha256 {
    // sha256 is a built-in precompile (address 0x02); no external deployment needed.
    // These trees use the non-field-checked (non-BN254) variants: sha256 outputs span the
    // full uint256 range, so leaves and siblings are never required to be in the snark field.
    function hasher(uint256[2] memory input) private pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(input[0], input[1])));
    }

    function init(SkinnyIMTData storage self) public returns (uint256) {
        return InternalSkinnyIMTEvent._init(self);
    }

    function reset(SkinnyIMTData storage self) public {
        InternalSkinnyIMTEvent._reset(self);
    }

    function insert(SkinnyIMTData storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalSkinnyIMTEvent._insert(self, leaf, hasher);
    }

    function insertMany(
        SkinnyIMTData storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTEvent._insertMany(self, leaves, hasher);
    }

    function insertManyRepeated(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTEvent._insertManyRepeated(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(SkinnyIMTData storage self, uint256 value, uint256 upToLevel) public {
        return InternalSkinnyIMTEvent._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTEvent._update(self, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
    }

    function updateMany(
        SkinnyIMTData storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTEvent._updateMany(self, oldLeaves, newLeaves, leafIndexes, proofSiblings, hasher);
    }

    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMTEvent._root(self);
    }
}
