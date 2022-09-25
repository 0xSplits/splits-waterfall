// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {WaterfallModule} from "../src/WaterfallModule.sol";

contract WaterfallReentrancy {
    receive() external payable {
        if (address(this).balance <= 1 ether) {
            WaterfallModule(msg.sender).waterfallFunds();
        }
    }
}
