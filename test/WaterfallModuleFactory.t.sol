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
    WaterfallModule wmETH;
    WaterfallModule wmERC20;
    MockERC20 mERC20;

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

        wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipient, _trancheThreshold
        );

        wmf.createWaterfallModule(
            address(mERC20), _trancheRecipient, _trancheThreshold
        );
    }

    function testCan_emitOnCreate() public {
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

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead), ETH_ADDRESS, _trancheRecipient, _trancheThreshold
            );
        wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipient, _trancheThreshold
        );

        // don't check deploy address
        vm.expectEmit(false, true, true, true);
        emit CreateWaterfallModule(
            address(0xdead), address(mERC20), _trancheRecipient, _trancheThreshold
            );
        wmf.createWaterfallModule(
            address(mERC20), _trancheRecipient, _trancheThreshold
        );
    }

    function testCannot_createWithTooFewRecipients() public {
        uint256 _trancheRecipientLength = 1;
        address[] memory _trancheRecipient =
            new address[](_trancheRecipientLength);
        for (uint256 i = 0; i < _trancheRecipientLength; i++) {
            _trancheRecipient[i] = address(uint160(i));
        }
        uint256 _trancheThresholdLength = _trancheRecipientLength - 1;
        uint256[] memory _trancheThreshold =
            new uint256[](_trancheThresholdLength);
        for (uint256 i = 0; i < _trancheThresholdLength; i++) {
            _trancheThreshold[i] = (i + 1) << 96;
        }

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__TooFewRecipients.selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipient, _trancheThreshold
        );

        _trancheRecipientLength = 0;
        _trancheRecipient = new address[](_trancheRecipientLength);
        for (uint256 i = 0; i < _trancheRecipientLength; i++) {
            _trancheRecipient[i] = address(uint160(i));
        }
        _trancheThresholdLength = 0;
        _trancheThreshold = new uint256[](_trancheThresholdLength);
        for (uint256 i = 0; i < _trancheThresholdLength; i++) {
            _trancheThreshold[i] = (i + 1) << 96;
        }

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__TooFewRecipients.selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipient, _trancheThreshold
        );
    }

    function testCannot_createWithMismatchedLengths() public {
        uint256 _trancheRecipientLength = 2;
        address[] memory _trancheRecipient =
            new address[](_trancheRecipientLength);
        for (uint256 i = 0; i < _trancheRecipientLength; i++) {
            _trancheRecipient[i] = address(uint160(i));
        }
        uint256 _trancheThresholdLength = 2;
        uint256[] memory _trancheThreshold =
            new uint256[](_trancheThresholdLength);
        for (uint256 i = 0; i < _trancheThresholdLength; i++) {
            _trancheThreshold[i] = (i + 1) << 96;
        }

        vm.expectRevert(
            WaterfallModuleFactory
                .InvalidWaterfall__RecipientsAndThresholdsLengthMismatch
                .selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipient, _trancheThreshold
        );

        _trancheRecipientLength = 3;
        _trancheRecipient = new address[](_trancheRecipientLength);
        for (uint256 i = 0; i < _trancheRecipientLength; i++) {
            _trancheRecipient[i] = address(uint160(i));
        }
        _trancheThresholdLength = 1;
        _trancheThreshold = new uint256[](_trancheThresholdLength);
        for (uint256 i = 0; i < _trancheThresholdLength; i++) {
            _trancheThreshold[i] = (i + 1) << 96;
        }

        vm.expectRevert(
            WaterfallModuleFactory
                .InvalidWaterfall__RecipientsAndThresholdsLengthMismatch
                .selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipient, _trancheThreshold
        );
    }

    function testCannot_createWithZeroThreshold() public {
        uint256 _trancheRecipientLength = 2;
        address[] memory _trancheRecipient =
            new address[](_trancheRecipientLength);
        for (uint256 i = 0; i < _trancheRecipientLength; i++) {
            _trancheRecipient[i] = address(uint160(i));
        }
        uint256 _trancheThresholdLength = 1;
        uint256[] memory _trancheThreshold =
            new uint256[](_trancheThresholdLength);

        vm.expectRevert(
            WaterfallModuleFactory.InvalidWaterfall__ZeroThreshold.selector
        );
        wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipient, _trancheThreshold
        );
    }

    function testCannot_createWithTooLargeThreshold() public {
        uint256 _trancheRecipientLength = 3;
        address[] memory _trancheRecipient =
            new address[](_trancheRecipientLength);
        for (uint256 i = 0; i < _trancheRecipientLength; i++) {
            _trancheRecipient[i] = address(uint160(i));
        }
        uint256 _trancheThresholdLength = _trancheRecipientLength - 1;
        uint256[] memory _trancheThreshold =
            new uint256[](_trancheThresholdLength);
        for (uint256 i = 0; i < _trancheThresholdLength; i++) {
            _trancheThreshold[i] = (i + 1) << 96;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory.InvalidWaterfall__ThresholdTooLarge.selector, 0
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), _trancheRecipient, _trancheThreshold
        );

        _trancheThreshold[0] = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory.InvalidWaterfall__ThresholdTooLarge.selector, 1
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), _trancheRecipient, _trancheThreshold
        );
    }

    function testCannot_createWithThresholdOutOfOrder() public {
        uint256 _trancheRecipientLength = 4;
        address[] memory _trancheRecipient =
            new address[](_trancheRecipientLength);
        for (uint256 i = 0; i < _trancheRecipientLength; i++) {
            _trancheRecipient[i] = address(uint160(i));
        }
        uint256 _trancheThresholdLength = _trancheRecipientLength - 1;
        uint256[] memory _trancheThreshold =
            new uint256[](_trancheThresholdLength);
        for (uint256 i = 0; i < _trancheThresholdLength; i++) {
            _trancheThreshold[i] = _trancheRecipientLength - i;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory.InvalidWaterfall__ThresholdsOutOfOrder.selector, 1
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), _trancheRecipient, _trancheThreshold
        );

        _trancheThreshold[1] = _trancheRecipientLength + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                WaterfallModuleFactory.InvalidWaterfall__ThresholdsOutOfOrder.selector, 2
            )
        );
        wmf.createWaterfallModule(
            address(mERC20), _trancheRecipient, _trancheThreshold
        );
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - fuzzing
    /// -----------------------------------------------------------------------
}
