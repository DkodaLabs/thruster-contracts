// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./interfaces/ISwapRouter02.sol";
import "./V2SwapRouter.sol";
import "./V3SwapRouter.sol";
import "./ThrusterGas.sol";

contract SwapRouter02 is ISwapRouter02, V2SwapRouter, V3SwapRouter, ThrusterGas {
    address private constant BLAST_POINTS = 0x2536FE9ab3F511540F2f9e2eC2A805005C3Dd800;

    constructor(address _factoryV2, address _factoryV3, address _WETH, address _manager) 
        V2SwapRouter(_factoryV2, _WETH) 
        V3SwapRouter(_factoryV3, _WETH)
        ThrusterGas(_manager)
    {
        IBlastPoints(BLAST_POINTS).configurePointsOperator(msg.sender);
    }

    function updatePointsAdmin(address _admin) public onlyManager {
        IBlastPoints(BLAST_POINTS).configurePointsOperator(_admin);
    }
}
