// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DummyVerifier
 * @notice Mock verifier that always returns true for Phase 1 development
 * @dev This allows testing all business logic before ZK circuits are ready
 * 
 * Usage:
 * - Phase 1: Deploy this as both withdrawVerifier and swapVerifier
 * - Phase 2: Replace with real Groth16 verifiers from Circom
 * 
 * SECURITY WARNING: 
 * This contract provides NO privacy or security!
 * Only use in development/testing environments.
 * Must be replaced with real verifiers before production.
 */
contract DummyVerifier {
    /**
     * @notice Always returns true (no actual verification)
     * @param proof Ignored (can be empty bytes)
     * @param publicSignals Ignored (can be any values)
     * @return true Always succeeds
     */
    function verifyProof(
        bytes calldata proof,
        uint256[] calldata publicSignals
    ) external pure returns (bool) {
        // Explicitly ignore parameters to avoid compiler warnings
        proof;
        publicSignals;
        
        // Always return true - this is intentionally insecure for testing
        return true;
    }
}
