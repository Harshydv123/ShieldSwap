// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IHasher
 * @dev Interface for MiMC hash function used in Merkle tree
 * @notice MiMC is a ZK-friendly hash function compatible with circom circuits
 */
interface IHasher {
    function MiMCSponge(uint256 in_xL, uint256 in_xR) external pure returns (uint256 xL, uint256 xR);
}

/**
 * @title MerkleTreeWithHistory
 * @dev Incremental Merkle tree with root history for privacy protocols
 * @notice This is adapted from Tornado Cash for ShieldSwap
 * 
 * Key Features:
 * - Incremental updates (no need to recompute entire tree)
 * - Root history buffer (allows recent roots for withdrawal proofs)
 * - MiMC hashing (ZK-circuit compatible)
 * - Gas optimized with mappings instead of arrays
 */
contract MerkleTreeWithHistory {
    // ============ Constants ============
    
    /// @dev BN254 scalar field size (used in ZK circuits)
    uint256 public constant FIELD_SIZE = 
        21888242871839275222246405745257275088548364400416034343698204186575808495617;
    
    /// @dev Initial zero value = keccak256("tornado") % FIELD_SIZE
    /// @notice This is the default value for empty tree leaves
    uint256 public constant ZERO_VALUE = 
        21663839004416932945382355908790599225266501822907911457504978515578255421292;
    
    /// @dev Number of historical roots to store (ring buffer)
    /// @notice Users can use any of the last 30 roots for withdrawal proofs
    uint32 public constant ROOT_HISTORY_SIZE = 30;

    // ============ Immutable State ============
    
    /// @notice External hasher contract (MiMC implementation)
    IHasher public immutable hasher;
    
    /// @notice Tree depth (number of levels)
    /// @dev Must be between 1-31 (2^levels = max leaves)
    uint32 public immutable levels;

    // ============ Mutable State ============
    
    /// @dev Stores the rightmost filled node at each level
    /// @notice Used for incremental tree updates
    /// @dev Using mapping instead of array saves gas (no bounds checking)
    mapping(uint256 => bytes32) public filledSubtrees;
    
    /// @dev Ring buffer of historical Merkle roots
    /// @notice Allows withdrawals using recent (but not current) roots
    mapping(uint256 => bytes32) public roots;
    
    /// @notice Current position in root history ring buffer
    uint32 public currentRootIndex;
    
    /// @notice Index of next leaf to be inserted
    /// @dev Also tracks total number of deposits
    uint32 public nextIndex;

    // ============ Events ============
    
    /// @notice Emitted when a new leaf is inserted
    /// @param leafIndex Index of the inserted leaf
    /// @param leaf The commitment that was inserted
    /// @param root New Merkle root after insertion
    event LeafInsertion(uint32 indexed leafIndex, bytes32 leaf, bytes32 root);

    // ============ Constructor ============
    
    /**
     * @notice Initialize the Merkle tree
     * @param _levels Tree depth (1-31)
     * @param _hasher Address of MiMC hasher contract
     */
    constructor(uint32 _levels, IHasher _hasher) {
        require(_levels > 0, "MerkleTree: levels must be > 0");
        require(_levels < 32, "MerkleTree: levels must be < 32");
        
        levels = _levels;
        hasher = _hasher;

        // Initialize filledSubtrees with zero values
        for (uint32 i = 0; i < _levels; i++) {
            filledSubtrees[i] = zeros(i);
        }

        // Set initial root (empty tree)
        roots[0] = zeros(_levels);
    }

    // ============ Core Functions ============

    /**
     * @notice Hash two child nodes using MiMC
     * @dev Used to compute parent node in Merkle tree
     * @param _hasher The hasher contract to use
     * @param _left Left child node
     * @param _right Right child node
     * @return Hash of the two inputs
     */
    function hashLeftRight(
        IHasher _hasher,
        bytes32 _left,
        bytes32 _right
    ) public pure returns (bytes32) {
        require(uint256(_left) < FIELD_SIZE, "MerkleTree: left out of field");
        require(uint256(_right) < FIELD_SIZE, "MerkleTree: right out of field");
        
        // MiMC sponge construction
        uint256 R = uint256(_left);
        uint256 C = 0;
        
        // First absorption
        (R, C) = _hasher.MiMCSponge(R, C);
        
        // Add right input
        R = addmod(R, uint256(_right), FIELD_SIZE);
        
        // Second absorption
        (R, C) = _hasher.MiMCSponge(R, C);
        
        return bytes32(R);
    }

    /**
     * @notice Insert a new leaf into the tree
     * @dev Internal function - should be called by child contract (e.g., ShieldPool)
     * @param _leaf The commitment to insert
     * @return index The index where the leaf was inserted
     */
    function _insert(bytes32 _leaf) internal returns (uint32 index) {
        uint32 _nextIndex = nextIndex;
        require(
            _nextIndex != uint32(2)**levels, 
            "MerkleTree: tree is full"
        );

        uint32 currentIndex = _nextIndex;
        bytes32 currentLevelHash = _leaf;
        bytes32 left;
        bytes32 right;

        // Update tree from bottom to top
        for (uint32 i = 0; i < levels; i++) {
            if (currentIndex % 2 == 0) {
                // Left child - store and pair with zero
                left = currentLevelHash;
                right = zeros(i);
                filledSubtrees[i] = currentLevelHash;
            } else {
                // Right child - pair with stored left sibling
                left = filledSubtrees[i];
                right = currentLevelHash;
            }
            
            currentLevelHash = hashLeftRight(hasher, left, right);
            currentIndex /= 2;
        }

        // Update root history (ring buffer)
        uint32 newRootIndex = (currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        currentRootIndex = newRootIndex;
        roots[newRootIndex] = currentLevelHash;
        
        // Increment next index
        nextIndex = _nextIndex + 1;
        
        emit LeafInsertion(_nextIndex, _leaf, currentLevelHash);
        
        return _nextIndex;
    }

    // ============ View Functions ============

    /**
     * @notice Check if a root exists in recent history
     * @dev Used during withdrawal to verify proof is recent
     * @param _root The root to check
     * @return true if root is in history, false otherwise
     */
    function isKnownRoot(bytes32 _root) public view returns (bool) {
        if (_root == 0) {
            return false;
        }
        
        uint32 _currentRootIndex = currentRootIndex;
        uint32 i = _currentRootIndex;
        
        // Search ring buffer
        do {
            if (_root == roots[i]) {
                return true;
            }
            if (i == 0) {
                i = ROOT_HISTORY_SIZE;
            }
            i--;
        } while (i != _currentRootIndex);
        
        return false;
    }

    /**
     * @notice Get the most recent Merkle root
     * @return The current root
     */
    function getLastRoot() public view returns (bytes32) {
        return roots[currentRootIndex];
    }

    /**
     * @notice Get zero value for a given tree level
     * @dev Precomputed zero values for empty subtrees
     * @param i Level index (0 = leaf level)
     * @return Zero value hash for that level
     */
    function zeros(uint256 i) public pure returns (bytes32) {
        if (i == 0) return bytes32(0x2fe54c60d3acabf3343a35b6eba15db4821b340f76e741e2249685ed4899af6c);
        else if (i == 1) return bytes32(0x256a6135777eee2fd26f54b8b7037a25439d5235caee224154186d2b8a52e31d);
        else if (i == 2) return bytes32(0x1151949895e82ab19924de92c40a3d6f7bcb60d92b00504b8199613683f0c200);
        else if (i == 3) return bytes32(0x20121ee811489ff8d61f09fb89e313f14959a0f28bb428a20dba6b0b068b3bdb);
        else if (i == 4) return bytes32(0x0a89ca6ffa14cc462cfedb842c30ed221a50a3d6bf022a6a57dc82ab24c157c9);
        else if (i == 5) return bytes32(0x24ca05c2b5cd42e890d6be94c68d0689f4f21c9cec9c0f13fe41d566dfb54959);
        else if (i == 6) return bytes32(0x1ccb97c932565a92c60156bdba2d08f3bf1377464e025cee765679e604a7315c);
        else if (i == 7) return bytes32(0x19156fbd7d1a8bf5cba8909367de1b624534ebab4f0f79e003bccdd1b182bdb4);
        else if (i == 8) return bytes32(0x261af8c1f0912e465744641409f622d466c3920ac6e5ff37e36604cb11dfff80);
        else if (i == 9) return bytes32(0x0058459724ff6ca5a1652fcbc3e82b93895cf08e975b19beab3f54c217d1c007);
        else if (i == 10) return bytes32(0x1f04ef20dee48d39984d8eabe768a70eafa6310ad20849d4573c3c40c2ad1e30);
        else if (i == 11) return bytes32(0x1bea3dec5dab51567ce7e200a30f7ba6d4276aeaa53e2686f962a46c66d511e5);
        else if (i == 12) return bytes32(0x0ee0f941e2da4b9e31c3ca97a40d8fa9ce68d97c084177071b3cb46cd3372f0f);
        else if (i == 13) return bytes32(0x1ca9503e8935884501bbaf20be14eb4c46b89772c97b96e3b2ebf3a36a948bbd);
        else if (i == 14) return bytes32(0x133a80e30697cd55d8f7d4b0965b7be24057ba5dc3da898ee2187232446cb108);
        else if (i == 15) return bytes32(0x13e6d8fc88839ed76e182c2a779af5b2c0da9dd18c90427a644f7e148a6253b6);
        else if (i == 16) return bytes32(0x1eb16b057a477f4bc8f572ea6bee39561098f78f15bfb3699dcbb7bd8db61854);
        else if (i == 17) return bytes32(0x0da2cb16a1ceaabf1c16b838f7a9e3f2a3a3088d9e0a6debaa748114620696ea);
        else if (i == 18) return bytes32(0x24a3b3d822420b14b5d8cb6c28a574f01e98ea9e940551d2ebd75cee12649f9d);
        else if (i == 19) return bytes32(0x198622acbd783d1b0d9064105b1fc8e4d8889de95c4c519b3f635809fe6afc05);
        else if (i == 20) return bytes32(0x29d7ed391256ccc3ea596c86e933b89ff339d25ea8ddced975ae2fe30b5296d4);
        else if (i == 21) return bytes32(0x19be59f2f0413ce78c0c3703a3a5451b1d7f39629fa33abd11548a76065b2967);
        else if (i == 22) return bytes32(0x1ff3f61797e538b70e619310d33f2a063e7eb59104e112e95738da1254dc3453);
        else if (i == 23) return bytes32(0x10c16ae9959cf8358980d9dd9616e48228737310a10e2b6b731c1a548f036c48);
        else if (i == 24) return bytes32(0x0ba433a63174a90ac20992e75e3095496812b652685b5e1a2eae0b1bf4e8fcd1);
        else if (i == 25) return bytes32(0x019ddb9df2bc98d987d0dfeca9d2b643deafab8f7036562e627c3667266a044c);
        else if (i == 26) return bytes32(0x2d3c88b23175c5a5565db928414c66d1912b11acf974b2e644caaac04739ce99);
        else if (i == 27) return bytes32(0x2eab55f6ae4e66e32c5189eed5c470840863445760f5ed7e7b69b2a62600f354);
        else if (i == 28) return bytes32(0x002df37a2642621802383cf952bf4dd1f32e05433beeb1fd41031fb7eace979d);
        else if (i == 29) return bytes32(0x104aeb41435db66c3e62feccc1d6f5d98d0a0ed75d1374db457cf462e3a1f427);
        else if (i == 30) return bytes32(0x1f3c6fd858e9a7d4b0d1f38e256a09d81d5a5e3c963987e2d4b814cfab7c6ebb);
        else if (i == 31) return bytes32(0x2c7a07d20dff79d01fecedc1134284a8d08436606c93693b67e333f671bf69cc);
        else revert("MerkleTree: index out of bounds");
    }
}