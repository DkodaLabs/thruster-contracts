// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IBlastPoints.sol";
import "./interfaces/IV2SwapRouter.sol";
import "./interfaces/IThrusterV2Factory.sol";
import "./interfaces/IWETH.sol";

import "./base/PeripheryPaymentsWithFeeExtended.sol";
import "./libraries/LowGasSafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/ThrusterV2Library.sol";
import "./libraries/Constants.sol";

abstract contract V2SwapRouter is IV2SwapRouter, PeripheryPaymentsWithFeeExtended {
    using LowGasSafeMath for uint256;

    address public immutable override factoryV2;
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "ThrusterRouter: EXPIRED");
        _;
    }

    constructor(address _factoryV2, address _WETH) {
        factoryV2 = _factoryV2;
        WETH = _WETH;
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = ThrusterV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 
                ? ThrusterV2Library.pairFor(factoryV2, output, path[i + 2]) 
                : _to;
            IThrusterPair(ThrusterV2Library.pairFor(factoryV2, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        bool hasAlreadyPaid;
        if (amountIn == Constants.CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            amountIn = IERC20(path[0]).balanceOf(address(this));
        }
        
        amounts = ThrusterV2Library.getAmountsOut(factoryV2, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "ThrusterRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        pay(
            path[0], 
            hasAlreadyPaid ? address(this) : msg.sender, 
            ThrusterV2Library.pairFor(factoryV2, path[0], path[1]), 
            amounts[0]
        );

        // find and replace to addresses
        if (to == Constants.MSG_SENDER) to = msg.sender;
        else if (to == Constants.ADDRESS_THIS) to = address(this);

        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = ThrusterV2Library.getAmountsIn(factoryV2, amountOut, path);
        require(amounts[0] <= amountInMax, "ThrusterRouter: EXCESSIVE_INPUT_AMOUNT");
        pay(
            path[0], msg.sender, ThrusterV2Library.pairFor(factoryV2, path[0], path[1]), amounts[0]
        );

        // find and replace to addresses
        if (to == Constants.MSG_SENDER) to = msg.sender;
        else if (to == Constants.ADDRESS_THIS) to = address(this);

        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "ThrusterRouter: INVALID_PATH");
        amounts = ThrusterV2Library.getAmountsIn(factoryV2, amountOut, path);
        require(amounts[0] <= amountInMax, "ThrusterRouter: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, ThrusterV2Library.pairFor(factoryV2, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);

        // find and replace to addresses
        if (to == Constants.MSG_SENDER) to = msg.sender;
        else if (to == Constants.ADDRESS_THIS) to = address(this);

        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "ThrusterRouter: INVALID_PATH");

        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        bool hasAlreadyPaid;
        if (amountIn == Constants.CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            amountIn = IERC20(path[0]).balanceOf(address(this));
        }

        amounts = ThrusterV2Library.getAmountsOut(factoryV2, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "ThrusterRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        pay(
            path[0], 
            hasAlreadyPaid ? address(this) : msg.sender, 
            ThrusterV2Library.pairFor(factoryV2, path[0], path[1]), 
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);

        // find and replace to addresses
        if (to == Constants.MSG_SENDER) to = msg.sender;
        else if (to == Constants.ADDRESS_THIS) to = address(this);

        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = ThrusterV2Library.sortTokens(input, output);
            IThrusterPair pair = IThrusterPair(ThrusterV2Library.pairFor(factoryV2, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) =
                    input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = ThrusterV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? ThrusterV2Library.pairFor(factoryV2, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        bool hasAlreadyPaid;
        if (amountIn == Constants.CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            amountIn = IERC20(path[0]).balanceOf(address(this));
        }

        pay(
            path[0], 
            hasAlreadyPaid ? address(this) : msg.sender, 
            ThrusterV2Library.pairFor(factoryV2, path[0], path[1]), 
            amountIn
        );

        // find and replace to addresses
        if (to == Constants.MSG_SENDER) to = msg.sender;
        else if (to == Constants.ADDRESS_THIS) to = address(this);
        
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            "ThrusterRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WETH, "ThrusterRouter: INVALID_PATH");

        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        bool hasAlreadyPaid;
        if (amountIn == Constants.CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            amountIn = IERC20(path[0]).balanceOf(address(this));
        }

        pay(
            path[0], 
            hasAlreadyPaid ? address(this) : msg.sender, 
            ThrusterV2Library.pairFor(factoryV2, path[0], path[1]), 
            amountIn
        );

        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, "ThrusterRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(WETH).withdraw(amountOut);

        // find and replace to addresses
        if (to == Constants.MSG_SENDER) to = msg.sender;
        else if (to == Constants.ADDRESS_THIS) to = address(this);
        
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        virtual
        override
        returns (uint256 amountB)
    {
        return ThrusterV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return ThrusterV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountIn)
    {
        return ThrusterV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return ThrusterV2Library.getAmountsOut(factoryV2, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return ThrusterV2Library.getAmountsIn(factoryV2, amountOut, path);
    }
}