// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Interfaces/ISSFactory.sol";
import "./SSPair.sol";

contract SSFactory is IShieldSwapFactory {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(address => address)) public override getPair;

    address[] public allPairs;

    /*//////////////////////////////////////////////////////////////
                               VIEW
    //////////////////////////////////////////////////////////////*/

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /*//////////////////////////////////////////////////////////////
                          PAIR CREATION
    //////////////////////////////////////////////////////////////*/

    function createPair(address tokenA, address tokenB)
        external
        override
        returns (address pair)
    {
        if (tokenA == tokenB) revert IdenticalAddresses();

        (address token0, address token1) =
            tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        if (token0 == address(0)) revert ZeroAddress();

        if (getPair[token0][token1] != address(0)) revert PairExists();

        bytes memory bytecode = type(SSPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
            if iszero(pair) {
                revert(0, 0)
            }
        }

        SSPair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        allPairs.push(pair);

        emit PairCreated(token0, token1, pair);
    }
}
