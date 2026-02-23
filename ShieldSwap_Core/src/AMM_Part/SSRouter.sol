// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISSRouter} from "./Interfaces/ISSRouter.sol";
import {SSFactory} from "./SSFactory.sol";
import {SSPair} from "./SSPair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract SSRouter is ISSRouter {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error PairNotFound();
    error SlippageExceeded();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable override factory;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _factory) {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    function getPair(address tokenA, address tokenB)
        public
        view
        override
        returns (address pair)
    {
        pair = SSFactory(factory).getPair(tokenA, tokenB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    )
        public
        pure
        override
        returns (uint256 amountOut)
    {
        uint256 amountInWithFee = amountIn * 997;
        amountOut =
            (amountInWithFee * reserveOut) /
            (reserveIn * 1000 + amountInWithFee);
    }

    /*//////////////////////////////////////////////////////////////
                          ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    )
        external
        override
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        address pairAddr = getPair(tokenA, tokenB);
        if (pairAddr == address(0)) revert PairNotFound();

        SSPair pair = SSPair(pairAddr);

        (uint112 r0, uint112 r1,) = pair.getReserves();

        address token0 = pair.token0();

        if (tokenA == token0) {
            (amountA, amountB) =
                _quoteLiquidity(
                    amountADesired,
                    amountBDesired,
                    r0,
                    r1
                );
        } else {
            (amountB, amountA) =
                _quoteLiquidity(
                    amountBDesired,
                    amountADesired,
                    r0,
                    r1
                );
        }

        if (amountA < amountAMin || amountB < amountBMin)
            revert SlippageExceeded();

        IERC20(tokenA).transferFrom(
            msg.sender,
            pairAddr,
            amountA
        );
        IERC20(tokenB).transferFrom(
            msg.sender,
            pairAddr,
            amountB
        );

        liquidity = pair.mint(to);
    }

    function _quoteLiquidity(
        uint256 amtA,
        uint256 amtB,
        uint112 rA,
        uint112 rB
    )
        internal
        pure
        returns (uint256 outA, uint256 outB)
    {
        if (rA == 0 && rB == 0) {
            return (amtA, amtB);
        }

        uint256 optimalB = (amtA * rB) / rA;

        if (optimalB <= amtB) {
            return (amtA, optimalB);
        }

        uint256 optimalA = (amtB * rA) / rB;

        return (optimalA, amtB);
    }

    /*//////////////////////////////////////////////////////////////
                        REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        address to
    )
        external
        override
        returns (
            uint256 amountA,
            uint256 amountB
        )
    {
        address pairAddr = getPair(tokenA, tokenB);
        if (pairAddr == address(0)) revert PairNotFound();

        SSPair pair = SSPair(pairAddr);

        pair.transferFrom(
            msg.sender,
            pairAddr,
            liquidity
        );

        (uint256 amt0, uint256 amt1) =
            pair.burn(to);

        if (tokenA == pair.token0()) {
            (amountA, amountB) = (amt0, amt1);
        } else {
            (amountA, amountB) = (amt1, amt0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          SWAP EXACT IN
    //////////////////////////////////////////////////////////////*/

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    )
        external
        override
        returns (uint256 amountOut)
    {
        address pairAddr = getPair(tokenIn, tokenOut);
        if (pairAddr == address(0)) revert PairNotFound();

        SSPair pair = SSPair(pairAddr);

        (uint112 r0, uint112 r1,) = pair.getReserves();

        bool zeroForOne =
            tokenIn == pair.token0();

        (uint256 reserveIn, uint256 reserveOut) =
            zeroForOne
                ? (r0, r1)
                : (r1, r0);

        amountOut = getAmountOut(
            amountIn,
            reserveIn,
            reserveOut
        );

        if (amountOut < amountOutMin)
            revert SlippageExceeded();

        IERC20(tokenIn).transferFrom(
            msg.sender,
            pairAddr,
            amountIn
        );

        if (zeroForOne) {
            pair.swap(0, amountOut, to);
        } else {
            pair.swap(amountOut, 0, to);
        }
    }
}
