// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {Script} from "forge-std/Script.sol";

contract DeployDecentralizedStableCoin is Script {
    function run() external returns (DecentralizedStableCoin) {
        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        vm.stopBroadcast();
        return dsc;
    }
}
