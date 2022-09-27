// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {WaterfallModuleFactory} from "../src/WaterfallModuleFactory.sol";
import {WaterfallModule} from "../src/WaterfallModule.sol";
import {WaterfallReentrancy} from "./WaterfallReentrancy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract WaterfallModuleTest is Test {
    using SafeTransferLib for address;

    event CreateWaterfallModule(
        address indexed waterfallModule,
        address token,
        address[] trancheRecipients,
        uint256[] trancheThresholds
    );

    event ReceiveETH(uint256 amount);

    event WaterfallFunds(
        address[] recipients, uint256[] payouts, uint256 pullFlowFlag
    );

    event RecoverNonWaterfallFunds(
        address nonWaterfallToken, address recipient, uint256 amount
    );

    address internal constant ETH_ADDRESS = address(0);

    WaterfallModuleFactory wmf;
    WaterfallModule wmETH;
    WaterfallModule wmERC20;
    MockERC20 mERC20;

    function setUp() public {
        uint256 _trancheRecipientsLength = 2;
        address[] memory _trancheRecipients =
            new address[](_trancheRecipientsLength);
        for (uint256 i = 0; i < _trancheRecipientsLength; i++) {
            _trancheRecipients[i] = address(uint160(i));
        }
        uint256 _trancheThresholdsLength = _trancheRecipientsLength - 1;
        uint256[] memory _trancheThresholds =
            new uint256[](_trancheThresholdsLength);
        for (uint256 i = 0; i < _trancheThresholdsLength; i++) {
            _trancheThresholds[i] = (i + 1) * 1 ether;
        }

        mERC20 = new MockERC20("Test Token", "TOK", 18);
        mERC20.mint(type(uint256).max);

        wmf = new WaterfallModuleFactory();
        wmETH = wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipients, _trancheThresholds
        );
        wmERC20 = wmf.createWaterfallModule(
            address(mERC20), _trancheRecipients, _trancheThresholds
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

        (trancheRecipients, trancheThresholds) = wmERC20.getTranches();

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

    function testCan_receiveETHViaTransfer() public {
        payable(address(wmETH)).transfer(1 ether);
        assertEq(address(wmETH).balance, 1 ether);

        payable(address(wmERC20)).transfer(1 ether);
        assertEq(address(wmERC20).balance, 1 ether);
    }

    function testCan_emitOnReceiveETH() public {
        vm.expectEmit(true, true, true, true);
        emit ReceiveETH(1 ether);

        address(wmETH).safeTransferETH(1 ether);
    }

    function testCan_receiveERC20() public {
        address(mERC20).safeTransfer(address(wmETH), 1 ether);
        assertEq(mERC20.balanceOf(address(wmETH)), 1 ether);

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        assertEq(mERC20.balanceOf(address(wmERC20)), 1 ether);
    }

    function testCan_recoverNonWaterfallFundsToRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        address(mERC20).safeTransfer(address(wmETH), 1 ether);

        wmETH.recoverNonWaterfallFunds(address(mERC20), address(0));
        assertEq(address(wmETH).balance, 1 ether);
        assertEq(mERC20.balanceOf(address(wmETH)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);

        address(mERC20).safeTransfer(address(wmETH), 1 ether);

        wmETH.recoverNonWaterfallFunds(address(mERC20), address(1));
        assertEq(address(wmETH).balance, 1 ether);
        assertEq(mERC20.balanceOf(address(wmETH)), 0 ether);
        assertEq(mERC20.balanceOf(address(1)), 1 ether);

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        address(wmERC20).safeTransferETH(1 ether);

        wmERC20.recoverNonWaterfallFunds(ETH_ADDRESS, address(0));
        assertEq(mERC20.balanceOf(address(wmERC20)), 1 ether);
        assertEq(address(wmERC20).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);

        address(wmERC20).safeTransferETH(1 ether);

        wmERC20.recoverNonWaterfallFunds(ETH_ADDRESS, address(1));
        assertEq(mERC20.balanceOf(address(wmERC20)), 1 ether);
        assertEq(address(wmERC20).balance, 0 ether);
        assertEq(address(1).balance, 1 ether);
    }

    function testCan_emitOnRecoverNonWaterfallFundsToRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        address(mERC20).safeTransfer(address(wmETH), 1 ether);

        vm.expectEmit(true, true, true, true);
        emit RecoverNonWaterfallFunds(address(mERC20), address(1), 1 ether);
        wmETH.recoverNonWaterfallFunds(address(mERC20), address(1));

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        address(wmERC20).safeTransferETH(1 ether);

        vm.expectEmit(true, true, true, true);
        emit RecoverNonWaterfallFunds(ETH_ADDRESS, address(1), 1 ether);
        wmERC20.recoverNonWaterfallFunds(ETH_ADDRESS, address(1));
    }

    function testCannot_recoverNonWaterfallFundsToNonRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        address(mERC20).safeTransfer(address(wmETH), 1 ether);

        vm.expectRevert(
            WaterfallModule.InvalidTokenRecovery_InvalidRecipient.selector
        );
        wmETH.recoverNonWaterfallFunds(address(mERC20), address(2));

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        address(wmERC20).safeTransferETH(1 ether);

        vm.expectRevert(
            WaterfallModule.InvalidTokenRecovery_InvalidRecipient.selector
        );
        wmERC20.recoverNonWaterfallFunds(ETH_ADDRESS, address(2));
    }

    function testCannot_recoverWaterfallFunds() public {
        address(wmETH).safeTransferETH(1 ether);
        address(mERC20).safeTransfer(address(wmETH), 1 ether);

        vm.expectRevert(
            WaterfallModule.InvalidTokenRecovery_WaterfallToken.selector
        );
        wmETH.recoverNonWaterfallFunds(ETH_ADDRESS, address(0));

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
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
        assertEq(mERC20.balanceOf(address(0)), 0 ether);
    }

    function testCan_emitOnWaterfallToNoRecipients() public {
        vm.expectEmit(true, true, true, true);
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint256[] memory payouts = new uint256[](1);
        payouts[0] = 0 ether;
        emit WaterfallFunds(recipients, payouts, 0);
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

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);

        wmERC20.waterfallFunds();
        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);

        wmERC20.waterfallFunds();
        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);
    }

    function testCan_emitOnWaterfallToFirstRecipient() public {
        address(wmETH).safeTransferETH(1 ether);
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint256[] memory payouts = new uint256[](1);
        payouts[0] = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts, 0);
        wmETH.waterfallFunds();

        address(wmETH).safeTransferETH(1 ether);
        recipients[0] = address(1);

        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts, 0);
        wmETH.waterfallFunds();

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        recipients[0] = address(0);

        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts, 0);
        wmERC20.waterfallFunds();

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        recipients[0] = address(1);

        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts, 0);
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

        address(mERC20).safeTransfer(address(wmERC20), 0.5 ether);
        wmERC20.waterfallFunds();
        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 0.5 ether);

        address(mERC20).safeTransfer(address(wmERC20), 0.5 ether);
        wmERC20.waterfallFunds();
        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
    }

    function testCan_waterfallToBothRecipients() public {
        address(wmETH).safeTransferETH(2 ether);
        wmETH.waterfallFunds();
        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1 ether);

        address(mERC20).safeTransfer(address(wmERC20), 2 ether);
        wmERC20.waterfallFunds();
        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 1 ether);
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
        emit WaterfallFunds(recipients, payouts, 0);
        wmETH.waterfallFunds();

        address(mERC20).safeTransfer(address(wmERC20), 2 ether);
        vm.expectEmit(true, true, true, true);
        emit WaterfallFunds(recipients, payouts, 0);
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

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        wmERC20.waterfallFunds();

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        wmERC20.waterfallFunds();

        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 1 ether);
    }

    function testCan_waterfallToResidualRecipient() public {
        address(wmETH).safeTransferETH(10 ether);
        wmETH.waterfallFunds();
        address(wmETH).safeTransferETH(10 ether);
        wmETH.waterfallFunds();

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 19 ether);

        address(mERC20).safeTransfer(address(wmERC20), 10 ether);
        wmERC20.waterfallFunds();
        address(mERC20).safeTransfer(address(wmERC20), 10 ether);
        wmERC20.waterfallFunds();

        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 19 ether);
    }

    function testCannot_distributeTooMuch() public {
        vm.deal(address(wmETH), type(uint128).max);
        wmETH.waterfallFunds();
        vm.deal(address(wmETH), 1);

        vm.expectRevert(WaterfallModule.InvalidDistribution_TooLarge.selector);
        wmETH.waterfallFunds();

        vm.expectRevert(WaterfallModule.InvalidDistribution_TooLarge.selector);
        wmETH.waterfallFundsPull();

        address(mERC20).safeTransfer(address(wmERC20), type(uint128).max);
        wmERC20.waterfallFunds();
        address(mERC20).safeTransfer(address(wmERC20), 1);

        vm.expectRevert(WaterfallModule.InvalidDistribution_TooLarge.selector);
        wmERC20.waterfallFunds();

        vm.expectRevert(WaterfallModule.InvalidDistribution_TooLarge.selector);
        wmERC20.waterfallFundsPull();
    }

    function testCannot_reenterWaterfall() public {
        WaterfallReentrancy wr = new WaterfallReentrancy();

        uint256 _trancheRecipientsLength = 2;
        address[] memory _trancheRecipients =
            new address[](_trancheRecipientsLength);
        _trancheRecipients[0] = address(wr);
        _trancheRecipients[1] = address(0);
        uint256 _trancheThresholdsLength = _trancheRecipientsLength - 1;
        uint256[] memory _trancheThresholds =
            new uint256[](_trancheThresholdsLength);
        _trancheThresholds[0] = 1 ether;

        wmETH = wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipients, _trancheThresholds
        );
        address(wmETH).safeTransferETH(10 ether);
        vm.expectRevert(SafeTransferLib.ETHTransferFailed.selector);
        wmETH.waterfallFunds();
        assertEq(address(wmETH).balance, 10 ether);
        assertEq(address(wr).balance, 0 ether);
        assertEq(address(0).balance, 0 ether);
    }

    function testCan_waterfallToPullFlow() public {
        // test eth
        address(wmETH).safeTransferETH(10 ether);
        wmETH.waterfallFundsPull();

        assertEq(address(wmETH).balance, 10 ether);
        assertEq(address(0).balance, 0 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 1 ether);
        assertEq(wmETH.getPullBalance(address(1)), 9 ether);

        assertEq(wmETH.distributedFunds(), 10 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 10 ether);

        wmETH.withdraw(address(0));

        assertEq(address(wmETH).balance, 9 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 9 ether);

        assertEq(wmETH.distributedFunds(), 10 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 9 ether);

        wmETH.withdraw(address(1));

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 9 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0 ether);

        assertEq(wmETH.distributedFunds(), 10 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 0 ether);

        // test erc20
        address(mERC20).safeTransfer(address(wmERC20), 10 ether);
        wmERC20.waterfallFundsPull();

        assertEq(mERC20.balanceOf(address(wmERC20)), 10 ether);
        assertEq(mERC20.balanceOf(address(0)), 0 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 1 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 9 ether);

        assertEq(wmERC20.distributedFunds(), 10 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 10 ether);

        wmERC20.withdraw(address(0));

        assertEq(mERC20.balanceOf(address(wmERC20)), 9 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 9 ether);

        assertEq(wmERC20.distributedFunds(), 10 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 9 ether);

        wmERC20.withdraw(address(1));

        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 9 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0 ether);

        assertEq(wmERC20.distributedFunds(), 10 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 0 ether);
    }

    function testCan_waterfallPushAndPull() public {
        // test eth
        address(wmETH).safeTransferETH(0.5 ether);
        assertEq(address(wmETH).balance, 0.5 ether);

        wmETH.waterfallFunds();

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 0.5 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0 ether);

        assertEq(wmETH.distributedFunds(), 0.5 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 0 ether);

        address(wmETH).safeTransferETH(1 ether);
        assertEq(address(wmETH).balance, 1 ether);

        wmETH.waterfallFundsPull();

        assertEq(address(wmETH).balance, 1 ether);
        assertEq(address(0).balance, 0.5 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0.5 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmETH.distributedFunds(), 1.5 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 1 ether);

        wmETH.waterfallFunds();

        assertEq(address(wmETH).balance, 1 ether);
        assertEq(address(0).balance, 0.5 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0.5 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmETH.distributedFunds(), 1.5 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 1 ether);

        wmETH.waterfallFundsPull();

        assertEq(address(wmETH).balance, 1 ether);
        assertEq(address(0).balance, 0.5 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0.5 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmETH.distributedFunds(), 1.5 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 1 ether);

        address(wmETH).safeTransferETH(1 ether);
        assertEq(address(wmETH).balance, 2 ether);

        wmETH.waterfallFunds();

        assertEq(address(wmETH).balance, 1 ether);
        assertEq(address(0).balance, 0.5 ether);
        assertEq(address(1).balance, 1 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0.5 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmETH.distributedFunds(), 2.5 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 1 ether);

        wmETH.withdraw(address(0));

        assertEq(address(wmETH).balance, 0.5 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmETH.distributedFunds(), 2.5 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 0.5 ether);

        wmETH.withdraw(address(1));

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 1.5 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0 ether);

        assertEq(wmETH.distributedFunds(), 2.5 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 0 ether);

        // test erc20
        address(mERC20).safeTransfer(address(wmERC20), 0.5 ether);
        assertEq(mERC20.balanceOf(address(wmERC20)), 0.5 ether);

        wmERC20.waterfallFunds();

        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 0.5 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0 ether);

        assertEq(wmERC20.distributedFunds(), 0.5 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 0 ether);

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        assertEq(mERC20.balanceOf(address(wmERC20)), 1 ether);

        wmERC20.waterfallFundsPull();

        assertEq(mERC20.balanceOf(address(wmERC20)), 1 ether);
        assertEq(mERC20.balanceOf(address(0)), 0.5 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0.5 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmERC20.distributedFunds(), 1.5 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 1 ether);

        wmERC20.waterfallFundsPull();

        assertEq(mERC20.balanceOf(address(wmERC20)), 1 ether);
        assertEq(mERC20.balanceOf(address(0)), 0.5 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0.5 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmERC20.distributedFunds(), 1.5 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 1 ether);

        address(mERC20).safeTransfer(address(wmERC20), 1 ether);
        assertEq(mERC20.balanceOf(address(wmERC20)), 2 ether);

        wmERC20.waterfallFunds();

        assertEq(mERC20.balanceOf(address(wmERC20)), 1 ether);
        assertEq(mERC20.balanceOf(address(0)), 0.5 ether);
        assertEq(mERC20.balanceOf(address(1)), 1 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0.5 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmERC20.distributedFunds(), 2.5 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 1 ether);

        wmERC20.withdraw(address(0));

        assertEq(mERC20.balanceOf(address(wmERC20)), 0.5 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 1 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0.5 ether);

        assertEq(wmERC20.distributedFunds(), 2.5 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 0.5 ether);

        wmERC20.withdraw(address(1));

        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 1.5 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0 ether);

        assertEq(wmERC20.distributedFunds(), 2.5 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 0 ether);
    }

    function testCan_waterfallPullNoMultiWithdraw() public {
        // test eth
        address(wmETH).safeTransferETH(3 ether);
        assertEq(address(wmETH).balance, 3 ether);

        wmETH.waterfallFundsPull();

        assertEq(address(wmETH).balance, 3 ether);
        assertEq(address(0).balance, 0 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 1 ether);
        assertEq(wmETH.getPullBalance(address(1)), 2 ether);

        assertEq(wmETH.distributedFunds(), 3 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 3 ether);

        wmETH.withdraw(address(0));

        assertEq(address(wmETH).balance, 2 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 2 ether);

        assertEq(wmETH.distributedFunds(), 3 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 2 ether);

        wmETH.withdraw(address(0));

        assertEq(address(wmETH).balance, 2 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 0 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 2 ether);

        assertEq(wmETH.distributedFunds(), 3 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 2 ether);

        wmETH.withdraw(address(1));

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 2 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0 ether);

        assertEq(wmETH.distributedFunds(), 3 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 0 ether);

        wmETH.withdraw(address(1));

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(address(0).balance, 1 ether);
        assertEq(address(1).balance, 2 ether);

        assertEq(wmETH.getPullBalance(address(0)), 0 ether);
        assertEq(wmETH.getPullBalance(address(1)), 0 ether);

        assertEq(wmETH.distributedFunds(), 3 ether);
        assertEq(wmETH.fundsPendingWithdrawal(), 0 ether);

        // test erc20
        address(mERC20).safeTransfer(address(wmERC20), 3 ether);
        assertEq(mERC20.balanceOf(address(wmERC20)), 3 ether);

        wmERC20.waterfallFundsPull();

        assertEq(mERC20.balanceOf(address(wmERC20)), 3 ether);
        assertEq(mERC20.balanceOf(address(0)), 0 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 1 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 2 ether);

        assertEq(wmERC20.distributedFunds(), 3 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 3 ether);

        wmERC20.withdraw(address(0));

        assertEq(mERC20.balanceOf(address(wmERC20)), 2 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 2 ether);

        assertEq(wmERC20.distributedFunds(), 3 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 2 ether);

        wmERC20.withdraw(address(0));

        assertEq(mERC20.balanceOf(address(wmERC20)), 2 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 0 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 2 ether);

        assertEq(wmERC20.distributedFunds(), 3 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 2 ether);

        wmERC20.withdraw(address(1));

        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 2 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0 ether);

        assertEq(wmERC20.distributedFunds(), 3 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 0 ether);

        wmERC20.withdraw(address(1));

        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(mERC20.balanceOf(address(0)), 1 ether);
        assertEq(mERC20.balanceOf(address(1)), 2 ether);

        assertEq(wmERC20.getPullBalance(address(0)), 0 ether);
        assertEq(wmERC20.getPullBalance(address(1)), 0 ether);

        assertEq(wmERC20.distributedFunds(), 3 ether);
        assertEq(wmERC20.fundsPendingWithdrawal(), 0 ether);
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - fuzzing
    /// -----------------------------------------------------------------------

    function testCan_getTranches(
        uint8 _numTranches,
        uint256 _recipientsSeed,
        uint256 _thresholdsSeed
    ) public {
        uint256 numTranches = bound(_numTranches, 2, type(uint8).max);

        (
            address[] memory _trancheRecipients,
            uint256[] memory _trancheThresholds
        ) = generateTranches(numTranches, _recipientsSeed, _thresholdsSeed);

        wmETH = wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipients, _trancheThresholds
        );
        wmERC20 = wmf.createWaterfallModule(
            address(mERC20), _trancheRecipients, _trancheThresholds
        );

        (address[] memory trancheRecipients, uint256[] memory trancheThresholds)
        = wmETH.getTranches();

        assertEq(trancheRecipients.length, _trancheRecipients.length);
        for (uint256 i = 0; i < trancheRecipients.length; i++) {
            assertEq(trancheRecipients[i], _trancheRecipients[i]);
        }
        assertEq(trancheThresholds.length, _trancheThresholds.length);
        for (uint256 i = 0; i < trancheThresholds.length; i++) {
            assertEq(trancheThresholds[i], _trancheThresholds[i]);
        }

        (trancheRecipients, trancheThresholds) = wmERC20.getTranches();

        assertEq(trancheRecipients.length, _trancheRecipients.length);
        for (uint256 i = 0; i < trancheRecipients.length; i++) {
            assertEq(trancheRecipients[i], _trancheRecipients[i]);
        }
        assertEq(trancheThresholds.length, _trancheThresholds.length);
        for (uint256 i = 0; i < trancheThresholds.length; i++) {
            assertEq(trancheThresholds[i], _trancheThresholds[i]);
        }
    }

    function testCan_recoverNonWaterfallFundsToRecipient(
        uint8 _numTranches,
        uint256 _recipientsSeed,
        uint256 _thresholdsSeed,
        uint8 _recoveryIndex,
        uint96 _ethAmount,
        uint256 _erc20Amount
    ) public {
        uint256 numTranches = bound(_numTranches, 2, type(uint8).max);
        uint256 recoveryIndex = bound(_recoveryIndex, 0, numTranches - 1);

        (
            address[] memory _trancheRecipients,
            uint256[] memory _trancheThresholds
        ) = generateTranches(numTranches, _recipientsSeed, _thresholdsSeed);

        wmETH = wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipients, _trancheThresholds
        );
        wmERC20 = wmf.createWaterfallModule(
            address(mERC20), _trancheRecipients, _trancheThresholds
        );

        address(mERC20).safeTransfer(address(wmETH), _erc20Amount);

        wmETH.recoverNonWaterfallFunds(
            address(mERC20), _trancheRecipients[recoveryIndex]
        );
        assertEq(mERC20.balanceOf(address(wmETH)), 0);
        assertEq(
            mERC20.balanceOf(_trancheRecipients[recoveryIndex]), _erc20Amount
        );

        address(wmERC20).safeTransferETH(_ethAmount);

        wmERC20.recoverNonWaterfallFunds(
            ETH_ADDRESS, _trancheRecipients[recoveryIndex]
        );
        assertEq(address(wmERC20).balance, 0);
        assertEq(_trancheRecipients[recoveryIndex].balance, _ethAmount);
    }

    function testCan_waterfallDepositsToRecipients(
        uint8 _numTranches,
        uint256 _recipientsSeed,
        uint256 _thresholdsSeed,
        uint8 _numDeposits,
        uint48 _ethAmount,
        uint96 _erc20Amount
    ) public {
        uint256 numTranches = bound(_numTranches, 2, type(uint8).max);

        (
            address[] memory _trancheRecipients,
            uint256[] memory _trancheThresholds
        ) = generateTranches(numTranches, _recipientsSeed, _thresholdsSeed);

        wmETH = wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipients, _trancheThresholds
        );
        wmERC20 = wmf.createWaterfallModule(
            address(mERC20), _trancheRecipients, _trancheThresholds
        );

        /// test eth

        for (uint256 i = 0; i < _numDeposits; i++) {
            address(wmETH).safeTransferETH(_ethAmount);
            wmETH.waterfallFunds();
        }
        uint256 _totalETHAmount = uint256(_numDeposits) * uint256(_ethAmount);

        assertEq(address(wmETH).balance, 0 ether);
        assertEq(wmETH.distributedFunds(), _totalETHAmount);
        assertEq(wmETH.fundsPendingWithdrawal(), 0 ether);
        assertEq(
            _trancheRecipients[0].balance,
            (_totalETHAmount >= _trancheThresholds[0])
                ? _trancheThresholds[0]
                : _totalETHAmount
        );
        for (uint256 i = 1; i < _trancheThresholds.length; i++) {
            if (_totalETHAmount >= _trancheThresholds[i]) {
                assertEq(
                    _trancheRecipients[i].balance,
                    _trancheThresholds[i] - _trancheThresholds[i - 1]
                );
            } else if (_totalETHAmount > _trancheThresholds[i - 1]) {
                assertEq(
                    _trancheRecipients[i].balance,
                    _totalETHAmount - _trancheThresholds[i - 1]
                );
            } else {
                assertEq(_trancheRecipients[i].balance, 0);
            }
        }
        assertEq(
            _trancheRecipients[_trancheRecipients.length - 1].balance,
            (
                _totalETHAmount
                    > _trancheThresholds[_trancheRecipients.length - 2]
            )
                ? _totalETHAmount
                    - _trancheThresholds[_trancheRecipients.length - 2]
                : 0
        );

        /// test erc20

        for (uint256 i = 0; i < _numDeposits; i++) {
            address(mERC20).safeTransfer(address(wmERC20), _erc20Amount);
            wmERC20.waterfallFunds();
        }
        uint256 _totalERC20Amount =
            uint256(_numDeposits) * uint256(_erc20Amount);

        assertEq(mERC20.balanceOf(address(wmERC20)), 0 ether);
        assertEq(wmERC20.distributedFunds(), _totalERC20Amount);
        assertEq(wmERC20.fundsPendingWithdrawal(), 0 ether);
        assertEq(
            mERC20.balanceOf(_trancheRecipients[0]),
            (_totalERC20Amount >= _trancheThresholds[0])
                ? _trancheThresholds[0]
                : _totalERC20Amount
        );
        for (uint256 i = 1; i < _trancheThresholds.length; i++) {
            if (_totalERC20Amount >= _trancheThresholds[i]) {
                assertEq(
                    mERC20.balanceOf(_trancheRecipients[i]),
                    _trancheThresholds[i] - _trancheThresholds[i - 1]
                );
            } else if (_totalERC20Amount > _trancheThresholds[i - 1]) {
                assertEq(
                    mERC20.balanceOf(_trancheRecipients[i]),
                    _totalERC20Amount - _trancheThresholds[i - 1]
                );
            } else {
                assertEq(mERC20.balanceOf(_trancheRecipients[i]), 0);
            }
        }
        assertEq(
            mERC20.balanceOf(_trancheRecipients[_trancheRecipients.length - 1]),
            (
                _totalERC20Amount
                    > _trancheThresholds[_trancheRecipients.length - 2]
            )
                ? _totalERC20Amount
                    - _trancheThresholds[_trancheRecipients.length - 2]
                : 0
        );
    }

    function testCan_waterfallPullDepositsToRecipients(
        uint8 _numTranches,
        uint256 _recipientsSeed,
        uint256 _thresholdsSeed,
        uint8 _numDeposits,
        uint48 _ethAmount,
        uint96 _erc20Amount
    ) public {
        uint256 numTranches = bound(_numTranches, 2, type(uint8).max);

        (
            address[] memory _trancheRecipients,
            uint256[] memory _trancheThresholds
        ) = generateTranches(numTranches, _recipientsSeed, _thresholdsSeed);

        wmETH = wmf.createWaterfallModule(
            ETH_ADDRESS, _trancheRecipients, _trancheThresholds
        );
        wmERC20 = wmf.createWaterfallModule(
            address(mERC20), _trancheRecipients, _trancheThresholds
        );

        /// test eth

        for (uint256 i = 0; i < _numDeposits; i++) {
            address(wmETH).safeTransferETH(_ethAmount);
            wmETH.waterfallFundsPull();
        }
        uint256 _totalETHAmount = uint256(_numDeposits) * uint256(_ethAmount);

        assertEq(address(wmETH).balance, _totalETHAmount);
        assertEq(wmETH.distributedFunds(), _totalETHAmount);
        assertEq(wmETH.fundsPendingWithdrawal(), _totalETHAmount);
        assertEq(
            wmETH.getPullBalance(_trancheRecipients[0]),
            (_totalETHAmount >= _trancheThresholds[0])
                ? _trancheThresholds[0]
                : _totalETHAmount
        );
        for (uint256 i = 1; i < _trancheThresholds.length; i++) {
            if (_totalETHAmount >= _trancheThresholds[i]) {
                assertEq(
                    wmETH.getPullBalance(_trancheRecipients[i]),
                    _trancheThresholds[i] - _trancheThresholds[i - 1]
                );
            } else if (_totalETHAmount > _trancheThresholds[i - 1]) {
                assertEq(
                    wmETH.getPullBalance(_trancheRecipients[i]),
                    _totalETHAmount - _trancheThresholds[i - 1]
                );
            } else {
                assertEq(wmETH.getPullBalance(_trancheRecipients[i]), 0);
            }
        }
        assertEq(
            wmETH.getPullBalance(
                _trancheRecipients[_trancheRecipients.length - 1]
            ),
            (
                _totalETHAmount
                    > _trancheThresholds[_trancheRecipients.length - 2]
            )
                ? _totalETHAmount
                    - _trancheThresholds[_trancheRecipients.length - 2]
                : 0
        );

        for (uint256 i = 0; i < _trancheRecipients.length; i++) {
            wmETH.withdraw(_trancheRecipients[i]);
        }

        assertEq(address(wmETH).balance, 0);
        assertEq(wmETH.distributedFunds(), _totalETHAmount);
        assertEq(wmETH.fundsPendingWithdrawal(), 0);
        assertEq(
            _trancheRecipients[0].balance,
            (_totalETHAmount >= _trancheThresholds[0])
                ? _trancheThresholds[0]
                : _totalETHAmount
        );
        for (uint256 i = 1; i < _trancheThresholds.length; i++) {
            if (_totalETHAmount >= _trancheThresholds[i]) {
                assertEq(
                    _trancheRecipients[i].balance,
                    _trancheThresholds[i] - _trancheThresholds[i - 1]
                );
            } else if (_totalETHAmount > _trancheThresholds[i - 1]) {
                assertEq(
                    _trancheRecipients[i].balance,
                    _totalETHAmount - _trancheThresholds[i - 1]
                );
            } else {
                assertEq(_trancheRecipients[i].balance, 0);
            }
        }
        assertEq(
            _trancheRecipients[_trancheRecipients.length - 1].balance,
            (
                _totalETHAmount
                    > _trancheThresholds[_trancheRecipients.length - 2]
            )
                ? _totalETHAmount
                    - _trancheThresholds[_trancheRecipients.length - 2]
                : 0
        );

        /// test erc20

        for (uint256 i = 0; i < _numDeposits; i++) {
            address(mERC20).safeTransfer(address(wmERC20), _erc20Amount);
            wmERC20.waterfallFundsPull();
        }
        uint256 _totalERC20Amount =
            uint256(_numDeposits) * uint256(_erc20Amount);

        assertEq(mERC20.balanceOf(address(wmERC20)), _totalERC20Amount);
        assertEq(wmERC20.distributedFunds(), _totalERC20Amount);
        assertEq(wmERC20.fundsPendingWithdrawal(), _totalERC20Amount);
        assertEq(
            wmERC20.getPullBalance(_trancheRecipients[0]),
            (_totalERC20Amount >= _trancheThresholds[0])
                ? _trancheThresholds[0]
                : _totalERC20Amount
        );
        for (uint256 i = 1; i < _trancheThresholds.length; i++) {
            if (_totalERC20Amount >= _trancheThresholds[i]) {
                assertEq(
                    wmERC20.getPullBalance(_trancheRecipients[i]),
                    _trancheThresholds[i] - _trancheThresholds[i - 1]
                );
            } else if (_totalERC20Amount > _trancheThresholds[i - 1]) {
                assertEq(
                    wmERC20.getPullBalance(_trancheRecipients[i]),
                    _totalERC20Amount - _trancheThresholds[i - 1]
                );
            } else {
                assertEq(wmERC20.getPullBalance(_trancheRecipients[i]), 0);
            }
        }
        assertEq(
            wmERC20.getPullBalance(
                _trancheRecipients[_trancheRecipients.length - 1]
            ),
            (
                _totalERC20Amount
                    > _trancheThresholds[_trancheRecipients.length - 2]
            )
                ? _totalERC20Amount
                    - _trancheThresholds[_trancheRecipients.length - 2]
                : 0
        );

        for (uint256 i = 0; i < _trancheRecipients.length; i++) {
            wmERC20.withdraw(_trancheRecipients[i]);
        }

        assertEq(mERC20.balanceOf(address(wmERC20)), 0);
        assertEq(wmERC20.distributedFunds(), _totalERC20Amount);
        assertEq(wmERC20.fundsPendingWithdrawal(), 0);
        assertEq(
            mERC20.balanceOf(_trancheRecipients[0]),
            (_totalERC20Amount >= _trancheThresholds[0])
                ? _trancheThresholds[0]
                : _totalERC20Amount
        );
        for (uint256 i = 1; i < _trancheThresholds.length; i++) {
            if (_totalERC20Amount >= _trancheThresholds[i]) {
                assertEq(
                    mERC20.balanceOf(_trancheRecipients[i]),
                    _trancheThresholds[i] - _trancheThresholds[i - 1]
                );
            } else if (_totalERC20Amount > _trancheThresholds[i - 1]) {
                assertEq(
                    mERC20.balanceOf(_trancheRecipients[i]),
                    _totalERC20Amount - _trancheThresholds[i - 1]
                );
            } else {
                assertEq(mERC20.balanceOf(_trancheRecipients[i]), 0);
            }
        }
        assertEq(
            mERC20.balanceOf(_trancheRecipients[_trancheRecipients.length - 1]),
            (
                _totalERC20Amount
                    > _trancheThresholds[_trancheRecipients.length - 2]
            )
                ? _totalERC20Amount
                    - _trancheThresholds[_trancheRecipients.length - 2]
                : 0
        );
    }

    /// -----------------------------------------------------------------------
    /// helper fns
    /// -----------------------------------------------------------------------

    function generateTranches(uint256 numTranches, uint256 rSeed, uint256 tSeed)
        internal
        pure
        returns (address[] memory recipients, uint256[] memory thresholds)
    {
        recipients = generateTrancheRecipients(numTranches, rSeed);
        thresholds = generateTrancheThresholds(numTranches - 1, tSeed);
    }

    function generateTrancheRecipients(uint256 numRecipients, uint256 _seed)
        internal
        pure
        returns (address[] memory recipients)
    {
        recipients = new address[](numRecipients);
        bytes32 seed = bytes32(_seed);
        for (uint256 i = 0; i < numRecipients; i++) {
            seed = keccak256(abi.encodePacked(seed));
            recipients[i] = address(bytes20(seed));
        }
    }

    function generateTrancheThresholds(uint256 numThresholds, uint256 _seed)
        internal
        pure
        returns (uint256[] memory thresholds)
    {
        thresholds = new uint256[](numThresholds);
        uint256 seed = _seed;
        seed = uint256(keccak256(abi.encodePacked(seed)));
        thresholds[0] = uint32(seed);
        for (uint256 i = 1; i < numThresholds; i++) {
            seed = uint256(keccak256(abi.encodePacked(seed)));
            thresholds[i] = thresholds[i - 1] + uint32(seed);
        }
    }
}
