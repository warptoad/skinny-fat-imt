// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibPoseidon2Yul} from "poseidon2-evm/src/bn254/yul/LibPoseidon2Yul.sol";

import {InternalSkinnyIMTEvent} from "../InternalSkinnyIMTEvent.sol";
import {SkinnyIMTData} from "../InternalSkinnyIMTCore.sol";
import {TreeEmpty} from "../InternalSkinnyIMTCore.sol";

/// @title SkinnyIMTPoseidon2Verify
/// @notice Stateless proof verification (`proofToRoot` / `proofManyToRoot`) split out of
/// `SkinnyIMTPoseidon2` and `SkinnyIMTPoseidon2FullNode` to keep those libraries under the
/// EIP-170 contract size limit. Both functions take the whole proof as parameters and touch no
/// storage, so a single library serves the plain and full-node trees alike.
library SkinnyIMTPoseidon2Verify {
    using InternalSkinnyIMTEvent for *;

    function hasher(uint256[2] memory leaves) public pure returns (uint256) {
        return LibPoseidon2Yul.hash_2(leaves[0], leaves[1]);
    }

    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMTEvent._root(self);
    }

    function proofToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        return InternalSkinnyIMTEvent._proofToRootBN254(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function proofManyToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        return
            InternalSkinnyIMTEvent._proofManyToRootBN254(
                treeDepth,
                treeSize,
                leaves,
                leafIndexes,
                proofSiblings,
                hasher
            );
    }

    function verify(
        SkinnyIMTData storage self,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public view returns (bool) {
        if (self.size == 0) {
            revert TreeEmpty();
        }
        uint256 provenRoot = InternalSkinnyIMTEvent._proofToRootBN254(
            self.depth,
            self.size,
            leaf,
            leafIndex,
            proofSiblings,
            hasher
        );
        uint256 currentRoot = InternalSkinnyIMTEvent._root(self);
        return provenRoot == currentRoot;
    }

    function verifyMany(
        SkinnyIMTData storage self,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (bool) {
        if (self.size == 0) {
            revert TreeEmpty();
        }
        uint256 provenRoot = InternalSkinnyIMTEvent._proofManyToRootBN254(
            self.depth,
            self.size,
            leaves,
            leafIndexes,
            proofSiblings,
            hasher
        );
        uint256 currentRoot = InternalSkinnyIMTEvent._root(self);
        return provenRoot == currentRoot;
    }
}
