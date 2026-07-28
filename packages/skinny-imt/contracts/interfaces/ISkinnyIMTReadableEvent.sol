// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title ISkinnyIMTReadableEvent
interface ISkinnyIMTReadableEvent is IERC165 {
    /// @notice Tree `treeId`'s side nodes in the half-open range [firstIndex, endIndex).
    function getSkinnySideNodes(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view returns (uint256[] memory);

    /// @notice The current root of tree `treeId`.
    function getSkinnyRoot(uint256 treeId) external view returns (uint256);

    /// @notice The number of leaves in tree `treeId`.
    function getSkinnySize(uint256 treeId) external view returns (uint256);

    /// @notice The current depth of tree `treeId`.
    function getSkinnyDepth(uint256 treeId) external view returns (uint256);
}
