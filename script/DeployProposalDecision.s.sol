// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import { ProposalDecision } from "../src/ProposalDecision.sol";

contract DeployScript is Script {
    address constant ENTROPY_ADDRESS_OP = 0xdF21D137Aadc95588205586636710ca2890538d5;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        ProposalDecision decision = new ProposalDecision(ENTROPY_ADDRESS_OP, msg.sender);

        vm.stopBroadcast();
    }
}
