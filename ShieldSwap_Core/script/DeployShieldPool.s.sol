// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Privacy_Part/ShieldPool.sol";
import "../src/Privacy_Part/MiMCHasher.sol";
import "../src/Privacy_Part/DummyVerifier.sol";
import "../src/AMM_Part/Interfaces/ISSRouter.sol";

contract DeployShieldPool is Script {

    address constant TOKEN_A   = 0x68df70070872b49670190c9c6f77478Fc9Bc2f48;
    address constant SS_ROUTER = 0xfeb4141299997bE4EDE9b012A5bbAe171eE44c6f;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        // 1. Deploy MiMC Hasher
        MiMCHasher hasher = new MiMCHasher();

        // 2. Deploy DummyVerifier x2
        // One for normal withdrawals
        // One for swap withdrawals
        DummyVerifier withdrawVerifier = new DummyVerifier();
        DummyVerifier swapVerifier     = new DummyVerifier();

        // 3. Deploy ShieldPool
        ShieldPool pool = new ShieldPool(
            IERC20(TOKEN_A),                      // deposit token
            100 * 1e18,                           // denomination: 100 tokens
            ISSRouter(SS_ROUTER),                 // AMM router
            IVerifier(address(withdrawVerifier)), // withdraw verifier
            IVerifier(address(swapVerifier)),     // swap verifier
            20,                                   // Merkle tree depth
            IHasher(address(hasher))              // MiMC hasher
        );

        vm.stopBroadcast();

        // ── SAVE THESE ADDRESSES ──────────────────────────
        console.log("=== SHIELDPOOL DEPLOYED ===");
        console.log("MiMCHasher:       ", address(hasher));
        console.log("WithdrawVerifier: ", address(withdrawVerifier));
        console.log("SwapVerifier:     ", address(swapVerifier));
        console.log("ShieldPool:       ", address(pool));
        console.log("Token:            ", TOKEN_A);
        console.log("Denomination:      100 tokens");
        console.log("===========================");
    }
}