// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/Privacy_Part/ShieldPool.sol";
import "../../src/Privacy_Part/MerkleTreeWithHistory.sol";
import "../../src/Privacy_Part/DummyVerifier.sol";
import "../../src/AMM_Part/SSFactory.sol";
import "../../src/AMM_Part/SSRouter.sol";
import "../../src/AMM_Part/SSPair.sol";

/**
 * @title AMM_ShieldPool_IntegrationTest
 * @notice FOCUSED integration tests for AMM + ShieldPool interaction
 * @dev Assumes AMM and ShieldPool work individually, tests them TOGETHER
 *
 * What We Test:
 * 1. ShieldPool can call SSRouter successfully
 * 2. Swaps via privacy layer update AMM reserves correctly
 * 3. Multiple privacy withdrawals don't break AMM state
 * 4. Relayer fees work with AMM swaps
 * 5. Slippage protection works through privacy layer
 * 6. Different token pairs work with privacy swaps
 */
contract AMM_ShieldPool_IntegrationTest is Test {
    // ============ Contracts ============
    SSFactory public factory;
    SSRouter public router;
    SSPair public usdcDaiPair;
    SSPair public usdcUsdtPair;

    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public usdt;

    ShieldPool public usdcPool100;
    ShieldPool public daiPool100;
    DummyVerifier public verifier;
    MockHasher public hasher;

    // ============ Test Actors ============
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);
    address relayer = address(0x2E1A7E2);

    // ============ Constants ============
    uint256 constant USDC_100 = 100 * 10 ** 18; // 100 USDC (18 decimals)
    uint256 constant DAI_100 = 100 * 10 ** 18; // 100 DAI (18 decimals)
    uint256 constant USDT_100 = 100 * 10 ** 18; // 100 USDT (18 decimals)

    uint256 constant POOL_LIQUIDITY_USDC = 10_000 * 10 ** 18; // 10k USDC
    uint256 constant POOL_LIQUIDITY_DAI = 10_000 * 10 ** 18; // 10k DAI
    uint256 constant POOL_LIQUIDITY_USDT = 10_000 * 10 ** 18; // 10k USDT

    uint256 constant FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    // ============ Events ============
    event SwapWithdrawal(
        address indexed recipient,
        bytes32 nullifierHash,
        address tokenOut,
        uint256 amountOut,
        address indexed relayer,
        uint256 fee
    );

    function setUp() public {
        // Label addresses for better trace output
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");
        vm.label(relayer, "Relayer");

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 18);
        dai = new MockERC20("Dai", "DAI", 18);
        usdt = new MockERC20("Tether", "USDT", 18);

        // Deploy AMM
        factory = new SSFactory();
        router = new SSRouter(address(factory));

        // Create pairs
        factory.createPair(address(usdc), address(dai));
        factory.createPair(address(usdc), address(usdt));

        usdcDaiPair = SSPair(factory.getPair(address(usdc), address(dai)));
        usdcUsdtPair = SSPair(factory.getPair(address(usdc), address(usdt)));

        // Deploy privacy infrastructure
        hasher = new MockHasher();
        verifier = new DummyVerifier();

        usdcPool100 = new ShieldPool(
            IERC20(address(usdc)),
            USDC_100,
            ISSRouter(address(router)),
            IVerifier(address(verifier)),
            IVerifier(address(verifier)),
            20, // tree levels
            IHasher(address(hasher))
        );

        daiPool100 = new ShieldPool(
            IERC20(address(dai)),
            DAI_100,
            ISSRouter(address(router)),
            IVerifier(address(verifier)),
            IVerifier(address(verifier)),
            20,
            IHasher(address(hasher))
        );

        // Mint tokens to users
        usdc.mint(alice, 1_000_000 * 10 ** 18);
        dai.mint(alice, 1_000_000 * 10 ** 18);
        usdt.mint(alice, 1_000_000 * 10 ** 18);

        usdc.mint(bob, 100_000 * 10 ** 18);
        dai.mint(bob, 100_000 * 10 ** 18);

        usdc.mint(carol, 100_000 * 10 ** 18);

        // Add liquidity to AMM (Alice is LP provider)
        vm.startPrank(alice);

        // USDC/DAI pair
        usdc.approve(address(router), POOL_LIQUIDITY_USDC);
        dai.approve(address(router), POOL_LIQUIDITY_DAI);
        router.addLiquidity(
            address(usdc),
            address(dai),
            POOL_LIQUIDITY_USDC,
            POOL_LIQUIDITY_DAI,
            (POOL_LIQUIDITY_USDC * 99) / 100,
            (POOL_LIQUIDITY_DAI * 99) / 100,
            alice
        );

        // USDC/USDT pair
        usdc.approve(address(router), POOL_LIQUIDITY_USDC);
        usdt.approve(address(router), POOL_LIQUIDITY_USDT);
        router.addLiquidity(
            address(usdc),
            address(usdt),
            POOL_LIQUIDITY_USDC,
            POOL_LIQUIDITY_USDT,
            (POOL_LIQUIDITY_USDC * 99) / 100,
            (POOL_LIQUIDITY_USDT * 99) / 100,
            alice
        );

        vm.stopPrank();

        console.log("=== Integration Test Setup Complete ===");
        console.log("USDC/DAI Pair:", address(usdcDaiPair));
        console.log("USDC/USDT Pair:", address(usdcUsdtPair));
        console.log("USDC ShieldPool:", address(usdcPool100));
        console.log("DAI ShieldPool:", address(daiPool100));
    }

    // ============ Helper Functions ============

    function _commitment(uint256 seed) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(keccak256(abi.encodePacked("commitment", seed))) % FIELD
            );
    }

    function _nullifier(uint256 seed) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(keccak256(abi.encodePacked("nullifier", seed))) % FIELD
            );
    }

    function _depositToPool(
        address user,
        ShieldPool pool,
        uint256 amount,
        uint256 seed
    ) internal {
        vm.startPrank(user);
        IERC20(pool.token()).approve(address(pool), amount);
        pool.deposit(_commitment(seed));
        vm.stopPrank();
    }

    /**
     * @notice Get reserves in a specific token order
     * @param pair The SSPair to query
     * @param tokenA The token whose reserve should be returned first
     * @return reserveA Reserve of tokenA
     * @return reserveB Reserve of the other token
     */
    function _getOrderedReserves(
        SSPair pair,
        address tokenA
    ) internal view returns (uint112 reserveA, uint112 reserveB) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();

        // If tokenA is token0, return (reserve0, reserve1)
        // Otherwise return (reserve1, reserve0)
        (reserveA, reserveB) = token0 == tokenA
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // ============================================================
    //                    INTEGRATION TESTS
    // ============================================================

    /**
     * TEST 1: Basic Integration - Deposit USDC, Withdraw as DAI
     *
     * Flow:
     * 1. Alice deposits 100 USDC to ShieldPool
     * 2. Alice withdraws to Bob's address as DAI (privacy + swap)
     * 3. Verify Bob receives DAI via AMM
     * 4. Verify AMM reserves updated correctly
     */
    function test_Integration_BasicSwapWithdraw() public {
    console.log("\n=== TEST 1: Basic Privacy Swap via AMM ===");
    
    // 1. Alice deposits USDC
    bytes32 commitment = _commitment(1);
    bytes32 nullifierHash = _nullifier(1);
    
    vm.startPrank(alice);
    usdc.approve(address(usdcPool100), USDC_100);
    usdcPool100.deposit(commitment);
    vm.stopPrank();
    
    console.log("Alice deposited 100 USDC to ShieldPool");
    
    // 2. Get AMM state before swap (using helper function)
    (uint112 usdcReserveBefore, uint112 daiReserveBefore) = _getOrderedReserves(usdcDaiPair, address(usdc));
    
    console.log("AMM Reserves Before - USDC:", usdcReserveBefore, "DAI:", daiReserveBefore);
    
    // 3. Calculate expected DAI output
    uint256 expectedDai = router.getAmountOut(USDC_100, usdcReserveBefore, daiReserveBefore);
    uint256 minDai = expectedDai * 99 / 100; // 1% slippage tolerance
    
    console.log("Expected DAI output:", expectedDai);
    
    // 4. Withdraw to Bob as DAI
    bytes32 root = usdcPool100.getLastRoot();
    uint256 bobDaiBefore = dai.balanceOf(bob);
    
    usdcPool100.swapAndWithdraw(
        "",                // dummy proof
        root,
        nullifierHash,
        bob,               // recipient (different from Alice!)
        address(dai),      // tokenOut (different from USDC!)
        minDai,
        address(0),        // no relayer
        0                  // no fee
    );
    
    uint256 bobDaiAfter = dai.balanceOf(bob);
    uint256 daiReceived = bobDaiAfter - bobDaiBefore;
    
    console.log("Bob received DAI:", daiReceived);
    
    // 5. Get AMM state after swap (using helper function)
    (uint112 usdcReserveAfter, uint112 daiReserveAfter) = _getOrderedReserves(usdcDaiPair, address(usdc));
    
    console.log("AMM Reserves After - USDC:", usdcReserveAfter, "DAI:", daiReserveAfter);
    
    // ============ Assertions ============
    
    // Privacy achieved: Bob received, not Alice
    assertTrue(daiReceived > 0, "Bob should receive non-zero DAI");
    assertTrue(daiReceived >= minDai, "Should meet slippage protection");
    
    // AMM reserves updated correctly
    assertEq(usdcReserveAfter, usdcReserveBefore + USDC_100, "USDC reserve should increase by 100");
    assertEq(daiReserveAfter, daiReserveBefore - daiReceived, "DAI reserve should decrease by output");
    
    // Pool emptied
    assertEq(usdcPool100.totalDeposits(), 0, "ShieldPool should be empty");
    
    // Nullifier marked used
    assertTrue(usdcPool100.nullifierHashes(nullifierHash), "Nullifier should be marked used");
    
    console.log(" Basic integration test PASSED");
}


    /**
     * TEST 2: Multiple Sequential Privacy Swaps
     *
     * Verify:
     * - Multiple privacy withdrawals work in sequence
     * - AMM reserves track correctly across multiple swaps
     * - No state corruption between operations
     */
    function test_Integration_MultipleSequentialSwaps() public {
        console.log("\n=== TEST 2: Multiple Sequential Privacy Swaps ===");

        // Setup: 3 users deposit USDC
        _depositToPool(alice, usdcPool100, USDC_100, 1);
        _depositToPool(bob, usdcPool100, USDC_100, 2);
        _depositToPool(carol, usdcPool100, USDC_100, 3);

        console.log("3 users deposited 100 USDC each (total: 300 USDC)");

        bytes32 root = usdcPool100.getLastRoot();

        // Track AMM state
        (uint112 usdcInitial, uint112 daiInitial ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        console.log(
            "Initial AMM Reserves - USDC:",
            usdcInitial,
            "DAI:",
            daiInitial
        );

        uint256 totalDaiOut = 0;

        // Swap 1: Alice's deposit to DAI for random address
        {
            address recipient1 = address(0x1111);
            (uint112 r0, uint112 r1 ) = _getOrderedReserves(usdcDaiPair, address(usdc));
            uint256 expectedOut = router.getAmountOut(USDC_100, r0, r1);

            usdcPool100.swapAndWithdraw(
                "",
                root,
                _nullifier(1),
                recipient1,
                address(dai),
                (expectedOut * 99) / 100,
                address(0),
                0
            );

            uint256 daiOut = dai.balanceOf(recipient1);
            totalDaiOut += daiOut;
            console.log("Swap 1: USDC -> DAI =", daiOut);
        }

        // Swap 2: Bob's deposit to DAI for different address
        {
            address recipient2 = address(0x2222);
            (uint112 r0, uint112 r1 ) = _getOrderedReserves(usdcDaiPair, address(usdc));
            uint256 expectedOut = router.getAmountOut(USDC_100, r0, r1);

            usdcPool100.swapAndWithdraw(
                "",
                root,
                _nullifier(2),
                recipient2,
                address(dai),
                (expectedOut * 99) / 100,
                address(0),
                0
            );

            uint256 daiOut = dai.balanceOf(recipient2);
            totalDaiOut += daiOut;
            console.log("Swap 2: USDC -> DAI =", daiOut);
        }

        // Swap 3: Carol's deposit to DAI for yet another address
        {
            address recipient3 = address(0x3333);
            (uint112 r0, uint112 r1 ) = _getOrderedReserves(usdcDaiPair, address(usdc));
            uint256 expectedOut = router.getAmountOut(USDC_100, r0, r1);

            usdcPool100.swapAndWithdraw(
                "",
                root,
                _nullifier(3),
                recipient3,
                address(dai),
                (expectedOut * 99) / 100,
                address(0),
                0
            );

            uint256 daiOut = dai.balanceOf(recipient3);
            totalDaiOut += daiOut;
            console.log("Swap 3: USDC -> DAI =", daiOut);
        }

        // Final AMM state
        (uint112 usdcFinal, uint112 daiFinal ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        console.log("Final AMM Reserves - USDC:", usdcFinal, "DAI:", daiFinal);

        // ============ Assertions ============

        // All USDC went into AMM
        assertEq(
            usdcFinal,
            usdcInitial + (USDC_100 * 3),
            "USDC reserve should increase by 300"
        );

        // DAI came out of AMM
        assertEq(
            daiFinal,
            daiInitial - totalDaiOut,
            "DAI reserve should decrease by total output"
        );

        // Pool is empty
        assertEq(usdcPool100.totalDeposits(), 0, "All deposits withdrawn");

        // All nullifiers marked used
        assertTrue(
            usdcPool100.nullifierHashes(_nullifier(1)),
            "Nullifier 1 used"
        );
        assertTrue(
            usdcPool100.nullifierHashes(_nullifier(2)),
            "Nullifier 2 used"
        );
        assertTrue(
            usdcPool100.nullifierHashes(_nullifier(3)),
            "Nullifier 3 used"
        );

        console.log("Total DAI out:", totalDaiOut);
        console.log("  Multiple sequential swaps PASSED");
    }

    /**
     * TEST 3: Privacy Swap with Relayer Fee
     *
     * Verify:
     * - Relayer fee deducted before swap
     * - Reduced amount swapped via AMM
     * - Relayer receives fee in original token
     * - Recipient receives swapped token
     */
    function test_Integration_SwapWithRelayerFee() public {
        console.log("\n=== TEST 3: Privacy Swap with Relayer Fee ===");

        // Alice deposits
        _depositToPool(alice, usdcPool100, USDC_100, 1);

        bytes32 root = usdcPool100.getLastRoot();
        uint256 fee = 2 * 10 ** 18; // 2 USDC fee
        uint256 swapAmount = USDC_100 - fee; // 98 USDC to swap

        // Calculate expected DAI
        (uint112 r0, uint112 r1 ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        uint256 expectedDai = router.getAmountOut(swapAmount, r0, r1);
        uint256 minDai = (expectedDai * 99) / 100;

        console.log("Fee:", fee, "USDC");
        console.log("Amount to swap:", swapAmount, "USDC");
        console.log("Expected DAI:", expectedDai);

        // Execute swap with fee
        uint256 relayerUsdcBefore = usdc.balanceOf(relayer);
        uint256 bobDaiBefore = dai.balanceOf(bob);

        usdcPool100.swapAndWithdraw(
            "",
            root,
            _nullifier(1),
            bob,
            address(dai),
            minDai,
            relayer,
            fee
        );

        uint256 relayerUsdcAfter = usdc.balanceOf(relayer);
        uint256 bobDaiAfter = dai.balanceOf(bob);

        uint256 relayerFeeReceived = relayerUsdcAfter - relayerUsdcBefore;
        uint256 bobDaiReceived = bobDaiAfter - bobDaiBefore;

        console.log("Relayer received:", relayerFeeReceived, "USDC");
        console.log("Bob received:", bobDaiReceived, "DAI");

        // ============ Assertions ============

        // Relayer got fee in USDC
        assertEq(relayerFeeReceived, fee, "Relayer should receive exact fee");

        // Bob got swapped DAI
        assertTrue(
            bobDaiReceived >= minDai,
            "Bob should receive at least minDai"
        );
        assertTrue(bobDaiReceived > 0, "Bob should receive DAI");

        // AMM only saw the swap amount (not the fee)
        (uint112 r0After, uint112 r1After ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        assertEq(r0After, r0 + swapAmount, "Only swap amount should go to AMM");
        assertEq(
            r1After,
            r1 - bobDaiReceived,
            "DAI out should match Bob's receipt"
        );

        console.log("  Relayer fee test PASSED");
    }

    /**
     * TEST 4: Cross-Pool Swaps (Different Pairs)
     *
     * Verify:
     * - USDC to DAI swap works
     * - USDC to USDT swap works
     * - Different pairs don't interfere
     */
    function test_Integration_DifferentPairSwaps() public {
        console.log("\n=== TEST 4: Cross-Pool Privacy Swaps ===");

        // Deposit 1: Alice deposits to USDC pool (will swap to DAI)
        _depositToPool(alice, usdcPool100, USDC_100, 1);

        // Deposit 2: Bob deposits to USDC pool (will swap to USDT)
        _depositToPool(bob, usdcPool100, USDC_100, 2);

        bytes32 root = usdcPool100.getLastRoot();

        // Get initial reserves for both pairs
        (
            uint112 usdcDai_USDC_Before,
            uint112 usdcDai_DAI_Before

        ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        (
            uint112 usdcUsdt_USDC_Before,
            uint112 usdcUsdt_USDT_Before

        ) = _getOrderedReserves(usdcUsdtPair, address(usdc));

        console.log(
            "USDC/DAI Pair - USDC:",
            usdcDai_USDC_Before,
            "DAI:",
            usdcDai_DAI_Before
        );
        console.log(
            "USDC/USDT Pair - USDC:",
            usdcUsdt_USDC_Before,
            "USDT:",
            usdcUsdt_USDT_Before
        );

        // Swap 1: USDC to DAI
        {
            address recipient1 = address(0xAAAA);
            uint256 expectedDai = router.getAmountOut(
                USDC_100,
                usdcDai_USDC_Before,
                usdcDai_DAI_Before
            );

            usdcPool100.swapAndWithdraw(
                "",
                root,
                _nullifier(1),
                recipient1,
                address(dai),
                (expectedDai * 99) / 100,
                address(0),
                0
            );

            uint256 daiReceived = dai.balanceOf(recipient1);
            console.log("Swap 1: USDC -> DAI =", daiReceived);

            // Check only USDC/DAI pair affected
            (uint112 r0, uint112 r1 ) = _getOrderedReserves(usdcDaiPair, address(usdc));
            assertEq(
                r0,
                usdcDai_USDC_Before + USDC_100,
                "USDC/DAI USDC reserve updated"
            );
            assertEq(
                r1,
                usdcDai_DAI_Before - daiReceived,
                "USDC/DAI DAI reserve updated"
            );

            // USDC/USDT pair unchanged
            (uint112 r2, uint112 r3 ) = _getOrderedReserves(usdcUsdtPair, address(usdc));
            assertEq(r2, usdcUsdt_USDC_Before, "USDC/USDT pair unchanged");
            assertEq(r3, usdcUsdt_USDT_Before, "USDC/USDT pair unchanged");
        }

        // Swap 2: USDC to USDT
        {
            address recipient2 = address(0xBBBB);
            uint256 expectedUsdt = router.getAmountOut(
                USDC_100,
                usdcUsdt_USDC_Before,
                usdcUsdt_USDT_Before
            );

            usdcPool100.swapAndWithdraw(
                "",
                root,
                _nullifier(2),
                recipient2,
                address(usdt),
                (expectedUsdt * 99) / 100,
                address(0),
                0
            );

            uint256 usdtReceived = usdt.balanceOf(recipient2);
            console.log("Swap 2: USDC -> USDT =", usdtReceived);

            // Check only USDC/USDT pair affected
            (uint112 r0, uint112 r1 ) = _getOrderedReserves(usdcUsdtPair, address(usdc));
            assertEq(
                r0,
                usdcUsdt_USDC_Before + USDC_100,
                "USDC/USDT USDC reserve updated"
            );
            assertEq(
                r1,
                usdcUsdt_USDT_Before - usdtReceived,
                "USDC/USDT USDT reserve updated"
            );
        }

        console.log("  Different pair swaps PASSED");
    }

    /**
     * TEST 5: Slippage Protection Through Privacy Layer
     *
     * Verify:
     * - If AMM can't meet minOut, entire tx reverts
     * - Privacy maintained (no partial state changes)
     */
    function test_Integration_SlippageProtection() public {
        console.log("\n=== TEST 5: Slippage Protection ===");

        _depositToPool(alice, usdcPool100, USDC_100, 1);

        bytes32 root = usdcPool100.getLastRoot();

        // Set unrealistic minimum (asking for 1000 DAI for 100 USDC)
        uint256 unrealisticMin = 1000 * 10 ** 18;

        console.log("Attempting swap with unrealistic minOut:", unrealisticMin);

        // Should revert
        vm.expectRevert();
        usdcPool100.swapAndWithdraw(
            "",
            root,
            _nullifier(1),
            bob,
            address(dai),
            unrealisticMin,
            address(0),
            0
        );

        // Verify no state changed (nullifier still unused, deposit still there)
        assertFalse(
            usdcPool100.nullifierHashes(_nullifier(1)),
            "Nullifier should not be marked used"
        );
        assertEq(
            usdcPool100.totalDeposits(),
            USDC_100,
            "Deposit should still be there"
        );

        console.log("  Slippage protection PASSED (tx reverted as expected)");
    }

    /**
     * TEST 6: Reserve Accounting Precision
     *
     * Verify:
     * - After multiple privacy swaps, AMM reserves are exact
     * - No rounding errors accumulate
     * - Constant product formula holds
     */
    function test_Integration_ReserveAccountingPrecision() public {
        console.log("\n=== TEST 6: Reserve Accounting Precision ===");

        // Get initial state
        (uint112 r0Initial, uint112 r1Initial ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        uint256 kInitial = uint256(r0Initial) * uint256(r1Initial);

        console.log("Initial k:", kInitial);

        // Do 5 privacy swaps
        uint256 totalUsdcIn = 0;
        uint256 totalDaiOut = 0;

        for (uint256 i = 0; i < 5; i++) {
            _depositToPool(alice, usdcPool100, USDC_100, 100 + i);

            bytes32 root = usdcPool100.getLastRoot();
            (uint112 r0, uint112 r1 ) = _getOrderedReserves(usdcDaiPair, address(usdc));
            uint256 expectedOut = router.getAmountOut(USDC_100, r0, r1);

            address recipient = address(uint160(0x5000 + i));

            usdcPool100.swapAndWithdraw(
                "",
                root,
                _nullifier(100 + i),
                recipient,
                address(dai),
                (expectedOut * 99) / 100,
                address(0),
                0
            );

            uint256 daiOut = dai.balanceOf(recipient);
            totalUsdcIn += USDC_100;
            totalDaiOut += daiOut;

            console.log("Swap", i + 1, "- DAI out:", daiOut);
        }

        // Final state
        (uint112 r0Final, uint112 r1Final ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        uint256 kFinal = uint256(r0Final) * uint256(r1Final);

        console.log("Final k:", kFinal);
        console.log("Total USDC in:", totalUsdcIn);
        console.log("Total DAI out:", totalDaiOut);

        // ============ Assertions ============

        // Reserves match exactly
        assertEq(r0Final, r0Initial + totalUsdcIn, "USDC reserve exact");
        assertEq(r1Final, r1Initial - totalDaiOut, "DAI reserve exact");

        // k increased (due to fees)
        assertTrue(
            kFinal > kInitial,
            "Constant product should increase due to fees"
        );

        // Pool is empty
        assertEq(usdcPool100.totalDeposits(), 0, "All deposits withdrawn");

        console.log("  Reserve accounting precision PASSED");
    }

    /**
     * TEST 7: End-to-End User Journey (THE DEMO)
     *
     * Shows complete flow from user perspective
     */
    function test_Integration_CompleteUserJourney() public {
        console.log("\n");

        // STEP 1: User deposits USDC privately
        console.log("STEP 1: Alice deposits 100 USDC to ShieldPool");
        console.log("  - Alice's address:", alice);
        console.log("  - Commitment goes into Merkle tree");
        console.log("  - Alice saves her secret note offline");

        bytes32 commitment = keccak256("alice-secret-note");
        bytes32 nullifierHash = keccak256("alice-nullifier");

        _depositToPool(alice, usdcPool100, USDC_100, 777);

        console.log("    Deposit confirmed");
        console.log("");

        // STEP 2: Other users deposit (anonymity set grows)
        console.log("STEP 2: Bob and Carol also deposit (anonymity set)");

        _depositToPool(bob, usdcPool100, USDC_100, 778);
        _depositToPool(carol, usdcPool100, USDC_100, 779);

        console.log("  - Anonymity set size:", usdcPool100.nextIndex());
        console.log("    Can't tell deposits apart!");
        console.log("");

        // STEP 3: Time passes... then withdraw to new address as different token
        console.log("STEP 3: Later... Alice withdraws to NEW address as DAI");

        address newAddress = address(0xDEADBEEF);
        console.log(" New recipient address:", newAddress);
        console.log(" Token change: USDC to DAI");
        console.log(" Using YOUR AMM for the swap!");
        bytes32 root = usdcPool100.getLastRoot();
        (uint112 r0, uint112 r1 ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        uint256 expectedDai = router.getAmountOut(USDC_100, r0, r1);

        console.log(
            "   AMM Quote: 100 USDC to",
            expectedDai / 10 ** 18,
            "DAI"
        );

        usdcPool100.swapAndWithdraw(
            "",
            root,
            _nullifier(777),
            newAddress,
            address(dai),
            (expectedDai * 99) / 100,
            address(0),
            0
        );

        uint256 daiReceived = dai.balanceOf(newAddress);

        console.log("  DAI received:", daiReceived / 10 ** 18);
        console.log("  Privacy swap complete!");

        // STEP 4: Verify privacy achieved
        console.log("STEP 4: Privacy Analysis");
        console.log("  Original depositor: Alice (", alice, ")");
        console.log("  Final recipient: NewAddress (", newAddress, ")");
        console.log("   NO LINK between addresses!");
        console.log("   NO LINK in tokens (USDC to DAI)!");
        console.log("    Anonymity set size: 3 deposits");
        console.log("    Privacy ACHIEVED!");
        console.log("");

        // STEP 5: Verify AMM state
        console.log("STEP 5: AMM State Verification");
        (uint112 r0After, uint112 r1After ) = _getOrderedReserves(usdcDaiPair, address(usdc));
        console.log("   USDC reserve increased by 100");
        console.log("   DAI reserve decreased by", daiReceived / 10 ** 18);
        console.log("    AMM reserves accurate!");
        console.log("");

        // Final assertions
        assertTrue(daiReceived > 0, "Should receive DAI");
        assertEq(r0After, r0 + USDC_100, "USDC reserve correct");
        assertEq(r1After, r1 - daiReceived, "DAI reserve correct");
    }
}

// ============================================================
//                      MOCK CONTRACTS
// ============================================================

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract MockHasher {
    function MiMCSponge(
        uint256 in_xL,
        uint256 in_xR
    ) external pure returns (uint256 xL, uint256 xR) {
        xL =
            uint256(keccak256(abi.encodePacked(in_xL, in_xR))) %
            21888242871839275222246405745257275088548364400416034343698204186575808495617;
        xR = 0;
    }
}
