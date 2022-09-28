// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {WaterfallModuleFactory} from "../src/WaterfallModuleFactory.sol";
import {WaterfallModule} from "../src/WaterfallModule.sol";
import {WaterfallReentrancy} from "./WaterfallReentrancy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract WaterfallModuleFactoryTest is Test {
    event CreateWaterfallModule(
        address indexed waterfallModule,
        address token,
        address nonWaterfallRecipient,
        address[] trancheRecipient,
        uint256[] trancheThreshold
    );

    address internal constant ETH_ADDRESS = address(0);

    WaterfallModuleFactory wmf;
    MockERC20 mERC20;

    address public nonWaterfallRecipient;
    address[] public recipients;
    uint256[] public thresholds;

    function setUp() public {
        mERC20 = new MockERC20("Test Token", "TOK", 18);
        mERC20.mint(type(uint256).max);

        wmf = new WaterfallModuleFactory();

        nonWaterfallRecipient = makeAddr("nonWaterfallRecipient");
        (recipients, thresholds) = generateTranches(2);
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
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );

        nonWaterfallRecipient = address(0);
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCan_emitOnCreate() public {
        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead),
            ETH_ADDRESS,
            nonWaterfallRecipient,
            recipients,
            thresholds
            );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead),
            address(mERC20),
            nonWaterfallRecipient,
            recipients,
            thresholds
            );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );

        nonWaterfallRecipient = address(0);

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead),
            ETH_ADDRESS,
            nonWaterfallRecipient,
            recipients,
            thresholds
            );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead),
            address(mERC20),
            nonWaterfallRecipient,
            recipients,
            thresholds
            );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithTooFewRecipients() public {
        (recipients, thresholds) = generateTranches(1);

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__TooFewRecipients.selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        recipients = generateTrancheRecipients(0);

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__TooFewRecipients.selector
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithMismatchedLengths() public {
        recipients = generateTrancheRecipients(2);
        thresholds = generateTrancheThresholds(2);

        vm.expectRevert(
            WaterfallModuleFactory
                .InvalidWaterfall__RecipientsAndThresholdsLengthMismatch
                .selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        recipients = generateTrancheRecipients(3);
        thresholds = generateTrancheThresholds(1);

        vm.expectRevert(
            WaterfallModuleFactory
                .InvalidWaterfall__RecipientsAndThresholdsLengthMismatch
                .selector
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithZeroThreshold() public {
        thresholds[0] = 0;

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__ZeroThreshold.selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__ZeroThreshold.selector
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithTooLargeThreshold() public {
        (recipients, thresholds) = generateTranches(3);
        for (uint256 i = 0; i < thresholds.length; i++) {
            thresholds[i] <<= 96;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdTooLarge
                    .selector,
                0
            )
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        thresholds[0] = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdTooLarge
                    .selector,
                1
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithThresholdOutOfOrder() public {
        (recipients, thresholds) = generateTranches(4);
        for (uint256 i = 0; i < thresholds.length; i++) {
            thresholds[i] = (thresholds.length - i) * 1 ether;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdsOutOfOrder
                    .selector,
                1
            )
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        thresholds[1] = thresholds[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdsOutOfOrder
                    .selector,
                1
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );

        thresholds[1] = thresholds[0] + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdsOutOfOrder
                    .selector,
                2
            )
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - fuzzing
    /// -----------------------------------------------------------------------

    function testCan_createWaterfallModules(
        address _nonWaterfallRecipient,
        uint8 _numTranches
    ) public {
        nonWaterfallRecipient = _nonWaterfallRecipient;
        uint256 numTranches = bound(_numTranches, 2, type(uint8).max);

        (recipients, thresholds) = generateTranches(numTranches);

        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCan_emitOnCreate(
        address _nonWaterfallRecipient,
        uint8 _numTranches
    ) public {
        nonWaterfallRecipient = _nonWaterfallRecipient;
        uint256 numTranches = bound(_numTranches, 2, type(uint8).max);

        (recipients, thresholds) = generateTranches(numTranches);

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead),
            ETH_ADDRESS,
            nonWaterfallRecipient,
            recipients,
            thresholds
            );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead),
            address(mERC20),
            nonWaterfallRecipient,
            recipients,
            thresholds
            );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithMismatchedLengths(
        uint8 _numRecipients,
        uint8 _numThresholds
    ) public {
        vm.assume(_numRecipients >= 2);
        vm.assume(_numThresholds >= 1);
        vm.assume(_numRecipients - 1 != _numThresholds);

        recipients = generateTrancheRecipients(_numRecipients);
        thresholds = generateTrancheThresholds(_numThresholds);

        vm.expectRevert(
            WaterfallModuleFactory
                .InvalidWaterfall__RecipientsAndThresholdsLengthMismatch
                .selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        vm.expectRevert(
            WaterfallModuleFactory
                .InvalidWaterfall__RecipientsAndThresholdsLengthMismatch
                .selector
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithZeroThreshold(uint8 _numTranches) public {
        uint256 numTranches = bound(_numTranches, 2, type(uint8).max);

        (recipients, thresholds) = generateTranches(numTranches);
        thresholds[0] = 0;

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__ZeroThreshold.selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__ZeroThreshold.selector
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithTooLargeThreshold(
        uint8 _numTranches,
        uint8 _largeThresholdIndex,
        uint160 _largeThreshold
    ) public {
        uint256 numTranches = bound(_numTranches, 2, type(uint8).max);
        uint256 largeThresholdIndex =
            bound(_largeThresholdIndex, 0, numTranches - 2);
        vm.assume(_largeThreshold > 0);
        uint256 largeThreshold = uint256(_largeThreshold) << 96;

        (recipients, thresholds) = generateTranches(numTranches);

        thresholds[largeThresholdIndex] = largeThreshold;

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdTooLarge
                    .selector,
                largeThresholdIndex
            )
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdTooLarge
                    .selector,
                largeThresholdIndex
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    function testCannot_createWithThresholdOutOfOrder(
        uint8 _numTranches,
        uint8 _swapIndex
    ) public {
        uint256 numTranches = bound(_numTranches, 3, type(uint8).max);
        uint256 swapIndex = bound(_swapIndex, 1, numTranches - 2);

        (recipients, thresholds) = generateTranches(numTranches);

        (thresholds[swapIndex], thresholds[swapIndex - 1]) =
            (thresholds[swapIndex - 1], thresholds[swapIndex]);

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdsOutOfOrder
                    .selector,
                swapIndex
            )
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdsOutOfOrder
                    .selector,
                swapIndex
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );

        /// test equal thresholds

        thresholds[swapIndex - 1] = thresholds[swapIndex];

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdsOutOfOrder
                    .selector,
                swapIndex
            )
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, nonWaterfallRecipient, recipients, thresholds
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory
                    .InvalidWaterfall__ThresholdsOutOfOrder
                    .selector,
                swapIndex
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), nonWaterfallRecipient, recipients, thresholds
        );
    }

    /// -----------------------------------------------------------------------
    /// helper fns
    /// -----------------------------------------------------------------------

    function generateTranches(uint256 numTranches)
        internal
        pure
        returns (address[] memory _recipients, uint256[] memory _thresholds)
    {
        _recipients = generateTrancheRecipients(numTranches);
        _thresholds = generateTrancheThresholds(numTranches - 1);
    }

    function generateTrancheRecipients(uint256 numRecipients)
        internal
        pure
        returns (address[] memory _recipients)
    {
        _recipients = new address[](numRecipients);
        for (uint256 i = 0; i < numRecipients; i++) {
            _recipients[i] = address(uint160(i));
        }
    }

    function generateTrancheThresholds(uint256 numThresholds)
        internal
        pure
        returns (uint256[] memory _thresholds)
    {
        _thresholds = new uint256[](numThresholds);
        for (uint256 i = 0; i < numThresholds; i++) {
            _thresholds[i] = (i + 1) * 1 ether;
        }
    }
}
