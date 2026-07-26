// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalFatIMTEvent} from "../InternalFatIMTEvent.sol";
import {FatIMTData} from "../InternalFatIMTCore.sol";

library FatIMTSha256WriteEvent {
    // sha256 is a built-in precompile (address 0x02); no external deployment needed.
    // These trees use the non-field-checked (non-BN254) variants: sha256 outputs span the
    // full uint256 range, so leaves and siblings are never required to be in the snark field.
    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(input[0], input[1])));
    }

    function init(FatIMTData storage self) public returns (uint256) {
        return InternalFatIMTEvent._init(self);
    }

    function reset(FatIMTData storage self) internal {
        InternalFatIMTEvent._reset(self);
    }

    // getNodes and getLeaves both live in FatIMTSha256Read to keep this library under the EIP-170 size limit.

    function insert(FatIMTData storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalFatIMTEvent._insert(self, leaf, hasher);
    }

    function insertMany(FatIMTData storage self, uint256[] calldata leaves) public returns (uint256, uint256, uint256) {
        return InternalFatIMTEvent._insertMany(self, leaves, hasher);
    }

    function insertManyRepeated(
        FatIMTData storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalFatIMTEvent._insertManyRepeated(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(FatIMTData storage self, uint256 value, uint256 upToLevel) internal {
        return InternalFatIMTEvent._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function update(FatIMTData storage self, uint256 newLeaf, uint256 leafIndex) public returns (uint256, uint256) {
        return InternalFatIMTEvent._update(self, newLeaf, leafIndex, hasher);
    }

    function updateMany(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes
    ) public returns (uint256, uint256[] memory) {
        return InternalFatIMTEvent._updateMany(self, newLeaves, leafIndexes, hasher);
    }
}
