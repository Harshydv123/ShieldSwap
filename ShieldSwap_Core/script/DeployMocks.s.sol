// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../test/test_AMM/mocks/MockERC20.sol"; 

contract DeployMocks is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        MockERC20 tokenA = new MockERC20("MockTokenA", "mTKA");
        MockERC20 tokenB = new MockERC20("MockTokenB", "mTKB");

        tokenA.mint(deployer, 10_000 * 1e18);
        tokenB.mint(deployer,   300 * 1e18);

        vm.stopBroadcast();

        console.log("=== MOCK TOKENS DEPLOYED ===");
        console.log("MockTokenA: ", address(tokenA));
        console.log("MockTokenB: ", address(tokenB));
        console.log("Deployer:   ", deployer);
        console.log("============================");
    }
}