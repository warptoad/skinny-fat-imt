// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalFatIMTEvent} from "../InternalFatIMTEvent.sol";
import {FatIMTData} from "../InternalFatIMTCore.sol";
import {TreeEmpty} from "../InternalFatIMTCore.sol";
import {InternalFatIMTStorage, FatIMTDataFullNode} from "../InternalFatIMTStorage.sol";

/// @title FatIMTSha256Read
/// @notice Stateless proof verification (`proofToRoot` / `proofManyToRoot`) split out of
/// `FatIMTSha256WriteArchiveNode` and `FatIMTSha256WriteFullNode` to keep those libraries under the
/// EIP-170 contract size limit. Both functions take the whole proof as parameters and touch no
/// storage, so a single library serves the plain and full-node trees alike.
/// Uses the non-field-checked (non-BN254) proof variants: sha256 outputs span the full uint256
/// range, so leaves and siblings are never required to be in the snark field.
library FatIMTSha256Read {
    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(input[0], input[1])));
    }

    function root(FatIMTData storage self) public view returns (uint256) {
        return InternalFatIMTEvent._root(self);
    }

    /// @notice Batch node getter. Reads the `nodes` mapping, which lives in `FatIMTData` for both the
    /// plain and full-node trees — a full-node caller passes its `.treeData`. Hosted here (rather
    /// than in the two wrapper libraries) to keep them under the EIP-170 size limit. set level 0 to
    /// get the leaves.
    function getNodes(
        FatIMTData storage self,
        uint256 firstIndex,
        uint256 endIndex,
        uint256 level
    ) public view returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(self, firstIndex, endIndex, level);
    }

    /// @notice Leaf getter for the plain/archive tree: its leaves live in the `nodes` mapping at
    /// level 0, so this is `getNodes(self, ..., 0)`.
    function getLeaves(
        FatIMTData storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) public view returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(self, firstIndex, endIndex, 0);
    }

    /// @notice Leaf getter for the full-node tree: reads its dedicated `leaves` array (consecutive
    /// storage slots, fast via debug_storageRangeAt). Pass the whole full-node struct, not `.treeData`.
    function getLeaves(
        FatIMTDataFullNode storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) public view returns (uint256[] memory) {
        return InternalFatIMTStorage._getLeaves(self, firstIndex, endIndex);
    }

    function proofToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        return InternalFatIMTEvent._proofToRoot(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function proofManyToRoot(
        uint256 treeDepth,
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        return InternalFatIMTEvent._proofManyToRoot(treeDepth, treeSize, leaves, leafIndexes, proofSiblings, hasher);
    }

    function verify(
        FatIMTData storage self,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public view returns (bool) {
        if (self.size == 0) {
            revert TreeEmpty();
        }
        uint256 provenRoot = InternalFatIMTEvent._proofToRoot(
            self.depth,
            self.size,
            leaf,
            leafIndex,
            proofSiblings,
            hasher
        );
        uint256 currentRoot = InternalFatIMTEvent._root(self);
        return provenRoot == currentRoot;
    }

    function verifyMany(
        FatIMTData storage self,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (bool) {
        if (self.size == 0) {
            revert TreeEmpty();
        }
        uint256 provenRoot = InternalFatIMTEvent._proofManyToRoot(
            self.depth,
            self.size,
            leaves,
            leafIndexes,
            proofSiblings,
            hasher
        );
        uint256 currentRoot = InternalFatIMTEvent._root(self);
        return provenRoot == currentRoot;
    }
}
