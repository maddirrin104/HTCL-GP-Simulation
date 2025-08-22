// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol"; 
import "../src/HashedTimelockERC20.sol";

contract DeployHashedTimelock is Script {
    function run() external {
        // Lấy private key từ env (PRIVATE_KEY)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy contract
        HashedTimelockERC20 htcl = new HashedTimelockERC20();

        console.log("HashedTimelockERC20 deployed at:", address(htcl));

        vm.stopBroadcast();
    }
}
