// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./IV2SwapRouter.sol";
import "./IV3SwapRouter.sol";
import "./IThrusterGas.sol";

interface ISwapRouter02 is IV2SwapRouter, IV3SwapRouter, IThrusterGas {
    
}