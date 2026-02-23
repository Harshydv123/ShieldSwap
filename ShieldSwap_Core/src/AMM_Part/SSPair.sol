// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Interfaces/ISSPair.sol";
import "./SSERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract SSPair is ISSPair, SSERC20 {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Locked();
    error Forbidden();
    error InsufficientLiquidity();
    error InsufficientOutput();
    error InsufficientInput();
    error InvalidTo();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MINIMUM_LIQUIDITY = 1_000;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    address public override factory;
    address public override token0;
    address public override token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32  private blockTimestampLast;

    uint256 private unlocked = 1;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier lock() {
        if (unlocked != 1) revert Locked();
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor()
        SSERC20("ShieldSwap LP", "SSLP", address(this))
    {
        factory = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZE
    //////////////////////////////////////////////////////////////*/

    function initialize(address _token0, address _token1) external override {
        if (msg.sender != factory) revert Forbidden();

        token0 = _token0;
        token1 = _token1;
    }

    /*//////////////////////////////////////////////////////////////
                              RESERVES
    //////////////////////////////////////////////////////////////*/

    function getReserves()
        public
        view
        override
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);

        emit Sync(reserve0, reserve1);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT
    //////////////////////////////////////////////////////////////*/

    function mint(address to)
        external
        override
        lock
        returns (uint256 liquidity)
    {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply;

        if (_totalSupply == 0) {
            liquidity =
                _sqrt(amount0 * amount1) -
                MINIMUM_LIQUIDITY;

            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = _min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }

        if (liquidity == 0) revert InsufficientLiquidity();

        _mint(to, liquidity);

        _update(balance0, balance1);

        emit Mint(msg.sender, amount0, amount1);
    }

    /*//////////////////////////////////////////////////////////////
                              BURN
    //////////////////////////////////////////////////////////////*/

    function burn(address to)
        external
        override
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply;

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();

        _burn(address(this), liquidity);

        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1);

        emit Burn(msg.sender, amount0, amount1, to);
    }

    /*//////////////////////////////////////////////////////////////
                              SWAP
    //////////////////////////////////////////////////////////////*/

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external override lock {
        if (amount0Out == 0 && amount1Out == 0)
            revert InsufficientOutput();

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        if (amount0Out >= _reserve0 || amount1Out >= _reserve1)
            revert InsufficientLiquidity();

        if (to == token0 || to == token1) revert InvalidTo();

        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In =
            balance0 > _reserve0 - amount0Out
                ? balance0 - (_reserve0 - amount0Out)
                : 0;

        uint256 amount1In =
            balance1 > _reserve1 - amount1Out
                ? balance1 - (_reserve1 - amount1Out)
                : 0;

        if (amount0In == 0 && amount1In == 0)
            revert InsufficientInput();

        // 0.3% LP fee (997 / 1000)
        uint256 balance0Adjusted =
            balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted =
            balance1 * 1000 - amount1In * 3;

        if (
            balance0Adjusted * balance1Adjusted <
            uint256(_reserve0) *
                uint256(_reserve1) *
                1000 *
                1000
        ) revert InsufficientLiquidity();

        _update(balance0, balance1);

        emit Swap(
            msg.sender,
            amount0In,
            amount1In,
            amount0Out,
            amount1Out,
            to
        );
    }

    /*//////////////////////////////////////////////////////////////
                              SYNC
    //////////////////////////////////////////////////////////////*/

    function sync() external override lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this))
        );
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        bool success = IERC20(token).transfer(to, value);
        require(success, "TRANSFER_FAILED");
    }

    function _min(uint256 x, uint256 y)
        private
        pure
        returns (uint256)
    {
        return x < y ? x : y;
    }

    function _sqrt(uint256 y)
        private
        pure
        returns (uint256 z)
    {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
