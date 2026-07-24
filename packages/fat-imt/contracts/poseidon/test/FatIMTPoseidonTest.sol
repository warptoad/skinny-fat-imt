// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidonWriteArchiveNode, FatIMTData} from "../FatIMTPoseidonWriteArchiveNode.sol";
import {FatIMTPoseidonRead} from "../FatIMTPoseidonRead.sol";

// verify/verifyMany are wrapped as state-changing (event-emitting) txs rather than
// plain `view` so they appear in the hardhat gas report. Tests read the boolean
// result via `.staticCall` and send the real tx to record gas.
event VerifyResult(bool result);
event VerifyManyResult(bool result);

contract FatIMTPoseidonTest {
    FatIMTData internal data;

    constructor() {
        FatIMTPoseidonWriteArchiveNode.init(data);
    }

    function reset() external {
        FatIMTPoseidonWriteArchiveNode.reset(data);
    }

    function insert(uint256 leaf) external {
        FatIMTPoseidonWriteArchiveNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidonWriteArchiveNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidonWriteArchiveNode.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        FatIMTPoseidonWriteArchiveNode.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidonWriteArchiveNode.update(data, newLeaf, index);
    }

    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidonWriteArchiveNode.updateMany(data, newLeaves, leafIndexes);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external returns (bool) {
        bool result = FatIMTPoseidonRead.verify(data, leaf, index, siblingsNodes);
        emit VerifyResult(result);
        return result;
    }

    function verifyMany(
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external returns (bool) {
        bool result = FatIMTPoseidonRead.verifyMany(data, leaves, leafIndexes, proofSiblings);
        emit VerifyManyResult(result);
        return result;
    }

    function root() public view returns (uint256) {
        return FatIMTPoseidonRead.root(data);
    }
}
