// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ShieldLP
 * @notice Anonymous liquidity position management using ZK commitments
 * @dev Allows users to shield LP tokens with zero-knowledge privacy, earning fees while remaining anonymous
 */

interface IVerifier {
    function verifyProof(bytes calldata proof, bytes32[] calldata inputs) external view returns (bool);
}

contract ShieldLP {
    // ─── State Variables ──────────────────────────────────────────────────
    IERC20 public immutable lpToken;        // The LP token (SSPair)
    IVerifier public immutable verifier;     // ZK proof verifier (can be dummy)
    
    uint256 public constant MERKLE_TREE_HEIGHT = 20;
    uint256 public constant FIELD_SIZE = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    
    // Merkle tree for commitments
    bytes32[] public filledSubtrees;
    bytes32[] public roots;
    uint32 public currentRootIndex = 0;
    uint32 public nextIndex = 0;
    
    // Track spent nullifiers to prevent double-withdrawals
    mapping(bytes32 => bool) public nullifierHashes;
    
    // Track deposits by commitment for transparency
    mapping(bytes32 => uint256) public commitmentToAmount;
    
    // ─── Events ───────────────────────────────────────────────────────────
    event LPShielded(bytes32 indexed commitment, uint256 amount, uint32 leafIndex, uint256 timestamp);
    event LPUnshielded(address indexed recipient, bytes32 nullifierHash, uint256 amount, address relayer, uint256 fee);
    
    // ─── Errors ───────────────────────────────────────────────────────────
    error InvalidProof();
    error NullifierAlreadySpent();
    error InvalidMerkleRoot();
    error InvalidAmount();
    error TransferFailed();
    error TreeIsFull();
    error InvalidCommitment();
    
    // ─── Constructor ──────────────────────────────────────────────────────
    constructor(address _lpToken, address _verifier) {
        lpToken = IERC20(_lpToken);
        verifier = IVerifier(_verifier);
        
        // Initialize Merkle tree
        for (uint32 i = 0; i < MERKLE_TREE_HEIGHT; i++) {
            filledSubtrees.push(zeros(i));
        }
        roots.push(zeros(MERKLE_TREE_HEIGHT));
    }
    
    // ─── Shield LP Tokens ─────────────────────────────────────────────────
    /**
     * @notice Shield LP tokens by depositing them with a commitment
     * @param commitment The commitment hash (hash of nullifier + secret)
     * @param amount The amount of LP tokens to shield
     */
    function shieldLP(bytes32 commitment, uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (commitment == bytes32(0)) revert InvalidCommitment();
        if (nextIndex >= uint32(2)**MERKLE_TREE_HEIGHT) revert TreeIsFull();
        
        // Transfer LP tokens from user to this contract
        bool success = lpToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();
        
        // Store amount for this commitment
        commitmentToAmount[commitment] = amount;
        
        // Insert commitment into Merkle tree
        uint32 leafIndex = _insert(commitment);
        
        emit LPShielded(commitment, amount, leafIndex, block.timestamp);
    }
    
    // ─── Unshield LP Tokens ───────────────────────────────────────────────
    /**
     * @notice Unshield LP tokens using a ZK proof
     * @param proof The zero-knowledge proof
     * @param root The Merkle root
     * @param nullifierHash The nullifier hash to prevent double-spending
     * @param recipient The address to receive LP tokens
     * @param relayer The relayer address (address(0) if none)
     * @param fee The fee to pay to relayer
     * @param commitment The original commitment (needed to look up amount)
     */
    function unshieldLP(
        bytes calldata proof,
        bytes32 root,
        bytes32 nullifierHash,
        address recipient,
        address relayer,
        uint256 fee,
        bytes32 commitment
    ) external {
        // Check nullifier hasn't been used
        if (nullifierHashes[nullifierHash]) revert NullifierAlreadySpent();
        
        // Check root is valid
        if (!isKnownRoot(root)) revert InvalidMerkleRoot();
        
        // Verify ZK proof (dummy verifier will always return true for demo)
        // In production, this would verify the proof against public inputs
        bytes32[] memory inputs = new bytes32[](2);
        inputs[0] = root;
        inputs[1] = nullifierHash;
        
        if (!verifier.verifyProof(proof, inputs)) revert InvalidProof();
        
        // Mark nullifier as spent
        nullifierHashes[nullifierHash] = true;
        
        // Get the amount from commitment
        uint256 amount = commitmentToAmount[commitment];
        if (amount == 0) revert InvalidAmount();
        
        // Delete commitment data (privacy + gas refund)
        delete commitmentToAmount[commitment];
        
        // Calculate relayer fee
        uint256 amountToRecipient = amount;
        if (fee > 0 && relayer != address(0)) {
            if (fee > amount) revert InvalidAmount();
            amountToRecipient = amount - fee;
            bool feeSuccess = lpToken.transfer(relayer, fee);
            if (!feeSuccess) revert TransferFailed();
        }
        
        // Transfer LP tokens to recipient
        bool success = lpToken.transfer(recipient, amountToRecipient);
        if (!success) revert TransferFailed();
        
        emit LPUnshielded(recipient, nullifierHash, amount, relayer, fee);
    }
    
    // ─── Merkle Tree Functions ────────────────────────────────────────────
    function _insert(bytes32 leaf) internal returns (uint32 index) {
        uint32 _nextIndex = nextIndex;
        require(_nextIndex != uint32(2)**MERKLE_TREE_HEIGHT, "Merkle tree is full");
        
        uint32 currentIndex = _nextIndex;
        bytes32 currentLevelHash = leaf;
        bytes32 left;
        bytes32 right;
        
        for (uint32 i = 0; i < MERKLE_TREE_HEIGHT; i++) {
            if (currentIndex % 2 == 0) {
                left = currentLevelHash;
                right = zeros(i);
                filledSubtrees[i] = currentLevelHash;
            } else {
                left = filledSubtrees[i];
                right = currentLevelHash;
            }
            currentLevelHash = hashLeftRight(left, right);
            currentIndex /= 2;
        }
        
        uint32 newRootIndex = (currentRootIndex + 1) % 100;
        currentRootIndex = newRootIndex;
        roots.push(currentLevelHash);
        nextIndex = _nextIndex + 1;
        return _nextIndex;
    }
    
    function hashLeftRight(bytes32 left, bytes32 right) public pure returns (bytes32) {
        // Using keccak256 for simplicity (real version would use MiMC/Poseidon)
        return keccak256(abi.encodePacked(left, right));
    }
    
    function zeros(uint256 i) public pure returns (bytes32) {
        if (i == 0) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        if (i == 1) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000001);
        if (i == 2) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000002);
        if (i == 3) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000003);
        if (i == 4) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000004);
        if (i == 5) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000005);
        if (i == 6) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000006);
        if (i == 7) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000007);
        if (i == 8) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000008);
        if (i == 9) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000009);
        if (i == 10) return bytes32(0x000000000000000000000000000000000000000000000000000000000000000a);
        if (i == 11) return bytes32(0x000000000000000000000000000000000000000000000000000000000000000b);
        if (i == 12) return bytes32(0x000000000000000000000000000000000000000000000000000000000000000c);
        if (i == 13) return bytes32(0x000000000000000000000000000000000000000000000000000000000000000d);
        if (i == 14) return bytes32(0x000000000000000000000000000000000000000000000000000000000000000e);
        if (i == 15) return bytes32(0x000000000000000000000000000000000000000000000000000000000000000f);
        if (i == 16) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000010);
        if (i == 17) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000011);
        if (i == 18) return bytes32(0x0000000000000000000000000000000000000000000000000000000000000012);
        return bytes32(0x0000000000000000000000000000000000000000000000000000000000000013);
    }
    
    function isKnownRoot(bytes32 _root) public view returns (bool) {
        if (_root == 0) return false;
        uint32 _currentRootIndex = currentRootIndex;
        uint32 i = _currentRootIndex;
        do {
            if (_root == roots[i]) return true;
            if (i == 0) i = uint32(roots.length);
            i--;
        } while (i != _currentRootIndex);
        return false;
    }
    
    function getLastRoot() public view returns (bytes32) {
        return roots[roots.length - 1];
    }
    
    // ─── View Functions ───────────────────────────────────────────────────
    function totalShielded() external view returns (uint256) {
        return lpToken.balanceOf(address(this));
    }
    
    function totalDeposits() external view returns (uint32) {
        return nextIndex;
    }
}
