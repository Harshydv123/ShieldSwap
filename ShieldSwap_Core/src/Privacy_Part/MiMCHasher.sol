// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MiMCHasher {
    uint256 constant FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    uint256 constant ROUNDS = 91;

    // ← Signature now matches IHasher interface
    // k is hardcoded to 0 (standard MiMC sponge)
    function MiMCSponge(
        uint256 xL,
        uint256 xR
    ) external pure returns (uint256, uint256) {
        require(xL < FIELD, "MiMC: xL out of field");
        require(xR < FIELD, "MiMC: xR out of field");

        uint256 k = 0; // hardcoded key = 0
        uint256 t;

        for (uint256 i = 0; i < ROUNDS; i++) {
            t = addmod(xL, k, FIELD);
            t = addmod(t, _roundConstant(i), FIELD);

            xL = mulmod(t, t, FIELD);
            xL = mulmod(xL, t, FIELD);
            xL = mulmod(xL, t, FIELD);
            xL = mulmod(xL, t, FIELD);

            (xL, xR) = (xR, xL);
        }

        return (xL, xR);
    }

    function _roundConstant(uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked("mimc", i))) % FIELD;
    }
}