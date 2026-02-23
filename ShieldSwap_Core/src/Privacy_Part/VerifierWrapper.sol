// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IGroth16Verifier
 * @notice Interface for the auto-generated Groth16 verifier
 */
interface IGroth16Verifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[5] calldata _pubSignals
    ) external view returns (bool);
}

/**
 * @title VerifierWrapper
 * @notice Wrapper to make Groth16 verifier compatible with ShieldPool's IVerifier interface
 * @dev Converts flat bytes proof into Groth16's structured format
 */
contract VerifierWrapper {
    IGroth16Verifier public immutable groth16Verifier;

    constructor(address _groth16Verifier) {
        require(_groth16Verifier != address(0), "VerifierWrapper: zero address");
        groth16Verifier = IGroth16Verifier(_groth16Verifier);
    }

    /**
     * @notice Verify a ZK proof (ShieldPool-compatible interface)
     * @param _proof Encoded proof bytes (must be 256 bytes for Groth16)
     * @param _publicSignals Array of 5 public inputs [root, nullifierHash, recipient, relayer, fee]
     * @return true if proof is valid
     */
    function verifyProof(
        bytes calldata _proof,
        uint256[] calldata _publicSignals
    ) external view returns (bool) {
        require(_proof.length == 256, "VerifierWrapper: invalid proof length");
        require(_publicSignals.length == 5, "VerifierWrapper: invalid public signals length");

        // Decode proof bytes into Groth16 format
        // Groth16 proof structure:
        // - pA: 2 uint256s (64 bytes)
        // - pB: 4 uint256s (128 bytes) - 2x2 matrix
        // - pC: 2 uint256s (64 bytes)
        // Total: 256 bytes

        uint[2] memory pA;
        uint[2][2] memory pB;
        uint[2] memory pC;

        // Extract pA (bytes 0-63)
        pA[0] = uint256(bytes32(_proof[0:32]));
        pA[1] = uint256(bytes32(_proof[32:64]));

        // Extract pB (bytes 64-191)
        pB[0][0] = uint256(bytes32(_proof[64:96]));
        pB[0][1] = uint256(bytes32(_proof[96:128]));
        pB[1][0] = uint256(bytes32(_proof[128:160]));
        pB[1][1] = uint256(bytes32(_proof[160:192]));

        // Extract pC (bytes 192-255)
        pC[0] = uint256(bytes32(_proof[192:224]));
        pC[1] = uint256(bytes32(_proof[224:256]));

        // Convert public signals to fixed-size array
        uint[5] memory pubSignals;
        for (uint i = 0; i < 5; i++) {
            pubSignals[i] = _publicSignals[i];
        }

        // Call the real Groth16 verifier
        return groth16Verifier.verifyProof(pA, pB, pC, pubSignals);
    }
}