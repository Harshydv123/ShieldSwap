// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISSRouter {
    /*//////////////////////////////////////////////////////////////
                                LIQUIDITY
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
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        address to
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB
        );

    /*//////////////////////////////////////////////////////////////
                                  SWAPS
    //////////////////////////////////////////////////////////////*/

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    )
        external
        returns (uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                                VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    function factory() external view returns (address);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    )
        external
        pure
        returns (uint256 amountOut);
}
