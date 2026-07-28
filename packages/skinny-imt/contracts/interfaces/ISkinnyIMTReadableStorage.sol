// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISkinnyIMTReadableEvent} from "./ISkinnyIMTReadableEvent.sol";

/// @title ISkinnyIMTReadableStorage
interface ISkinnyIMTReadableStorage is ISkinnyIMTReadableEvent {
    /// @notice Tree `treeId`'s leaves in the half-open range [firstIndex, endIndex).
    function getSkinnyLeaves(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view returns (uint256[] memory);

    /// @notice Storage slot of tree `treeId`'s `leaves` array header, for clients reading the leaves
    /// straight out of storage rather than through an `eth_call`.
    function getSkinnyLeavesBaseSlot(uint256 treeId) external view returns (uint256);
}
