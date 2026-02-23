// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Privacy_Part/Verifier.sol";
import "../src/Privacy_Part/VerifierWrapper.sol";

contract DeployRealVerifier is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerKey);
        
        console.log("Deploying Real Groth16 Verifier...");
        
        // Deploy the Groth16 verifier
        Groth16Verifier verifier = new Groth16Verifier();
        console.log("Groth16Verifier:", address(verifier));
        
        // Deploy the wrapper
        VerifierWrapper wrapper = new VerifierWrapper(address(verifier));
        console.log("VerifierWrapper:", address(wrapper));
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== USE THIS ADDRESS ===");
        console.log("Real Verifier:", address(wrapper));
        console.log("");
    }
}