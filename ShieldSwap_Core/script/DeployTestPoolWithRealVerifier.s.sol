// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Privacy_Part/ShieldPool.sol";
import "../src/Privacy_Part/MiMCHasher.sol";

contract DeployTestPoolWithRealVerifier is Script {
    address constant TOKEN_A = 0x68df70070872b49670190c9c6f77478Fc9Bc2f48;
    address constant SS_ROUTER = 0xfeb4141299997bE4EDE9b012A5bbAe171eE44c6f;
    address constant HASHER = 0x0e39E0a7c051cDbe82Bb01D6827BD65140f8E87e;
    
    // ← PUT YOUR VERIFIER WRAPPER ADDRESS HERE
    address constant REAL_VERIFIER = 0x784DaD40f9c5Cc1E60f3095A455b6aBA83a58106;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerKey);
        
        // Deploy ONE test pool with REAL verifier
        ShieldPool testPool = new ShieldPool(
            IERC20(TOKEN_A),
            1 * 1e18,  // 1 TokenA (small amount for testing)
            ISSRouter(SS_ROUTER),
            IVerifier(REAL_VERIFIER),  // ← Real verifier!
            IVerifier(REAL_VERIFIER),  // ← Real verifier for swaps too!
            20,
            IHasher(HASHER)
        );
        
        console.log("Test Pool with Real Verifier:", address(testPool));
        
        vm.stopBroadcast();
    }
}