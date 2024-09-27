// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./PeripheryImmutableState.sol";
import "../interfaces/IImmutableState.sol";

/// @title Immutable state
/// @notice Immutable state used by combined router contracts
abstract contract ImmutableState is IImmutableState, PeripheryImmutableState {
    /// @inheritdoc IImmutableState
    address public immutable override factoryV2;

    constructor(address _factoryV2, address _factoryV3, address _WETH9) PeripheryImmutableState(_factoryV3, _WETH9) {
        factoryV2 = _factoryV2;
    }
}