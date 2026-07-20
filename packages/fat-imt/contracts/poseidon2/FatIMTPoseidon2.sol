// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibPoseidon2Yul} from "poseidon2-evm/src/bn254/yul/LibPoseidon2Yul.sol";

import {InternalFatIMTEvent} from "../InternalFatIMTEvent.sol";
import {FatIMTData} from "../InternalFatIMTCore.sol";

library FatIMTPoseidon2 {
    function hasher(uint256[2] memory leaves) public pure returns (uint256) {
        return LibPoseidon2Yul.hash_2(leaves[0], leaves[1]);
    }

    function init(FatIMTData storage self) public returns (uint256) {
        return InternalFatIMTEvent._init(self);
    }

    // getNodes lives in FatIMTPoseidon2Verify to keep this library under the EIP-170 size limit.
    function getLeaves(
        FatIMTData storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) public view returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(self, firstIndex, endIndex, 0);
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

    function root(FatIMTData storage self) public view returns (uint256) {
        return InternalFatIMTEvent._root(self);
    }
}
