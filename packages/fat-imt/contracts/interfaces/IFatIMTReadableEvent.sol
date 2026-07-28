// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IFatIMTReadableEvent
/// @dev
interface IFatIMTReadableEvent is IERC165 {
    /// @notice Tree `treeId`'s leaves in the half-open range [firstIndex, endIndex).
    function getFatLeaves(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex
    ) external view returns (uint256[] memory);

    /// @notice Tree `treeId`'s nodes at `level` in the half-open range [firstIndex, endIndex).
    /// Level 0 is the leaves.
    function getFatNodes(
        uint256 treeId,
        uint256 firstIndex,
        uint256 endIndex,
        uint256 level
    ) external view returns (uint256[] memory);

    /// @notice The current root of tree `treeId`.
    function getFatRoot(uint256 treeId) external view returns (uint256);

    /// @notice The number of leaves in tree `treeId`.
    function getFatSize(uint256 treeId) external view returns (uint256);

    /// @notice The current depth of tree `treeId`.
    function getFatDepth(uint256 treeId) external view returns (uint256);
}
