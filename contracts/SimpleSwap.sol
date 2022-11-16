// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/Math.sol";
import "./libraries/SafeMath.sol";
import "hardhat/console.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    using SafeMath for uint256;

    address public token0;
    address public token1;

    uint256 private reserve0;
    uint256 private reserve1;

    constructor(address _tokenA, address _tokenB) ERC20("SimpleSwap", "SSP") {
        bytes memory codeA = _tokenA.code;
        bytes memory codeB = _tokenB.code;
        require(codeA.length > 0, "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(codeB.length > 0, "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");

        (token0, token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    }

    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param tokenIn The address of the token to swap from
    /// @param tokenOut The address of the token to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external override returns (uint256 amountOut) {
        require(tokenIn == token0 || tokenIn == token1, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == token0 || tokenOut == token1, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        //check which is token0 & token1
        if (tokenIn < tokenOut) {
            amountOut = _swap(token0, token1, amountIn);
        } else {
            amountOut = _swap(token1, token0, amountIn);
        }

        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        _updateReserve();

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Add liquidity to the pool
    /// @param amountAIn The amount of tokenA to add
    /// @param amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    /// @return liquidity The amount of liquidity minted
    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external
        override
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(amountAIn > 0 && amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // transferFrom
        IERC20(token0).transferFrom(msg.sender, address(this), amountAIn);
        IERC20(token1).transferFrom(msg.sender, address(this), amountBIn);

        // liquidity
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountAIn.mul(amountBIn));
            (amountA, amountB) = (amountAIn, amountBIn);
        } else {
            liquidity = Math.min(amountAIn.mul(_totalSupply) / reserve0, amountBIn.mul(_totalSupply) / reserve1);
            //return more token
            (amountA, amountB) = returnMoreToken(amountAIn, amountBIn, liquidity);
        }

        // transfer liquidity to msg.sender
        _mint(msg.sender, liquidity);

        // event
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);

        // // change reserve = balance
        // reserve0 = IERC20(token0).balanceOf(address(this));
        // reserve1 = IERC20(token1).balanceOf(address(this));
        _updateReserve();
    }

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of liquidity to remove
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    function removeLiquidity(uint256 liquidity) external override returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        // transfer user liquidity to this contract
        _transfer(msg.sender, address(this), liquidity);

        //effect
        uint256 _totalSupply = totalSupply();
        amountA = (liquidity * reserve0) / _totalSupply;
        amountB = (liquidity * reserve1) / _totalSupply;

        _burn(address(this), liquidity);

        //interaction
        IERC20(token0).transfer(msg.sender, amountA);
        IERC20(token1).transfer(msg.sender, amountB);

        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Get the reserves of the pool
    /// @return reserveA The reserve of tokenA
    /// @return reserveB The reserve of tokenB
    function getReserves() external view override returns (uint256 reserveA, uint256 reserveB) {
        reserveA = reserve0;
        reserveB = reserve1;
    }

    /// @notice Get the address of tokenA
    /// @return tokenA The address of tokenA
    function getTokenA() external view override returns (address tokenA) {
        tokenA = token0;
    }

    /// @notice Get the address of tokenB
    /// @return tokenB The address of tokenB
    function getTokenB() external view override returns (address tokenB) {
        tokenB = token1;
    }

    function returnMoreToken(
        uint256 amountAIn,
        uint256 amountBIn,
        uint256 liquidity
    ) internal returns (uint256 amountA, uint256 amountB) {
        uint256 _totalSupply = totalSupply();

        uint256 hypotheticalAToken = (amountBIn * reserve0) / reserve1; //以B為主，計算A的數量
        uint256 hypotheticalBToken = (amountAIn * reserve1) / reserve0; //以A為主，計算B的數量

        if (amountBIn > hypotheticalBToken) {
            //以A為主，歸還B
            uint256 actualAmount = ((reserve1 * amountAIn) / reserve0);
            uint256 returnToken = amountBIn - actualAmount;

            IERC20(token1).transfer(msg.sender, returnToken);

            return (amountAIn, actualAmount);
        } else if (amountAIn > hypotheticalAToken) {
            // 以B為主，歸還A
            uint256 actualAmount = ((reserve0 * amountBIn) / reserve1);
            uint256 returnToken = amountAIn - actualAmount;

            IERC20(token0).transfer(msg.sender, returnToken);

            return (actualAmount, amountBIn);
        } else {
            return (amountAIn, amountBIn);
        }
    }

    function _swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        //transferFrom token to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // effect
        amountOut = (reserve1 * amountIn) / (amountIn + reserve0);

        uint256 adjustToken0 = reserve0 + amountIn;
        uint256 adjustToken1 = reserve1 - amountOut;

        require(adjustToken0 * adjustToken1 >= reserve0 * reserve1, "SimpleSwap: K");

        // interaction
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }

    function _updateReserve() internal {
        // change reserve = balance
        reserve0 = IERC20(token0).balanceOf(address(this));
        reserve1 = IERC20(token1).balanceOf(address(this));
    }
}
