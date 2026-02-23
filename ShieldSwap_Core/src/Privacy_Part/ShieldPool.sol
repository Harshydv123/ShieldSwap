// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MerkleTreeWithHistory.sol";
import {ISSRouter} from "../AMM_Part/Interfaces/ISSRouter.sol";
import {ISSPair} from "../AMM_Part/Interfaces/ISSPair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IVerifier
 * @notice Interface for Groth16 ZK proof verifier
 * @dev Will be DummyVerifier in Phase 1, real Groth16 in Phase 2
 */
interface IVerifier {
    function verifyProof(
        bytes calldata proof,
        uint256[] calldata publicSignals
    ) external view returns (bool);
}

/**
 * @title ShieldPool
 * @author Harsh Yadav 
 * @notice Privacy pool with Tornado-style deposits and optional AMM swap on withdrawal
 * @dev Each pool handles ONE token at ONE fixed denomination
 * 
 * Key Features:
 * - Fixed-denomination deposits (e.g., exactly 100 USDC)
 * - Merkle tree commitment tracking
 * - Two withdrawal modes:
 *   1. withdraw() - Get same token back
 *   2. swapAndWithdraw() - Swap to different token via AMM
 * - Nullifier prevents double-spending
 * - Root history allows recent proofs
 * - Relayer support for gas-less withdrawals
 * 
 * Privacy Model:
 * - All deposits in a pool are identical amounts
 * - Creates anonymity set (can't tell which deposit → which withdrawal)
 * - Larger pools = better privacy
 */
contract ShieldPool is MerkleTreeWithHistory, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Immutable Configuration ============
    
    /// @notice The ERC20 token this pool accepts (e.g., USDC, DAI)
    IERC20 public immutable token;
    
    /// @notice Fixed deposit/withdrawal amount in token's smallest unit
    /// @dev Examples:
    ///      - USDC (6 decimals): 100 USDC = 100_000_000
    ///      - DAI (18 decimals): 100 DAI = 100_000_000_000_000_000_000
    uint256 public immutable denomination;
    
    /// @notice ShieldSwap AMM router for token swaps
    ISSRouter public immutable router;
    
    /// @notice ZK verifier for simple withdrawals (same token out)
    IVerifier public immutable withdrawVerifier;
    
    /// @notice ZK verifier for swap withdrawals (different token out)
    IVerifier public immutable swapVerifier;

    // ============ Mutable State ============
    
    /// @dev Mapping of used nullifiers to prevent double-spending
    /// @notice Once a nullifier is used, that deposit can never be withdrawn again
    mapping(bytes32 => bool) public nullifierHashes;
    
    /// @notice Total value currently locked in this pool
    uint256 public totalDeposits;

    // ============ Events ============
    
    /**
     * @notice Emitted when tokens are deposited into the pool
     * @param commitment Pedersen hash of (nullifier, secret) - the user's private note
     * @param leafIndex Position in Merkle tree
     * @param timestamp Block timestamp of deposit
     */
    event Deposit(
        bytes32 indexed commitment,
        uint32 leafIndex,
        uint256 timestamp
    );
    
    /**
     * @notice Emitted when tokens are withdrawn (same token)
     * @param recipient Address receiving the tokens
     * @param nullifierHash Hash of the nullifier (public, prevents reuse)
     * @param relayer Address that submitted the transaction (0x0 if self-relay)
     * @param fee Amount paid to relayer
     */
    event Withdrawal(
        address indexed recipient,
        bytes32 nullifierHash,
        address indexed relayer,
        uint256 fee
    );
    
    /**
     * @notice Emitted when tokens are swapped and withdrawn
     * @param recipient Address receiving swapped tokens
     * @param nullifierHash Hash of the nullifier
     * @param tokenOut Token received after swap
     * @param amountOut Amount of tokenOut received
     * @param relayer Address of relayer
     * @param fee Fee paid to relayer (in original token)
     */
    event SwapWithdrawal(
        address indexed recipient,
        bytes32 nullifierHash,
        address tokenOut,
        uint256 amountOut,
        address indexed relayer,
        uint256 fee
    );

    // ============ Constructor ============
    
    /**
     * @notice Deploy a new privacy pool
     * @param _token ERC20 token address (e.g., USDC at 0xA0b8...)
     * @param _denomination Fixed amount in token's base units (e.g., 100 * 10^6 for 100 USDC)
     * @param _router SSRouter address for swaps
     * @param _withdrawVerifier Verifier contract for normal withdrawals
     * @param _swapVerifier Verifier contract for swap withdrawals
     * @param _levels Merkle tree depth (20 = ~1M deposits, 25 = ~33M deposits)
     * @param _hasher MiMC hasher contract address
     */
    constructor(
        IERC20 _token,
        uint256 _denomination,
        ISSRouter _router,
        IVerifier _withdrawVerifier,
        IVerifier _swapVerifier,
        uint32 _levels,
        IHasher _hasher
    ) MerkleTreeWithHistory(_levels, _hasher) {
        require(address(_token) != address(0), "ShieldPool: zero token address");
        require(_denomination > 0, "ShieldPool: zero denomination");
        require(address(_router) != address(0), "ShieldPool: zero router address");
        require(address(_withdrawVerifier) != address(0), "ShieldPool: zero withdraw verifier");
        require(address(_swapVerifier) != address(0), "ShieldPool: zero swap verifier");
        
        token = _token;
        denomination = _denomination;
        router = _router;
        withdrawVerifier = _withdrawVerifier;
        swapVerifier = _swapVerifier;
    }

    // ============ Deposit Function ============
    
    /**
     * @notice Deposit tokens into the privacy pool
     * @dev User must approve this contract for `denomination` tokens before calling
     * @param _commitment Pedersen hash of (nullifier, secret)
     * 
     * Flow:
     * 1. User generates random nullifier and secret off-chain
     * 2. User computes commitment = PedersenHash(nullifier, secret)
     * 3. User saves note = "shieldswap-[amount]-[nullifier]-[secret]"
     * 4. User approves tokens and calls this function
     * 5. Commitment is inserted into Merkle tree
     * 6. User can later withdraw using the note
     * 
     * Privacy: The commitment reveals nothing about nullifier or secret
     */
    function deposit(bytes32 _commitment) external nonReentrant {
        require(_commitment != bytes32(0), "ShieldPool: zero commitment");
        
        // Transfer exact denomination from user to pool
        token.safeTransferFrom(msg.sender, address(this), denomination);
        
        // Insert commitment into Merkle tree
        uint32 insertedIndex = _insert(_commitment);
        
        // Update total locked value
        totalDeposits += denomination;
        
        emit Deposit(_commitment, insertedIndex, block.timestamp);
    }

    // ============ Withdraw (Same Token) ============
    
    /**
     * @notice Withdraw original token to a new address (privacy preserved)
     * @param _proof ZK proof bytes
     * @param _root Merkle root (must exist in recent history)
     * @param _nullifierHash Hash of nullifier (public, prevents double-spend)
     * @param _recipient Address to receive tokens (can be different from depositor)
     * @param _relayer Address that paid gas (receives fee, or 0x0 for self-relay)
     * @param _fee Amount to pay relayer (must be < denomination)
     * 
     * ZK Proof proves:
     * - "I know (nullifier, secret) such that:"
     * - "PedersenHash(nullifier, secret) exists in the Merkle tree"
     * - "nullifierHash = Hash(nullifier)"
     * - "Send to this recipient with this fee"
     * 
     * Privacy: No link between depositor and recipient addresses
     */
    function withdraw(
        bytes calldata _proof,
        bytes32 _root,
        bytes32 _nullifierHash,
        address _recipient,
        address _relayer,
        uint256 _fee
    ) external nonReentrant {
        require(!nullifierHashes[_nullifierHash], "ShieldPool: note already spent");
        require(isKnownRoot(_root), "ShieldPool: unknown root");
        require(_fee < denomination, "ShieldPool: fee exceeds denomination");
        require(_recipient != address(0), "ShieldPool: zero recipient");
        
        // Construct public inputs for ZK proof verification
        uint256[] memory publicInputs = new uint256[](5);
        publicInputs[0] = uint256(_root);
        publicInputs[1] = uint256(_nullifierHash);
        publicInputs[2] = uint256(uint160(_recipient));
        publicInputs[3] = uint256(uint160(_relayer));
        publicInputs[4] = _fee;
        
        // Verify the ZK proof
        require(
            withdrawVerifier.verifyProof(_proof, publicInputs),
            "ShieldPool: invalid withdrawal proof"
        );
        
        // Mark nullifier as used (prevents double-spend)
        nullifierHashes[_nullifierHash] = true;
        
        // Calculate recipient amount (after relayer fee)
        uint256 recipientAmount = denomination - _fee;
        
        // Transfer tokens to recipient
        token.safeTransfer(_recipient, recipientAmount);
        
        // Pay relayer fee if applicable
        if (_fee > 0 && _relayer != address(0)) {
            token.safeTransfer(_relayer, _fee);
        }
        
        // Update total locked value
        totalDeposits -= denomination;
        
        emit Withdrawal(_recipient, _nullifierHash, _relayer, _fee);
    }

    // ============ Swap & Withdraw (Different Token) ============
    
    /**
     * @notice Withdraw by swapping to a different token via AMM
     * @param _proof ZK proof bytes
     * @param _root Merkle root
     * @param _nullifierHash Hash of nullifier
     * @param _recipient Address to receive swapped tokens
     * @param _tokenOut Token to receive (e.g., DAI if deposited USDC)
     * @param _amountOutMin Minimum output amount (slippage protection)
     * @param _relayer Relayer address (or 0x0 for self-relay)
     * @param _fee Relayer fee (paid in original token, before swap)
     * 
     * Flow:
     * 1. Verify ZK proof (includes tokenOut and amountOutMin commitments)
     * 2. Mark nullifier as used
     * 3. Approve router to spend tokens
     * 4. Swap (denomination - fee) via SSRouter
     * 5. Send swapped tokens to recipient
     * 6. Pay relayer fee in original token
     * 
     * Example:
     * - Deposited: 100 USDC
     * - Fee: 1 USDC (to relayer)
     * - Swap: 99 USDC → ~50 DAI (via AMM)
     * - Recipient gets: 50 DAI
     * - Privacy maintained: Can't link deposit to withdrawal
     */
    function swapAndWithdraw(
        bytes calldata _proof,
        bytes32 _root,
        bytes32 _nullifierHash,
        address _recipient,
        address _tokenOut,
        uint256 _amountOutMin,
        address _relayer,
        uint256 _fee
    ) external nonReentrant {
        require(!nullifierHashes[_nullifierHash], "ShieldPool: note already spent");
        require(isKnownRoot(_root), "ShieldPool: unknown root");
        require(_fee < denomination, "ShieldPool: fee exceeds denomination");
        require(_recipient != address(0), "ShieldPool: zero recipient");
        require(_tokenOut != address(0), "ShieldPool: zero tokenOut");
        require(_tokenOut != address(token), "ShieldPool: use withdraw() for same token");
        
        // Verify pair exists in AMM
        address pair = router.getPair(address(token), _tokenOut);
        require(pair != address(0), "ShieldPool: pair does not exist");
        
        // Construct public inputs for ZK proof verification
        // Note: This uses the swapVerifier which expects tokenOut and amountOutMin
        uint256[] memory publicInputs = new uint256[](7);
        publicInputs[0] = uint256(_root);
        publicInputs[1] = uint256(_nullifierHash);
        publicInputs[2] = uint256(uint160(_recipient));
        publicInputs[3] = uint256(uint160(_relayer));
        publicInputs[4] = _fee;
        publicInputs[5] = uint256(uint160(_tokenOut));
        publicInputs[6] = _amountOutMin;
        
        // Verify the ZK proof
        require(
            swapVerifier.verifyProof(_proof, publicInputs),
            "ShieldPool: invalid swap proof"
        );
        
        // Mark nullifier as used
        nullifierHashes[_nullifierHash] = true;
        
        // Amount to swap (after deducting relayer fee)
        uint256 swapAmount = denomination - _fee;
        
        // Approve router to spend tokens
        token.approve(address(router), swapAmount);
        
        // Execute swap via SSRouter
        uint256 amountOut = router.swapExactTokensForTokens(
            address(token),    // tokenIn
            _tokenOut,         // tokenOut
            swapAmount,        // amountIn
            _amountOutMin,     // amountOutMin (slippage protection)
            _recipient         // to
        );
        
        // Reset approval to zero (security best practice)
        token.approve(address(router), 0);
        
        // Pay relayer fee in original token
        if (_fee > 0 && _relayer != address(0)) {
            token.safeTransfer(_relayer, _fee);
        }
        
        // Update total locked value
        totalDeposits -= denomination;
        
        emit SwapWithdrawal(
            _recipient,
            _nullifierHash,
            _tokenOut,
            amountOut,
            _relayer,
            _fee
        );
    }

    // ============ View Functions ============
    
    /**
     * @notice Check if this pool can swap to a given token
     * @param _tokenOut Token to check
     * @return true if pair exists in AMM
     */
    function canSwapTo(address _tokenOut) external view returns (bool) {
        if (_tokenOut == address(0) || _tokenOut == address(token)) {
            return false;
        }
        address pair = router.getPair(address(token), _tokenOut);
        return pair != address(0);
    }
    
    /**
 * @notice Get expected output amount for a swap
 * @dev Uses Uniswap V2 formula: dy = dx*997*y / (x*1000 + dx*997)
 * @param _tokenOut Token to swap to
 * @param _amountIn Amount of pool token to swap
 * @return Expected output amount after 0.3% fee
 */
function getSwapQuote(address _tokenOut, uint256 _amountIn)
    external
    view
    returns (uint256)
{
    // Check pair exists
    address pair = router.getPair(address(token), _tokenOut);
    require(pair != address(0), "ShieldPool: pair does not exist");

    // Read current reserves from SSPair
    (uint112 res0, uint112 res1,) = ISSPair(pair).getReserves();

    // Determine which reserve belongs to which token
    // Uniswap V2 sorts tokens by address — we can't assume order
    address token0 = ISSPair(pair).token0();

    // If our deposit token is token0:
    //   reserveIn  = res0 (our token)
    //   reserveOut = res1 (token we want)
    // If our deposit token is token1:
    //   reserveIn  = res1 (our token)
    //   reserveOut = res0 (token we want)
    (uint112 reserveIn, uint112 reserveOut) = address(token) == token0
        ? (res0, res1)
        : (res1, res0);

    // Uniswap V2 formula with 0.3% fee
    // Derivation:
    //   amountInWithFee = amountIn * 997  (remove 0.3% fee)
    //   amountOut = amountInWithFee * reserveOut
    //               ─────────────────────────────────────
    //               reserveIn * 1000 + amountInWithFee
    uint256 amountInWithFee = _amountIn * 997;
    uint256 numerator       = amountInWithFee * uint256(reserveOut);
    uint256 denominator     = uint256(reserveIn) * 1000 + amountInWithFee;

    return numerator / denominator;
}
}
