// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTEvent} from "../InternalSkinnyIMTEvent.sol";
import {SkinnyIMTData} from "../InternalSkinnyIMTCore.sol";
import {TreeEmpty} from "../InternalSkinnyIMTCore.sol";

/// @title SkinnyIMTSha256Verify
/// @notice Stateless proof verification (`proofToRoot` / `proofManyToRoot`) split out of
/// `SkinnyIMTSha256` and `SkinnyIMTSha256FullNode` to keep those libraries under the
/// EIP-170 contract size limit. Both functions take the whole proof as parameters and touch no
/// storage, so a single library serves the plain and full-node trees alike.
/// Uses the non-field-checked (non-BN254) proof variants: sha256 outputs span the full uint256
/// range, so leaves and siblings are never required to be in the snark field.
library SkinnyIMTSha256Verify {
    using InternalSkinnyIMTEvent for *;

    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(input[0], input[1])));
    }

    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMTEvent._root(self);
    }

    function proofToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        return InternalSkinnyIMTEvent._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function proofManyToRoot(
        uint256 treeDepth,
        uint256 edgeIndex,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        return
            InternalSkinnyIMTEvent._proofManyToRoot(treeDepth, edgeIndex, leaves, leafIndexes, proofSiblings, hasher);
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
        uint256 provenRoot = InternalSkinnyIMTEvent._proofToRoot(
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
        uint256 edgeIndex = self.size - 1;
        uint256 provenRoot = InternalSkinnyIMTEvent._proofManyToRoot(
            self.depth,
            edgeIndex,
            leaves,
            leafIndexes,
            proofSiblings,
            hasher
        );
        uint256 currentRoot = InternalSkinnyIMTEvent._root(self);
        return provenRoot == currentRoot;
    }
}
