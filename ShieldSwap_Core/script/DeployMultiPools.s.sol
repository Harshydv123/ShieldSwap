// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Privacy_Part/ShieldPool.sol";
import "../src/Privacy_Part/MiMCHasher.sol";
import "../src/Privacy_Part/DummyVerifier.sol";
import "../src/AMM_Part/Interfaces/ISSRouter.sol";

contract DeployMultiPools is Script {

    address constant TOKEN_A   = 0x68df70070872b49670190c9c6f77478Fc9Bc2f48;
    address constant TOKEN_B   = 0x4474bD760d67a8a67e78Cea49886deFd4C8Ce34e;
    address constant SS_ROUTER = 0xfeb4141299997bE4EDE9b012A5bbAe171eE44c6f;
    
    address constant EXISTING_POOL_A100      = 0xa9d547007B9ce930dde76Ce038ce2f0aa53F1F5E;
    address constant EXISTING_HASHER         = 0x0e39E0a7c051cDbe82Bb01D6827BD65140f8E87e;
    address constant EXISTING_WITHDRAW_VERIFIER = 0xDBA0e3Ce58E26906E756067377ccfaCB9D282964;
    address constant EXISTING_SWAP_VERIFIER     = 0x0370932aB3468f6B821c6D4105e471f891c736Ff;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        console.log("Reusing existing MiMCHasher:       ", EXISTING_HASHER);
        console.log("Reusing existing WithdrawVerifier: ", EXISTING_WITHDRAW_VERIFIER);
        console.log("Reusing existing SwapVerifier:     ", EXISTING_SWAP_VERIFIER);
        console.log("Reusing existing Pool TokenA_100:  ", EXISTING_POOL_A100);
        console.log("");

        // Deploy Pool 2 - TokenA, 10 denomination
        
        ShieldPool poolA10 = new ShieldPool(
            IERC20(TOKEN_A),
            10 * 1e18,
            ISSRouter(SS_ROUTER),
            IVerifier(EXISTING_WITHDRAW_VERIFIER),
            IVerifier(EXISTING_SWAP_VERIFIER),
            20,
            IHasher(EXISTING_HASHER)
        );
        console.log("Deployed Pool TokenA_10:           ", address(poolA10));

        // Deploy Pool 3 - TokenB, 10 denomination
        
        ShieldPool poolB10 = new ShieldPool(
            IERC20(TOKEN_B),
            10 * 1e18,
            ISSRouter(SS_ROUTER),
            IVerifier(EXISTING_WITHDRAW_VERIFIER),
            IVerifier(EXISTING_SWAP_VERIFIER),
            20,
            IHasher(EXISTING_HASHER)
        );
        console.log("Deployed Pool TokenB_10:           ", address(poolB10));

        // Deploy Pool 4 - TokenB, 1 denomination
        
        ShieldPool poolB1 = new ShieldPool(
            IERC20(TOKEN_B),
            1 * 1e18,
            ISSRouter(SS_ROUTER),
            IVerifier(EXISTING_WITHDRAW_VERIFIER),
            IVerifier(EXISTING_SWAP_VERIFIER),
            20,
            IHasher(EXISTING_HASHER)
        );
        console.log("Deployed Pool TokenB_1:            ", address(poolB1));

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("Copy these addresses to your constants.ts:");
        console.log("");
        console.log("ShieldPools: {");
        console.log("  TokenA_100: \"", EXISTING_POOL_A100, "\",");
        console.log("  TokenA_10:  \"", address(poolA10), "\",");
        console.log("  TokenB_10:  \"", address(poolB10), "\",");
        console.log("  TokenB_1:   \"", address(poolB1), "\"");
        console.log("}");
        console.log("");
    }
}
