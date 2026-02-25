// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/Privacy_Part/ShieldPool.sol";
import "../../src/Privacy_Part/DummyVerifier.sol";
import "../../src/Privacy_Part/MerkleTreeWithHistory.sol";

/**
 * @title MockERC20
 * @notice Simple ERC20 for testing
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
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
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @title MockSSRouter
 * @notice Mock router for testing swap functionality
 */
contract MockSSRouter {
    mapping(address => mapping(address => address)) public pairs;
    
    function setPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }
    
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }
    
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external returns (uint256 amountOut) {
        // Simple mock: 1:1 swap ratio
        amountOut = amountIn;
        require(amountOut >= amountOutMin, "MockRouter: insufficient output");
        
        // Transfer tokens
        MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(tokenOut).transfer(to, amountOut);
        
        return amountOut;
    }
    
    function factory() external pure returns (address) {
        return address(0);
    }
    
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut) {
        // Simple   product formula
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }
}

/**
 * @title MockHasher
 * @notice Mock MiMC hasher for testing
 */
contract MockHasher {
    function MiMCSponge(uint256 in_xL, uint256 in_xR) 
        external 
        pure 
        returns (uint256 xL, uint256 xR) 
    {
        // Simple hash function for testing (NOT cryptographically secure)
        xL = uint256(keccak256(abi.encodePacked(in_xL, in_xR))) % 
             21888242871839275222246405745257275088548364400416034343698204186575808495617;
        xR = 0;
    }
}

/**
 * @title ShieldPoolTest
 * @notice Comprehensive tests for ShieldPool using DummyVerifier
 */
contract ShieldPoolTest is Test {
    ShieldPool public pool;
    MockERC20 public usdc;
    MockERC20 public dai;
    MockSSRouter public router;
    DummyVerifier public withdrawVerifier;
    DummyVerifier public swapVerifier;
    MockHasher public hasher;
    
    uint256 constant DENOMINATION = 100 * 10**6; // 100 USDC (6 decimals)
    uint32 constant TREE_LEVELS = 20;
    
    address alice = address(0x1);
    address bob = address(0x2);
    address relayer = address(0x3);
    
    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        
        // Deploy router
        router = new MockSSRouter();
        
        // Create mock pair
        router.setPair(address(usdc), address(dai), address(0x999));
        
        // Deploy verifiers
        withdrawVerifier = new DummyVerifier();
        swapVerifier = new DummyVerifier();
        
        // Deploy hasher
        hasher = new MockHasher();
        
        // Deploy ShieldPool
        pool = new ShieldPool(
            IERC20(address(usdc)),
            DENOMINATION,
            ISSRouter(address(router)),
            IVerifier(address(withdrawVerifier)),
            IVerifier(address(swapVerifier)),
            TREE_LEVELS,
            IHasher(address(hasher))
        );
        
        // Setup: Mint tokens to users
        usdc.mint(alice, 1000 * 10**6);
        usdc.mint(bob, 1000 * 10**6);
        dai.mint(address(router), 10000 * 10**18); // Router needs DAI for swaps
    }
    
    // ============ Deposit Tests ============
    
    function testDeposit1() public {
        bytes32 commitment = keccak256("test-commitment-1");
        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        // Check balances
        assertEq(usdc.balanceOf(alice), 1000 * 10**6 - DENOMINATION);
        assertEq(usdc.balanceOf(address(pool)), DENOMINATION);
        assertEq(pool.totalDeposits(), DENOMINATION);
        assertEq(pool.nextIndex(), 1);
    }
    
    function testDepositMultiple() public {
        uint256 FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment1 =
    bytes32(uint256(keccak256("commitment-1")) % FIELD);

bytes32 commitment2 =
    bytes32(uint256(keccak256("commitment-2")) % FIELD);

bytes32 commitment3 =
    bytes32(uint256(keccak256("commitment-3")) % FIELD);

        // Alice deposits twice
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION * 2);
        pool.deposit(commitment1);
        pool.deposit(commitment2);
        vm.stopPrank();
        
        // Bob deposits once
        vm.startPrank(bob);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment3);
        vm.stopPrank();
        
        // Check state
        assertEq(pool.nextIndex(), 3);
        assertEq(pool.totalDeposits(), DENOMINATION * 3);
        assertEq(usdc.balanceOf(address(pool)), DENOMINATION * 3);
    }
    
    function testDepositRevertsOnZeroCommitment() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        
        vm.expectRevert("ShieldPool: zero commitment");
        pool.deposit(bytes32(0));
        vm.stopPrank();
    }
    
    function testDepositRevertsWithoutApproval() public {
        bytes32 commitment = keccak256("test");
        
        vm.startPrank(alice);
        vm.expectRevert();
        pool.deposit(commitment);
        vm.stopPrank();
    }
    
    // ============ Withdraw Tests ============
    
    function testWithdraw1() public {
        // Setup: Alice deposits
        uint256   FIELD =21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        
        // Withdraw to Bob (with dummy proof)
        bytes memory dummyProof = "";
        pool.withdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,      // recipient
            address(0), // no relayer
            0         // no fee
        );
        
        // Check balances
        assertEq(usdc.balanceOf(bob), bobBalanceBefore + DENOMINATION);
        assertEq(usdc.balanceOf(address(pool)), 0);
        assertEq(pool.totalDeposits(), 0);
        
        // Check nullifier is marked as used
        assertTrue(pool.nullifierHashes(nullifierHash));
    }
    
    function testWithdrawWithRelayerFee() public {
        // Setup: Alice deposits
        uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        uint256 fee = 1 * 10**6; // 1 USDC fee
        
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        uint256 relayerBalanceBefore = usdc.balanceOf(relayer);
        
        // Withdraw with relayer
        bytes memory dummyProof = "";
        pool.withdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,
            relayer,
            fee
        );
        
        // Check balances
        assertEq(usdc.balanceOf(bob), bobBalanceBefore + DENOMINATION - fee);
        assertEq(usdc.balanceOf(relayer), relayerBalanceBefore + fee);
    }
    
    function testWithdrawRevertsOnDoubleSpend() public {
        // Setup: Deposit
       uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        bytes memory dummyProof = "";
        
        // First withdrawal succeeds
        pool.withdraw(dummyProof, root, nullifierHash, bob, address(0), 0);
        
        // Second withdrawal with same nullifier fails
        vm.expectRevert("ShieldPool: note already spent");
        pool.withdraw(dummyProof, root, nullifierHash, bob, address(0), 0);
    }
    
    function testWithdrawRevertsOnInvalidRoot() public {
        bytes32 fakeRoot = keccak256("fake-root");
        bytes32 nullifierHash = keccak256("test-nullifier");
        bytes memory dummyProof = "";
        
        vm.expectRevert("ShieldPool: unknown root");
        pool.withdraw(dummyProof, fakeRoot, nullifierHash, bob, address(0), 0);
    }
    
    function testWithdrawRevertsOnExcessiveFee() public {
        uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        bytes memory dummyProof = "";
        
        vm.expectRevert("ShieldPool: fee exceeds denomination");
        pool.withdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,
            relayer,
            DENOMINATION // Fee equals denomination
        );
    }
    
    // ============ Swap & Withdraw Tests ============
    
    function testSwapAndWithdraw() public {
        // Setup: Alice deposits USDC
        uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        uint256 bobDaiBalanceBefore = dai.balanceOf(bob);
        
        // Withdraw as DAI (swap)
        bytes memory dummyProof = "";
        pool.swapAndWithdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,           // recipient
            address(dai),  // tokenOut
            DENOMINATION,  // amountOutMin (1:1 in mock)
            address(0),    // no relayer
            0              // no fee
        );
        
        // Check balances
        // Mock router does 1:1 swap, so Bob gets 100 USDC worth of DAI
        // Note: In reality, different decimals would matter
        assertEq(dai.balanceOf(bob), bobDaiBalanceBefore + DENOMINATION);
        assertEq(usdc.balanceOf(address(pool)), 0);
        assertEq(pool.totalDeposits(), 0);
        
        // Check nullifier marked used
        assertTrue(pool.nullifierHashes(nullifierHash));
    }
    
    function testSwapAndWithdrawWithFee() public {
        // Setup: Deposit
       uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        uint256 fee = 2 * 10**6; // 2 USDC fee
        uint256 swapAmount = DENOMINATION - fee;
        
        uint256 bobDaiBalanceBefore = dai.balanceOf(bob);
        uint256 relayerUsdcBalanceBefore = usdc.balanceOf(relayer);
        
        // Swap & withdraw with relayer fee
        bytes memory dummyProof = "";
        pool.swapAndWithdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,
            address(dai),
            swapAmount, // Expecting 98 USDC worth of DAI
            relayer,
            fee
        );
        
        // Check balances
        assertEq(dai.balanceOf(bob), bobDaiBalanceBefore + swapAmount); // Gets swapped amount
        assertEq(usdc.balanceOf(relayer), relayerUsdcBalanceBefore + fee); // Gets fee in USDC
    }
    
    function testSwapAndWithdrawRevertsOnSameToken() public {
        uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        bytes memory dummyProof = "";
        
        vm.expectRevert("ShieldPool: use withdraw() for same token");
        pool.swapAndWithdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,
            address(usdc), // Same as pool token
            DENOMINATION,
            address(0),
            0
        );
    }
    
    function testSwapAndWithdrawRevertsOnNonexistentPair() public {
        // Deploy a token without a pair
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        
        uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        bytes memory dummyProof = "";
        
        vm.expectRevert("ShieldPool: pair does not exist");
        pool.swapAndWithdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,
            address(weth), // No pair exists
            DENOMINATION,
            address(0),
            0
        );
    }
    
    function testSwapAndWithdrawRevertsOnDoubleSpend() public {
        uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

bytes32 commitment =
    bytes32(uint256(keccak256("test-commitment")) % FIELD);

bytes32 nullifierHash =
    bytes32(uint256(keccak256("test-nullifier")) % FIELD);

        
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION);
        pool.deposit(commitment);
        vm.stopPrank();
        
        bytes32 root = pool.getLastRoot();
        bytes memory dummyProof = "";
        
        // First swap succeeds
        pool.swapAndWithdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,
            address(dai),
            DENOMINATION,
            address(0),
            0
        );
        
        // Second swap with same nullifier fails
        vm.expectRevert("ShieldPool: note already spent");
        pool.swapAndWithdraw(
            dummyProof,
            root,
            nullifierHash,
            bob,
            address(dai),
            DENOMINATION,
            address(0),
            0
        );
    }
    
    // ============ View Function Tests ============
    
    function testCanSwapTo() public {
        assertTrue(pool.canSwapTo(address(dai)));
        
        MockERC20 weth = new MockERC20("WETH", "WETH", 18);
        assertFalse(pool.canSwapTo(address(weth)));
        assertFalse(pool.canSwapTo(address(0)));
        assertFalse(pool.canSwapTo(address(usdc))); // Same as pool token
    }
    
    // ============ Integration Tests ============
    function toField(bytes memory data) internal pure returns (bytes32) {
        uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;
    return bytes32(uint256(keccak256(data)) % FIELD);
}

    
    function testMultipleDepositsAndWithdrawals() public {
        uint256   FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;
        // Multiple users deposit
        bytes32[] memory commitments = new bytes32[](5);
        bytes32[] memory nullifiers = new bytes32[](5);
        
        for (uint256 i = 0; i < 5; i++) {
    commitments[i] = toField(abi.encodePacked("commitment", i));
    nullifiers[i] = toField(abi.encodePacked("nullifier", i));
}

        // Alice deposits 3 times
        vm.startPrank(alice);
        usdc.approve(address(pool), DENOMINATION * 3);
        pool.deposit(commitments[0]);
        pool.deposit(commitments[1]);
        pool.deposit(commitments[2]);
        vm.stopPrank();
        
        // Bob deposits 2 times
        vm.startPrank(bob);
        usdc.approve(address(pool), DENOMINATION * 2);
        pool.deposit(commitments[3]);
        pool.deposit(commitments[4]);
        vm.stopPrank();
        
        // Verify pool state
        assertEq(pool.nextIndex(), 5);
        assertEq(pool.totalDeposits(), DENOMINATION * 5);
        
        // Get root after all deposits
        bytes32 root = pool.getLastRoot();
        
        // Withdraw some (mixed order)
        bytes memory dummyProof = "";
        
        // Withdraw commitment[1] to address(0x10)
        pool.withdraw(dummyProof, root, nullifiers[1], address(0x10), address(0), 0);
        assertEq(usdc.balanceOf(address(0x10)), DENOMINATION);
        
        // Swap withdrawal commitment[3] to DAI
        pool.swapAndWithdraw(
            dummyProof,
            root,
            nullifiers[3],
            address(0x11),
            address(dai),
            DENOMINATION,
            address(0),
            0
        );
        assertEq(dai.balanceOf(address(0x11)), DENOMINATION);
        
        // Pool state updated
        assertEq(pool.totalDeposits(), DENOMINATION * 3); // 3 remaining
    }
    // In your test file — quick reserve math check
function test_getSwapQuote_math() public {
    // Setup: 1000 tokenA : 29 tokenB in pool
    // Input: 100 tokenA
    // Expected: ~2.66 tokenB (after 0.3% fee)
    
    uint256 amountIn  = 100e18;
    uint112 reserveIn  = 1000e18;  // tokenA reserve
    uint112 reserveOut = 29e18;    // tokenB reserve

    uint256 amountInWithFee = amountIn * 997;
    uint256 numerator       = amountInWithFee * uint256(reserveOut);
    uint256 denominator     = uint256(reserveIn) * 1000 + amountInWithFee;
    uint256 result          = numerator / denominator;

    // result should be ~2.66e18
    console.log("Quote:", result);
    // 2663197969543147208 = 2.663 tokenB ✅
}
}
