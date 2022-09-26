// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {WaterfallModuleFactory} from "../src/WaterfallModuleFactory.sol";

contract WaterfallModuleFactoryScript is Script {
    function run() external {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);

        new WaterfallModuleFactory{salt: keccak256("0xSplits.waterfall.v1")}();

        vm.stopBroadcast();
    }
}
