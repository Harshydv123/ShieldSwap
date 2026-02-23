// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/AMM_Part/SSERC20.sol";

contract SSERC20Test is Test {
    SSERC20 lp;

    address pair = address(0x111);
    address alice = address(0xAAA);
    address bob   = address(0xBBB);

    function setUp() public {
        lp = new SSERC20(
            "ShieldSwap LP Token",
            "SSLP",
            pair
        );
    }

    /*//////////////////////////////////////////////////////////////
                            MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function testPairCanMint1() public {
        vm.prank(pair);

        lp.mint(alice, 100 ether);

        assertEq(lp.balanceOf(alice), 100 ether);
        assertEq(lp.totalSupply(), 100 ether);
    }

    function testPairCanMint2() public {
        vm.prank(pair);

        lp.mint(alice, 60 ether);

        assertEq(lp.balanceOf(alice), 60 ether);
        assertEq(lp.totalSupply(), 60 ether);
    }

    function testNonPairCannotMint() public {
        vm.prank(alice);
        vm.expectRevert(SSERC20.LPNotPair.selector);

        lp.mint(alice, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function testPairCanBurn() public {
        vm.prank(pair);
        lp.mint(alice, 100 ether);

        vm.prank(pair);
        lp.burn(alice, 40 ether);

        assertEq(lp.balanceOf(alice), 60 ether);
        assertEq(lp.totalSupply(), 60 ether);
    }

    function testBurnTooMuchReverts() public {
        vm.prank(pair);
        lp.mint(alice, 10 ether);

        vm.prank(pair);
        vm.expectRevert(SSERC20.LPInsufficientBalance.selector);

        lp.burn(alice, 20 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransfer() public {
        vm.prank(pair);
        lp.mint(alice, 50 ether);

        vm.prank(alice);
        lp.transfer(bob, 20 ether);

        assertEq(lp.balanceOf(alice), 30 ether);
        assertEq(lp.balanceOf(bob), 20 ether);
    }

    function testTransferInsufficientBalance() public {
        vm.prank(pair);
        lp.mint(alice, 10 ether);

        vm.prank(alice);
        vm.expectRevert(SSERC20.LPInsufficientBalance.selector);

        lp.transfer(bob, 20 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        APPROVE / TRANSFERFROM
    //////////////////////////////////////////////////////////////*/

    function testApproveAndTransferFrom() public {
        vm.prank(pair);
        lp.mint(alice, 100 ether);

        vm.prank(alice);
        lp.approve(bob, 40 ether);

        vm.prank(bob);
        lp.transferFrom(alice, bob, 25 ether);

        assertEq(lp.balanceOf(alice), 75 ether);
        assertEq(lp.balanceOf(bob), 25 ether);
        assertEq(lp.allowance(alice, bob), 15 ether);
    }

    function testTransferFromExceedsAllowance() public {
        vm.prank(pair);
        lp.mint(alice, 50 ether);

        vm.prank(alice);
        lp.approve(bob, 10 ether);

        vm.prank(bob);
        vm.expectRevert(SSERC20.LPInsufficientAllowance.selector);

        lp.transferFrom(alice, bob, 20 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        ZERO ADDRESS GUARDS
    //////////////////////////////////////////////////////////////*/

    function testTransferToZeroReverts() public {
        vm.prank(pair);
        lp.mint(alice, 10 ether);

        vm.prank(alice);
        vm.expectRevert(SSERC20.LPZeroAddress.selector);

        lp.transfer(address(0), 1 ether);
    }

}
