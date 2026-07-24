// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTStorage, SkinnyIMTDataFullNode} from "../InternalSkinnyIMTStorage.sol";

library SkinnyIMTSha256WriteFullNode {
    // sha256 is a built-in precompile (address 0x02); no external deployment needed.
    // Uses the non-field-checked (non-BN254) variants: sha256 outputs span the full uint256
    // range, so leaves and siblings are never required to be in the snark field.
    // Kept private: only used internally as a function pointer (inlining is the optimal call path).
    // getLeaves is intentionally NOT exposed here; inherit SkinnyIMTFullNodeReadable for that.
    function hasher(uint256[2] memory input) private pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(input[0], input[1])));
    }

    function init(SkinnyIMTDataFullNode storage self) public returns (uint256) {
        return InternalSkinnyIMTStorage._init(self);
    }

    function reset(SkinnyIMTDataFullNode storage self) internal {
        InternalSkinnyIMTStorage._reset(self);
    }

    function insert(SkinnyIMTDataFullNode storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalSkinnyIMTStorage._insert(self, leaf, hasher);
    }

    function insertMany(
        SkinnyIMTDataFullNode storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTStorage._insertMany(self, leaves, hasher);
    }

    function insertManyRepeated(
        SkinnyIMTDataFullNode storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTStorage._insertManyRepeated(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(SkinnyIMTDataFullNode storage self, uint256 value, uint256 upToLevel) internal {
        return InternalSkinnyIMTStorage._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function update(
        SkinnyIMTDataFullNode storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTStorage._update(self, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
    }

    function updateMany(
        SkinnyIMTDataFullNode storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTStorage._updateMany(self, oldLeaves, newLeaves, leafIndexes, proofSiblings, hasher);
    }
}
