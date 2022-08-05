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

contract WaterfallModuleTest is Test {
    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    event CreateWaterfallModule(
        address indexed waterfallModule,
        address token,
        address[] trancheRecipient,
        uint256[] trancheThreshold
    );

    event ReceiveETH(uint256 amount);

    event WaterfallFunds(address[] recipients, uint256[] payouts);

    event RecoverNonWaterfallFunds(
        address nonWaterfallToken,
        address recipient,
        uint256 amount
    );

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
        wmETH = wmf.createWaterfallModule(
            address(0), _trancheRecipient, _trancheThreshold
        );
        wmERC20 = wmf.createWaterfallModule(
            address(mERC20), _trancheRecipient, _trancheThreshold
        );
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

    function testCan_getTranches() public {
        (address[] memory trancheRecipients, uint256[] memory trancheThresholds)
            = wmETH.getTranches();

        for (uint256 i = 0; i < trancheRecipients.length; i++) {
            assertEq(trancheRecipients[i], address(uint160(i)));
        }
        for (uint256 i = 0; i < trancheThresholds.length; i++) {
            assertEq(trancheThresholds[i], (i + 1) * 1 ether);
        }
    }

    function testCan_receiveETH() public {
        address(wmETH).safeTransferETH(1 ether);
        assertEq(address(wmETH).balance, 1 ether);

        address(wmERC20).safeTransferETH(1 ether);
        assertEq(address(wmERC20).balance, 1 ether);
    }

    function testCan_emitOnReceiveETH() public {
        vm.expectEmit(true, true, true, true);
        emit ReceiveETH(1 ether);

        address(wmETH).safeTransferETH(1 ether);
    }

    function testCan_receiveERC20() public {
        ERC20(mERC20).safeTransfer(address(wmETH), 1 ether);
        assertEq(ERC20(mERC20).balanceOf(address(wmETH)), 1 ether);

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);
        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 1 ether);
    }

    function testCan_recoverNonWaterfallFundsToRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        ERC20(mERC20).safeTransfer(address(wmETH), 1 ether);

        wmETH.recoverNonWaterfallFunds(address(mERC20), address(0));
        assertEq(address(wmETH).balance, 1 ether);
        assertEq(ERC20(mERC20).balanceOf(address(wmETH)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(0)), 1 ether);

        ERC20(mERC20).safeTransfer(address(wmETH), 1 ether);

        wmETH.recoverNonWaterfallFunds(address(mERC20), address(1));
        assertEq(address(wmETH).balance, 1 ether);
        assertEq(ERC20(mERC20).balanceOf(address(wmETH)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(1)), 1 ether);

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);
        address(wmERC20).safeTransferETH(1 ether);

        wmERC20.recoverNonWaterfallFunds(address(0), address(0));
        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 1 ether);
        assertEq(address(wmERC20).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);

        address(wmERC20).safeTransferETH(1 ether);

        wmERC20.recoverNonWaterfallFunds(address(0), address(1));
        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 1 ether);
        assertEq(address(wmERC20).balance, 0 ether);
        assertEq(address(1).balance, 1 ether);
    }

    function testCan_emitOnRecoverNonWaterfallFundsToRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        ERC20(mERC20).safeTransfer(address(wmETH), 1 ether);

        vm.expectEmit(true, true, true, true);
        emit RecoverNonWaterfallFunds(address(mERC20), address(1), 1 ether);
        wmETH.recoverNonWaterfallFunds(address(mERC20), address(1));

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);
        address(wmERC20).safeTransferETH(1 ether);

        vm.expectEmit(true, true, true, true);
        emit RecoverNonWaterfallFunds(address(0), address(1), 1 ether);
        wmERC20.recoverNonWaterfallFunds(address(0), address(1));
    }

    function testCannot_recoverNonWaterfallFundsToNonRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        ERC20(mERC20).safeTransfer(address(wmETH), 1 ether);

        vm.expectRevert(
            WaterfallModule.InvalidTokenRecovery_InvalidRecipient.selector
        );
        wmETH.recoverNonWaterfallFunds(address(mERC20), address(2));

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);
        address(wmERC20).safeTransferETH(1 ether);

        vm.expectRevert(
            WaterfallModule.InvalidTokenRecovery_InvalidRecipient.selector
        );
        wmERC20.recoverNonWaterfallFunds(address(0), address(2));
    }

    function testCannot_recoverWaterfallFunds() public {
        address(wmETH).safeTransferETH(1 ether);
        ERC20(mERC20).safeTransfer(address(wmETH), 1 ether);

        vm.expectRevert(
            WaterfallModule.InvalidTokenRecovery_WaterfallToken.selector
        );
        wmETH.recoverNonWaterfallFunds(address(0), address(0));

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);
        address(wmERC20).safeTransferETH(1 ether);

        vm.expectRevert(
            WaterfallModule.InvalidTokenRecovery_WaterfallToken.selector
        );
        wmERC20.recoverNonWaterfallFunds(address(mERC20), address(0));
    }

    function testCan_waterfallIsPayable() public {
        wmETH.waterfallFunds{value: 2 ether}();

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1 ether);
    }

    function testCan_waterfallToNoRecipients() public {
        wmETH.waterfallFunds();
        assertEq(address(0).balance, 0 ether);

        wmERC20.waterfallFunds();
        assertEq(ERC20(mERC20).balanceOf(address(0)), 0 ether);
    }

    function testCan_emitOnWaterfallToNoRecipients() public {
        vm.expectEmit(true, true, true, true);
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint256[] memory payouts = new uint256[](1);
        payouts[0] = 0 ether;
        emit WaterfallFunds(recipients, payouts);
        wmETH.waterfallFunds();
    }

    function testCan_waterfallToFirstRecipient() public {
        address(wmETH).safeTransferETH(1 ether);

        wmETH.waterfallFunds();
        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);

        wmETH.waterfallFunds();
        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 0 ether);

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);

        wmERC20.waterfallFunds();
        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(0)), 1 ether);

        wmERC20.waterfallFunds();
        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(0)), 1 ether);
        assertEq(ERC20(mERC20).balanceOf(address(1)), 0 ether);
    }

    function testCan_emitOnWaterfallToFirstRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint256[] memory payouts = new uint256[](1);
        payouts[0] = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts);
        wmETH.waterfallFunds();

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);

        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts);
        wmERC20.waterfallFunds();
    }

    function testCan_waterfallMultipleDepositsToFirstRecipient() public {
        address(wmETH).safeTransferETH(0.5 ether);
        wmETH.waterfallFunds();
        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 0.5 ether);

        address(wmETH).safeTransferETH(0.5 ether);
        wmETH.waterfallFunds();
        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);

        ERC20(mERC20).safeTransfer(address(wmERC20), 0.5 ether);
        wmERC20.waterfallFunds();
        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(0)), 0.5 ether);

        ERC20(mERC20).safeTransfer(address(wmERC20), 0.5 ether);
        wmERC20.waterfallFunds();
        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(0)), 1 ether);
    }

    function testCan_waterfallToBothRecipients() public {
        address(wmETH).safeTransferETH(2 ether);
        wmETH.waterfallFunds();
        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1 ether);

        ERC20(mERC20).safeTransfer(address(wmERC20), 2 ether);
        wmERC20.waterfallFunds();
        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(0)), 1 ether);
        assertEq(ERC20(mERC20).balanceOf(address(1)), 1 ether);
    }

    function testCan_emitOnWaterfallToBothRecipients() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(0);
        recipients[1] = address(1);
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1 ether;
        payouts[1] = 1 ether;

        address(wmETH).safeTransferETH(2 ether);
        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts);
        wmETH.waterfallFunds();

        ERC20(mERC20).safeTransfer(address(wmERC20), 2 ether);
        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts);
        wmERC20.waterfallFunds();
    }

    function testCan_waterfallMultipleDepositsToSecondRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        wmETH.waterfallFunds();

        address(wmETH).safeTransferETH(1 ether);
        wmETH.waterfallFunds();

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1 ether);

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);
        wmERC20.waterfallFunds();

        ERC20(mERC20).safeTransfer(address(wmERC20), 1 ether);
        wmERC20.waterfallFunds();

        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(0)), 1 ether);
        assertEq(ERC20(mERC20).balanceOf(address(1)), 1 ether);
    }

    function testCan_waterfallToResidualRecipient() public {
        address(wmETH).safeTransferETH(10 ether);
        wmETH.waterfallFunds();
        address(wmETH).safeTransferETH(10 ether);
        wmETH.waterfallFunds();

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 19 ether);

        ERC20(mERC20).safeTransfer(address(wmERC20), 10 ether);
        wmERC20.waterfallFunds();
        ERC20(mERC20).safeTransfer(address(wmERC20), 10 ether);
        wmERC20.waterfallFunds();

        assertEq(ERC20(mERC20).balanceOf(address(wmERC20)), 0 ether);
        assertEq(ERC20(mERC20).balanceOf(address(0)), 1 ether);
        assertEq(ERC20(mERC20).balanceOf(address(1)), 19 ether);
    }

    function testCannot_reenterWaterfall() public {
        WaterfallReentrancy wr = new WaterfallReentrancy();

        uint256 _trancheRecipientLength = 2;
        address[] memory _trancheRecipient =
            new address[](_trancheRecipientLength);
        _trancheRecipient[0] = address(wr);
        _trancheRecipient[1] = address(0);
        uint256 _trancheThresholdLength = _trancheRecipientLength - 1;
        uint256[] memory _trancheThreshold =
            new uint256[](_trancheThresholdLength);
        _trancheThreshold[0] = 1 ether;

        wmETH = wmf.createWaterfallModule(
            address(0), _trancheRecipient, _trancheThreshold
        );
        address(wmETH).safeTransferETH(10 ether);
        vm.expectRevert(bytes("ETH_TRANSFER_FAILED"));
        wmETH.waterfallFunds();
        assertEq(address(wmETH).balance, 10 ether);
        assertEq(address(wr).balance, 0 ether);
        assertEq(address(0).balance, 0 ether);
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - fuzzing
    /// -----------------------------------------------------------------------
}
