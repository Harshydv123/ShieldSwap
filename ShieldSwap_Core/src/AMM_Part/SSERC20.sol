// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Interfaces/ISSERC20.sol";

contract SSERC20 is ISSERC20 {
    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    error LPNotPair();
    error LPInsufficientBalance();
    error LPInsufficientAllowance();
    error LPZeroAddress();

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    string public override name;
    string public override symbol;

    uint8 public constant override decimals = 18;

    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    address public immutable pair;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyPair() {
        if (msg.sender != pair) revert LPNotPair();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        address _pair
    ) {
        name = _name;
        symbol = _symbol;
        pair = _pair;
    }

    /*//////////////////////////////////////////////////////////////
                           ERC20 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 value)
        external
        override
        returns (bool)
    {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max) {
            if (allowed < value) revert LPInsufficientAllowance();
            allowance[from][msg.sender] = allowed - value;
        }

        _transfer(from, to, value);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL TRANSFER
    //////////////////////////////////////////////////////////////*/

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        if (to == address(0)) revert LPZeroAddress();

        uint256 bal = balanceOf[from];
        if (bal < value) revert LPInsufficientBalance();

        unchecked {
            balanceOf[from] = bal - value;
            balanceOf[to] += value;
        }

        emit Transfer(from, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                         MINT / BURN (PAIR ONLY)
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;

        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        uint256 bal = balanceOf[from];
        if (bal < value) revert LPInsufficientBalance();

        unchecked {
            balanceOf[from] = bal - value;
            totalSupply -= value;
        }

        emit Transfer(from, address(0), value);
    }

    /*//////////////////////////////////////////////////////////////
                   EXTERNAL HOOKS FOR PAIR CONTRACT
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 value) external onlyPair {
        _mint(to, value);
    }

    function burn(address from, uint256 value) external onlyPair {
        _burn(from, value);
    }
}
