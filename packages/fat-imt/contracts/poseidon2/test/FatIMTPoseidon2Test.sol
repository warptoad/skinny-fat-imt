// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2, FatIMTData} from "../FatIMTPoseidon2.sol";
import {FatIMTPoseidon2Verify} from "../FatIMTPoseidon2Verify.sol";

// verify/verifyMany are wrapped as state-changing (event-emitting) txs rather than
// plain `view` so they appear in the hardhat gas report. Tests read the boolean
// result via `.staticCall` and send the real tx to record gas.
event VerifyResult(bool result);
event VerifyManyResult(bool result);

contract FatIMTPoseidon2Test {
    FatIMTData internal data;

    constructor() {
        FatIMTPoseidon2.init(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidon2.insert(data, leaf);
    }

    function reset() external {
        FatIMTPoseidon2.reset(data);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidon2.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidon2.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        FatIMTPoseidon2.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidon2.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidon2.updateMany(data, newLeaves, leafIndexes);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external returns (bool) {
        bool result = FatIMTPoseidon2Verify.verify(data, leaf, index, siblingsNodes);
        emit VerifyResult(result);
        return result;
    }

    function verifyMany(
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external returns (bool) {
        bool result = FatIMTPoseidon2Verify.verifyMany(data, leaves, leafIndexes, proofSiblings);
        emit VerifyManyResult(result);
        return result;
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidon2.root(data);
    }
}
