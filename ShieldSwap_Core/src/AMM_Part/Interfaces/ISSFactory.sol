// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IShieldSwapFactory {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair
    );

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    /*//////////////////////////////////////////////////////////////
                          STATE-CHANGING
    //////////////////////////////////////////////////////////////*/

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}
