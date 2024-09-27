// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IPeripheryImmutableState.sol";

/// @title Immutable state
/// @notice Functions that return immutable state of the router
interface IImmutableState is IPeripheryImmutableState {
    /// @return Returns the address of the Thruster CFMM factory
    function factoryV2() external view returns (address);
}