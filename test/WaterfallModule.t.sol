// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {WaterfallModule} from "../src/WaterfallModule.sol";

contract ContractTest is Test {
    using SafeTransferLib for address;

    WaterfallModule wm;

    event ReceiveETH(uint256 amount);

    function setUp() public {
        uint256 _trancheRecipientLength = 2;
        address[] memory _trancheRecipient =
            new address[](_trancheRecipientLength);
        for (uint256 i = 0; i < _trancheRecipientLength; i++) {
            _trancheRecipient[i] = address(uint160(i));
        }
        uint256 _trancheThresholdLength = _trancheRecipientLength - 1;
        uint256[] memory _trancheThreshold =
            new uint256[](_trancheThresholdLength);
        for (uint256 i = 0; i < _trancheThresholdLength; i++) {
            _trancheThreshold[i] = (i + 1) * 1 ether;
        }
        wm = new WaterfallModule(_trancheRecipient, _trancheThreshold);
    }

    /// -----------------------------------------------------------------------
    /// gas benchmarks
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// correctness tests
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// basic tests
    /// -----------------------------------------------------------------------

    function testCan_receiveETH() public {
        address(wm).safeTransferETH(1 ether);
        assertEq(address(wm).balance, 1 ether);
    }

    function testCan_emitOnReceiveETH() public {
        vm.expectEmit(true, true, true, true);
        emit ReceiveETH(1 ether);

        address(wm).safeTransferETH(1 ether);
    }

    function testCan_waterfallETHToNoRecipients() public {
        wm.waterfallFunds();

        // TODO: check event
        assertEq(address(0).balance, 0 ether);
    }

    function testCan_waterfallETHPayable() public {
        wm.waterfallFunds{value: 2 ether}();

        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1 ether);
    }

    function testCan_waterfallETHToFirstRecipient() public {
        address(wm).safeTransferETH(1 ether);

        wm.waterfallFunds();

        assertEq(address(0).balance, 1 ether);

        wm.waterfallFunds();

        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 0 ether);
    }

    function testCan_waterfallMultipleETHToFirstRecipient() public {
        address(wm).safeTransferETH(0.5 ether);
        wm.waterfallFunds();

        assertEq(address(0).balance, 0.5 ether);

        address(wm).safeTransferETH(0.5 ether);
        wm.waterfallFunds();

        assertEq(address(0).balance, 1 ether);
    }

    function testCan_waterfallETHToSecondRecipient() public {
        address(wm).safeTransferETH(2 ether);

        wm.waterfallFunds();

        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1 ether);
    }

    function testCan_waterfallMultipleETHToSecondRecipient() public {
        address(wm).safeTransferETH(1 ether);
        wm.waterfallFunds();

        address(wm).safeTransferETH(1 ether);
        wm.waterfallFunds();

        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1 ether);
    }

    function testCan_waterfallETHToResidualRecipient() public {
        address(wm).safeTransferETH(100 ether);
        wm.waterfallFunds();

        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 99 ether);
    }

    /// -----------------------------------------------------------------------
    /// fuzz tests
    /// -----------------------------------------------------------------------
}
