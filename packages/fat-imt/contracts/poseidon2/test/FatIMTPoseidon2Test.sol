// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2WriteArchiveNode, FatIMTData} from "../FatIMTPoseidon2WriteArchiveNode.sol";
import {FatIMTPoseidon2Read} from "../FatIMTPoseidon2Read.sol";

// verify/verifyMany are wrapped as state-changing (event-emitting) txs rather than
// plain `view` so they appear in the hardhat gas report. Tests read the boolean
// result via `.staticCall` and send the real tx to record gas.
event VerifyResult(bool result);
event VerifyManyResult(bool result);

contract FatIMTPoseidon2Test {
    FatIMTData internal data;

    constructor() {
        FatIMTPoseidon2WriteArchiveNode.init(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidon2WriteArchiveNode.insert(data, leaf);
    }

    function reset() external {
        FatIMTPoseidon2WriteArchiveNode.reset(data);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteArchiveNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidon2WriteArchiveNode.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        FatIMTPoseidon2WriteArchiveNode.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidon2WriteArchiveNode.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidon2WriteArchiveNode.updateMany(data, newLeaves, leafIndexes);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external returns (bool) {
        bool result = FatIMTPoseidon2Read.verify(data, leaf, index, siblingsNodes);
        emit VerifyResult(result);
        return result;
    }

    function verifyMany(
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external returns (bool) {
        bool result = FatIMTPoseidon2Read.verifyMany(data, leaves, leafIndexes, proofSiblings);
        emit VerifyManyResult(result);
        return result;
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidon2Read.root(data);
    }
}
