// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {WaterfallModuleFactory} from "../src/WaterfallModuleFactory.sol";
import {WaterfallModule} from "../src/WaterfallModule.sol";
import {WaterfallReentrancy} from "./WaterfallReentrancy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

// TODO: add fuzzing testing
// https://book.getfoundry.sh/reference/forge-std/bound
// https://github.com/PraneshASP/forge-template/blob/main/src/test/utils/Utils.sol

contract WaterfallModuleFactoryTest is Test {
    event CreateWaterfallModule(
        address indexed waterfallModule,
        address token,
        address[] trancheRecipient,
        uint256[] trancheThreshold
    );

    address internal constant ETH_ADDRESS = address(0);

    WaterfallModuleFactory wmf;
    MockERC20 mERC20;

    function setUp() public {
        mERC20 = new MockERC20("Test Token", "TOK", 18);
        mERC20.mint(type(uint256).max);

        wmf = new WaterfallModuleFactory();
    }

    /// -----------------------------------------------------------------------
    /// gas benchmarks
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// correctness tests
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// correctness tests - basic
    /// -----------------------------------------------------------------------

    function testCan_createWaterfallModules() public {
        (address[] memory _trancheRecipients, uint256[] memory _trancheThresholds) =
            generateTranches(2);

        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);

        wmf.createWaterfallModule(address(mERC20), _trancheRecipients, _trancheThresholds);
    }

    function testCan_emitOnCreate() public {
        (address[] memory _trancheRecipients, uint256[] memory _trancheThresholds) =
            generateTranches(2);

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead), ETH_ADDRESS, _trancheRecipients, _trancheThresholds
            );
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead), address(mERC20), _trancheRecipients, _trancheThresholds
            );
        wmf.createWaterfallModule(address(mERC20), _trancheRecipients, _trancheThresholds);
    }

    function testCannot_createWithTooFewRecipients() public {
        (address[] memory _trancheRecipients, uint256[] memory _trancheThresholds) =
            generateTranches(1);

        vm.expectRevert(WaterfallModuleFactory.InvalidWaterfall__TooFewRecipients.selector);
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);

        _trancheRecipients = generateTrancheRecipients(0);

        vm.expectRevert(WaterfallModuleFactory.InvalidWaterfall__TooFewRecipients.selector);
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);
    }

    function testCannot_createWithMismatchedLengths() public {
        address[] memory _trancheRecipients = generateTrancheRecipients(2);
        uint256[] memory _trancheThresholds = generateTrancheThresholds(2);

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__RecipientsAndThresholdsLengthMismatch.selector
        );
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);

        _trancheRecipients = generateTrancheRecipients(3);
        _trancheThresholds = generateTrancheThresholds(1);

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__RecipientsAndThresholdsLengthMismatch.selector
        );
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);
    }

    function testCannot_createWithZeroThreshold() public {
        (address[] memory _trancheRecipients, uint256[] memory _trancheThresholds) =
            generateTranches(2);
        _trancheThresholds[0] = 0;

        vm.expectRevert(WaterfallModuleFactory.InvalidWaterfall__ZeroThreshold.selector);
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);
    }

    function testCannot_createWithTooLargeThreshold() public {
        (address[] memory _trancheRecipients, uint256[] memory _trancheThresholds) =
            generateTranches(3);
        for (uint256 i = 0; i < _trancheThresholds.length; i++) {
            _trancheThresholds[i] <<= 96;
        }

        vm.expectRevert(
            abi.encodeWithSelector(WaterfallModuleFactory.InvalidWaterfall__ThresholdTooLarge.selector, 0)
        );
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);

        _trancheThresholds[0] = 1;
        vm.expectRevert(
            abi.encodeWithSelector(WaterfallModuleFactory.InvalidWaterfall__ThresholdTooLarge.selector, 1)
        );
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);
    }

    function testCannot_createWithThresholdOutOfOrder() public {
        (address[] memory _trancheRecipients, uint256[] memory _trancheThresholds) =
            generateTranches(4);
        for (uint256 i = 0; i < _trancheThresholds.length; i++) {
            _trancheThresholds[i] = (_trancheThresholds.length - i) * 1 ether;
        }

        vm.expectRevert(
            abi.encodeWithSelector(WaterfallModuleFactory.InvalidWaterfall__ThresholdsOutOfOrder.selector, 1)
        );
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);

        _trancheThresholds[1] = _trancheThresholds[0];
        vm.expectRevert(
            abi.encodeWithSelector(WaterfallModuleFactory.InvalidWaterfall__ThresholdsOutOfOrder.selector, 1)
        );
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);

        _trancheThresholds[1] = _trancheThresholds[0] + 1;
        vm.expectRevert(
            abi.encodeWithSelector(WaterfallModuleFactory.InvalidWaterfall__ThresholdsOutOfOrder.selector, 2)
        );
        wmf.createWaterfallModule(ETH_ADDRESS, _trancheRecipients, _trancheThresholds);
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - fuzzing
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// helper fns
    /// -----------------------------------------------------------------------

    function generateTranches(uint256 numTranches)
        internal
        pure
        returns (address[] memory recipients, uint256[] memory thresholds)
    {
        recipients = generateTrancheRecipients(numTranches);
        thresholds = generateTrancheThresholds(numTranches - 1);
    }

    function generateTrancheRecipients(uint256 numRecipients)
        internal
        pure
        returns (address[] memory recipients)
    {
        recipients = new address[](numRecipients);
        for (uint256 i = 0; i < numRecipients; i++) {
            recipients[i] = address(uint160(i));
        }
    }

    function generateTrancheThresholds(uint256 numThresholds)
        internal
        pure
        returns (uint256[] memory thresholds)
    {
        thresholds = new uint256[](numThresholds);
        for (uint256 i = 0; i < numThresholds; i++) {
            thresholds[i] = (i + 1) * 1 ether;
        }
    }
}
