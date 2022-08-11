// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import {WaterfallModuleFactory} from "../src/WaterfallModuleFactory.sol";

contract WaterfallModuleFactoryScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        WaterfallModuleFactory wmf = new WaterfallModuleFactory();

        vm.stopBroadcast();
    }
}
