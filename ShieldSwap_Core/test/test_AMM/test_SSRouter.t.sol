// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {SSFactory} from "../../src/AMM_Part/SSFactory.sol";
import {SSRouter} from "../../src/AMM_Part/SSRouter.sol";
import {SSPair} from "../../src/AMM_Part/SSPair.sol";

import {MockERC20} from "./mocks/MockERC20.sol";

contract SSRouterTest is Test {
    SSFactory factory;
    SSRouter router;
    SSPair pair;

    MockERC20 tokenA;
    MockERC20 tokenB;

    address alice = address(0xA11);
    address alice1 = address(0xA12);

    function setUp() public {
        tokenA = new MockERC20("TokenA", "A");
        tokenB = new MockERC20("TokenB", "B");

        factory = new SSFactory();
        router = new SSRouter(address(factory));

        address pairAddr =
            factory.createPair(
                address(tokenA),
                address(tokenB)
            );

        pair = SSPair(pairAddr);

        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);

        vm.startPrank(alice);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function testAddLiquidityExact() public {
        vm.startPrank(alice);

        (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        ) =
            router.addLiquidity(
                address(tokenA),
                address(tokenB),
                10_000 ether,
                10_000 ether,
                10_000 ether,
                10_000 ether,
                alice
            );

        vm.stopPrank();

        assertEq(amountA, 10_000 ether);
        assertEq(amountB, 10_000 ether);

        assertEq(
            pair.balanceOf(alice) + pair.balanceOf(address(0)),
            liquidity + pair.balanceOf(address(0))
        );
        console2.log(liquidity);

        (uint112 r0, uint112 r1,) = pair.getReserves();

        if (pair.token0() == address(tokenA)) {
            assertEq(r0, 10_000 ether);
            assertEq(r1, 10_000 ether);
        } else {
            assertEq(r1, 10_000 ether);
            assertEq(r0, 10_000 ether);
        }
    }


    function testAddLiquidityUsesOptimalAmounts() public {
    // Alice seeds pool with perfect ratio
    vm.prank(alice);

    router.addLiquidity(
        address(tokenA),
        address(tokenB),
        10_000 ether,
        10_000 ether,
        0,
        0,
        alice
    );

    // Bob has skewed amounts
    address bob = address(0xB0B);

    tokenA.mint(bob, 5_000 ether);
    tokenB.mint(bob, 50_000 ether);

    vm.startPrank(bob);

    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    // Bob *wants* to add 5k A + 50k B
    // Pool ratio is 1:1 → router should only use:
    // 5k A + 5k B

    (
        uint256 usedA,
        uint256 usedB,
        uint256 liquidity
    ) =
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            5_000 ether,
            50_000 ether,
            5_000 ether,
            5_000 ether,
            bob
        );

    vm.stopPrank();

    // Router must only consume optimal amounts
    assertEq(usedA, 5_000 ether);
    assertEq(usedB, 5_000 ether);

    // Bob should still have excess tokenB
    assertEq(
        tokenB.balanceOf(bob),
        50_000 ether - 5_000 ether
    );

    assertEq(pair.totalSupply(),15000 ether );
    assertEq(pair.balanceOf(bob),5000 ether);
    assertEq(pair.balanceOf(alice),9999.999999999999999000 ether);
    assertEq(pair.balanceOf(address(0)),1000 );

    // Reserves should now be 15k / 15k
    (uint112 r0, uint112 r1,) = pair.getReserves();

    if (pair.token0() == address(tokenA)) {
        assertEq(r0, 15_000 ether);
        assertEq(r1, 15_000 ether);
    } else {
        assertEq(r1, 15_000 ether);
        assertEq(r0, 15_000 ether);
    }
}


    /*//////////////////////////////////////////////////////////////
                        SWAP EXACT TOKENS
    //////////////////////////////////////////////////////////////*/

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return
            (amountInWithFee * reserveOut) /
            (reserveIn * 1000 + amountInWithFee);
    }

    function testSwapExactTokensForTokens() public {
        vm.prank(alice);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            50_000 ether,
            50_000 ether,
            0,
            0,
            alice
        );

        address token0 = pair.token0();

        (uint112 r0, uint112 r1,) = pair.getReserves();

        uint256 amountIn = 1_000 ether;

        uint256 expectedOut;

        vm.startPrank(alice);

        if (token0 == address(tokenA)) {
            expectedOut =
                _getAmountOut(
                    amountIn,
                    r0,
                    r1
                );

            router.swapExactTokensForTokens(
                address(tokenA),
                address(tokenB),
                amountIn,
                expectedOut,
                alice
            );

            assertEq(
                tokenB.balanceOf(alice),
                1_000_000 ether -
                    50_000 ether +
                    expectedOut
            );
        } else {
            expectedOut =
                _getAmountOut(
                    amountIn,
                    r1,
                    r0
                );

            router.swapExactTokensForTokens(
                address(tokenB),
                address(tokenA),
                amountIn,
                expectedOut,
                alice
            );

            assertEq(
                tokenA.balanceOf(alice),
                1_000_000 ether -
                    50_000 ether +
                    expectedOut
            );
        }

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SLIPPAGE REVERT
    //////////////////////////////////////////////////////////////*/

    function testSwapRevertsOnSlippage() public {
        vm.prank(alice);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            20_000 ether,
            20_000 ether,
            0,
            0,
            alice
        );

        vm.startPrank(alice);

        vm.expectRevert();

        router.swapExactTokensForTokens(
            address(tokenA),
            address(tokenB),
            1_000 ether,
            10_000 ether, // impossible min
            alice
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function testRemoveLiquidity() public {
        vm.prank(alice);

        (
            ,
            ,
            uint256 liquidity
        ) =
            router.addLiquidity(
                address(tokenA),
                address(tokenB),
                30_000 ether,
                30_000 ether,
                0,
                0,
                alice
            );

        vm.startPrank(alice);

        pair.approve(
            address(router),
            liquidity
        );

        (
            uint256 amtA,
            uint256 amtB
        ) =
            router.removeLiquidity(
                address(tokenA),
                address(tokenB),
                liquidity,
                alice
            );

        vm.stopPrank();

        assertGt(amtA, 29_000 ether);
        assertGt(amtB, 29_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        GETPAIR CHECK
    //////////////////////////////////////////////////////////////*/

    function testRouterGetPair() public {
        address p =
            router.getPair(
                address(tokenA),
                address(tokenB)
            );

        assertEq(p, address(pair));
    }


    function testSandwichAttackSimulation() public {
    address bob = alice;
    address eve = alice1;

    // Give them funds
    tokenA.mint(bob, 10_000 ether);
    tokenB.mint(bob, 10_000 ether);

    tokenA.mint(eve, 10_000 ether);
    tokenB.mint(eve, 10_000 ether);

    vm.startPrank(bob);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);
    vm.stopPrank();

    vm.startPrank(eve);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);
    vm.stopPrank();

    // Alice seeds pool
    vm.prank(alice);
    router.addLiquidity(
        address(tokenA),
        address(tokenB),
        100_000 ether,
        100_000 ether,
        0,
        0,
        alice
    );

    // -----------------------------
    // Eve front-runs (A → B)
    // -----------------------------

    vm.startPrank(eve);

    uint256 eveAStart = tokenA.balanceOf(eve);

    router.swapExactTokensForTokens(
        address(tokenA),
        address(tokenB),
        5_000 ether,
        0,
        eve
    );

    vm.stopPrank();

    // -----------------------------
    // Bob victim trade (A → B)
    // -----------------------------

    vm.startPrank(bob);

    uint256 bobAStart = tokenA.balanceOf(bob);

    router.swapExactTokensForTokens(
        address(tokenA),
        address(tokenB),
        2_000 ether,
        0,
        bob
    );

    vm.stopPrank();

    // -----------------------------
    // Eve back-runs (B → A)
    // -----------------------------

    vm.startPrank(eve);

    uint256 eveB = tokenB.balanceOf(eve);

    router.swapExactTokensForTokens(
        address(tokenB),
        address(tokenA),
        eveB,
        0,
        eve
    );

    vm.stopPrank();

    // -----------------------------
    // ASSERTIONS
    // -----------------------------

    uint256 eveAEnd = tokenA.balanceOf(eve);
    uint256 bobAEnd = tokenA.balanceOf(bob);

    // Eve profited
    assertGt(eveAEnd, eveAStart);

    // Bob paid more A than expected
    assertLt(bobAEnd, bobAStart - 1_000 ether);
}

function testReservesUpdateAfterSwap() public {
    // Seed pool with known liquidity
    vm.prank(alice);

    router.addLiquidity(
        address(tokenA),
        address(tokenB),
        20_000 ether,
        20_000 ether,
        0,
        0,
        alice
    );

    address token0 = pair.token0();

    // Snapshot reserves BEFORE
    (uint112 r0Before, uint112 r1Before,) = pair.getReserves();
    console2.log(r0Before);
    console2.log(r1Before);

    uint256 amountIn = 1_000 ether;

    // Compute expected out
    uint256 expectedOut;

    if (token0 == address(tokenA)) {
        expectedOut = _getAmountOut(
            amountIn,
            r0Before,
            r1Before
        );

        vm.prank(alice);

        router.swapExactTokensForTokens(
            address(tokenA),
            address(tokenB),
            amountIn,
            expectedOut,
            alice
        );
    } else {
        expectedOut = _getAmountOut(
            amountIn,
            r1Before,
            r0Before
        );

        vm.prank(alice);

        router.swapExactTokensForTokens(
            address(tokenB),
            address(tokenA),
            amountIn,
            expectedOut,
            alice
        );
    }

    // Snapshot reserves AFTER
    (uint112 r0After, uint112 r1After,) = pair.getReserves();
    console2.log(r0After,r1After);

    // ----- EXACT ASSERTIONS -----
    
    console2.log(token0);
    console2.log(address(tokenA));
    
    assertEq(r0After, r0Before + amountIn);
    assertEq(r1After, r1Before - expectedOut);
    
}


}
