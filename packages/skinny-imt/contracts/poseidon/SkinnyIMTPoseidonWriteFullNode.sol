// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

import {InternalSkinnyIMTStorage, SkinnyIMTDataFullNode} from "../InternalSkinnyIMTStorage.sol";

library SkinnyIMTPoseidonWriteFullNode {
    // Kept private: the hasher is only used internally as a function pointer. The optimal call path is
    // inlined anyway, and a standalone hasher costs the same gas deployed separately — so no public entry.
    // getSkinnyLeaves is intentionally NOT exposed here; inherit SkinnyIMTFullNodeReadable for that.
    function hasher(uint256[2] memory input) private pure returns (uint256) {
        return PoseidonT3.hash(input);
    }

    function init(SkinnyIMTDataFullNode storage self) public returns (uint256) {
        return InternalSkinnyIMTStorage._init(self);
    }

    function reset(SkinnyIMTDataFullNode storage self) internal {
        InternalSkinnyIMTStorage._reset(self);
    }

    function insert(SkinnyIMTDataFullNode storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalSkinnyIMTStorage._insertBN254(self, leaf, hasher);
    }

    function insertMany(
        SkinnyIMTDataFullNode storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTStorage._insertManyBN254(self, leaves, hasher);
    }

    function insertManyRepeated(
        SkinnyIMTDataFullNode storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTStorage._insertManyRepeatedBN254(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(SkinnyIMTDataFullNode storage self, uint256 value, uint256 upToLevel) internal {
        return InternalSkinnyIMTStorage._precomputeRepeatedCacheBN254(self, value, upToLevel, hasher);
    }

    function update(
        SkinnyIMTDataFullNode storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTStorage._updateBN254(self, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
    }

    function updateMany(
        SkinnyIMTDataFullNode storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return
            InternalSkinnyIMTStorage._updateManyBN254(self, oldLeaves, newLeaves, leafIndexes, proofSiblings, hasher);
    }
}
