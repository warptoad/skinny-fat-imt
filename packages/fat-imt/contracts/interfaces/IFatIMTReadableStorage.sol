// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFatIMTReadableEvent} from "./IFatIMTReadableEvent.sol";

/// @title IFatIMTReadableStorage
/// @dev
interface IFatIMTReadableStorage is IFatIMTReadableEvent {
    function getFatLeavesBaseSlot(uint256 treeId) external view returns (uint256);
}
