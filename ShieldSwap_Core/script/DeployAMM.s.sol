// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/AMM_Part/SSFactory.sol";
import "../src/AMM_Part/SSRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployAMM is Script {
    address constant TOKEN_A = 0x68df70070872b49670190c9c6f77478Fc9Bc2f48;
    address constant TOKEN_B = 0x4474bD760d67a8a67e78Cea49886deFd4C8Ce34e;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Deploy SSFactory
        SSFactory factory = new SSFactory();

        // 2. Deploy SSRouter with factory address
        SSRouter router = new SSRouter(address(factory));

        // 3. Create TokenA/TokenB trading pair
        address pair = factory.createPair(TOKEN_A, TOKEN_B);

        // 4. Add initial liquidity
        // Ratio: 1000 tokenA : 29 tokenB
        // This mirrors ETH/BTC price ratio (~0.029)
        // So Chainlink feeds will roughly match pool price
        uint256 amountA = 1_000 * 1e18;
        uint256 amountB = 29   * 1e18;

        // Approve router to spend both tokens
        IERC20(TOKEN_A).approve(address(router), amountA);
        IERC20(TOKEN_B).approve(address(router), amountB);

        // Add liquidity — LP tokens go to deployer
        router.addLiquidity(
            TOKEN_A,
            TOKEN_B,
            amountA,           // desired tokenA
            amountB,           // desired tokenB
            amountA * 99 / 100, // min tokenA (1% slippage)
            amountB * 99 / 100, // min tokenB (1% slippage)
            deployer          // LP token recipient
        );

        vm.stopBroadcast();

        // ── SAVE THESE ADDRESSES ──────────────────────────
        console.log("=== AMM DEPLOYED ===");
        console.log("SSFactory:  ", address(factory));
        console.log("SSRouter:   ", address(router));
        console.log("SSPair:     ", pair);
        console.log("Liquidity:   1000 tokenA + 29 tokenB");
        console.log("====================");
    }
}