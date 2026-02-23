// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Privacy_Part/ShieldPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestDeposit is Script {

    // ── Your deployed addresses ───────────────────────────
    address constant TOKEN_A     = 0x68df70070872b49670190c9c6f77478Fc9Bc2f48;
    address constant SHIELD_POOL = 0xa9d547007B9ce930dde76Ce038ce2f0aa53F1F5E;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        ShieldPool pool = ShieldPool(SHIELD_POOL);

        // Generate commitment from nullifier + secret
        bytes32 nullifier  = keccak256(abi.encodePacked("shieldswap-nullifier-001"));
        bytes32 secret     = keccak256(abi.encodePacked("shieldswap-secret-001"));
        bytes32 commitment = keccak256(abi.encodePacked(nullifier, secret));

        // nullifierHash = what ShieldPool stores publicly
        bytes32 nullifierHash = keccak256(abi.encodePacked(nullifier));

        console.log("=== DEPOSIT PARAMS ===");
        console.log("Nullifier:");
        console.logBytes32(nullifier);
        console.log("Secret:");
        console.logBytes32(secret);
        console.log("Commitment:");
        console.logBytes32(commitment);
        console.log("NullifierHash:");
        console.logBytes32(nullifierHash);

        // Approve pool to spend 100 tokenA
        IERC20(TOKEN_A).approve(SHIELD_POOL, 100 * 1e18);

        // Deposit
        pool.deposit(commitment);

        console.log("=== DEPOSIT SUCCESSFUL ===");
        console.log("Total deposits:", pool.totalDeposits());

        vm.stopBroadcast();
    }
}