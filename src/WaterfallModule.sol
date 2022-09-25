// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {Clone} from "solady/utils/Clone.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title WaterfallModule
/// @author 0xSplits
/// @notice A maximally-composable waterfall contract allowing multiple
/// recipients to receive preferential payments before residual funds flow to a
/// final address.
/// @dev Only one token can be waterfall'd for a given deployment. There is a
/// recovery method for non-target tokens sent by accident.
/// Target ERC20s with very large decimals may overflow & cause issues.
/// This contract uses token = address(0) to refer to ETH.
contract WaterfallModule is Clone {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    /// Invalid token recovery; cannot recover the waterfall token
    error InvalidTokenRecovery_WaterfallToken();

    /// Invalid token recovery recipient; not a waterfall recipient
    error InvalidTokenRecovery_InvalidRecipient();

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    /// Emitted after each successful ETH transfer to proxy
    /// @param amount Amount of ETH received
    /// @dev embedded in & emitted from clone bytecode
    event ReceiveETH(uint256 amount);

    /// Emitted after funds are waterfall'd to recipients
    /// @param recipients Addresses receiving payouts
    /// @param payouts Amount of payout
    /// @param pullFlowFlag Flag for pushing funds to recipients or storing for pulling
    event WaterfallFunds(
        address[] recipients, uint256[] payouts, uint256 pullFlowFlag
    );

    /// Emitted after non-waterfall'd tokens are recovered to a recipient
    /// @param nonWaterfallToken Recovered token (cannot be waterfall token)
    /// @param recipient Address receiving recovered token
    /// @param amount Amount of recovered token
    event RecoverNonWaterfallFunds(
        address nonWaterfallToken, address recipient, uint256 amount
    );

    /// Emitted after funds withdrawn using pull flow
    /// @param account Account withdrawing funds for
    /// @param amount Amount withdrawn
    event Withdrawal(address account, uint256 amount);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    address internal constant ETH_ADDRESS = address(0);

    uint256 internal constant PUSH = 0;
    uint256 internal constant PULL = 1;

    uint256 internal constant ONE_WORD = 32;
    uint256 internal constant THRESHOLD_BITS = 96;
    uint256 internal constant ADDRESS_BITS = 160;
    uint256 internal constant ADDRESS_BITMASK = uint256(~0 >> THRESHOLD_BITS);

    // 20 = address (20 bytes)
    uint256 internal constant NUM_TRANCHES_OFFSET = 20;
    // 28 = NUM_TRANCHES_OFFSET (20) + uint64 (8 bytes)
    uint256 internal constant TRANCHES_OFFSET = 28;

    /// Address of ERC20 to waterfall (0x0 used for ETH)
    /// @dev equivalent to address public immutable token;
    function token() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// Number of waterfall tranches
    /// @dev equivalent to uint64 internal immutable numTranches;
    /// clones-with-immutable-args limits uint256[] array length to uint64
    function numTranches() internal pure returns (uint256) {
        return uint256(_getArgUint64(NUM_TRANCHES_OFFSET));
    }

    /// Amount of distributed waterfall token
    /// @dev ERC20s with very large decimals may overflow & cause issues
    uint128 public distributedFunds;

    /// Amount of active balance set aside for pulls
    /// @dev ERC20s with very large decimals may overflow & cause issues
    uint128 public fundsPendingWithdrawal;

    /// @notice mapping to account balances for pulling
    mapping(address => uint256) internal pullBalances;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    // solhint-disable-next-line no-empty-blocks
    /// clone implementation doesn't use constructor
    constructor() {}

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    /// emit event when receiving ETH
    /// @dev implemented w/i clone bytecode
    /* receive() external payable { */
    /*     emit ReceiveETH(msg.value); */
    /* } */

    /// Waterfalls target token inside the contract to next-in-line recipients
    function waterfallFunds() external payable {
        _waterfallFunds(PUSH);
    }

    function waterfallFundsPull() external payable {
        _waterfallFunds(PULL);
    }

    /// Recover non-waterfall'd tokens to a recipient
    /// @param nonWaterfallToken Token to recover (cannot be waterfall token)
    /// @param recipient Address to receive recovered token
    function recoverNonWaterfallFunds(
        address nonWaterfallToken,
        address recipient
    ) external payable {
        /// checks

        // revert if caller tries to recover waterfall token
        if (nonWaterfallToken == token()) {
            revert InvalidTokenRecovery_WaterfallToken();
        }

        // ensure txn recipient is a valid waterfall recipient
        (address[] memory recipients,) = getTranches();
        bool validRecipient = false;
        uint256 _numTranches = numTranches();
        for (uint256 i; i < _numTranches;) {
            if (recipients[i] == recipient) {
                validRecipient = true;
                break;
            }
            unchecked {
                // shouldn't overflow
                ++i;
            }
        }
        if (!validRecipient) {
            revert InvalidTokenRecovery_InvalidRecipient();
        }

        /// effects

        /// interactions

        // recover non-target token
        uint256 amount;
        if (nonWaterfallToken == ETH_ADDRESS) {
            amount = address(this).balance;
            recipient.safeTransferETH(amount);
        } else {
            amount = ERC20(nonWaterfallToken).balanceOf(address(this));
            nonWaterfallToken.safeTransfer(recipient, amount);
        }

        emit RecoverNonWaterfallFunds(nonWaterfallToken, recipient, amount);
    }

    /**
     * @notice Withdraw token balance for account `account`
     * @param account Address to withdraw on behalf of
     */
    function withdraw(address account) external {
        address _token = token();
        uint256 tokenAmount = pullBalances[account];
        unchecked {
            // shouldn't underflow; invariant: fundsPendingWithdrawal = sum(pullBalances)
            fundsPendingWithdrawal -= uint128(tokenAmount);
        }
        pullBalances[account] = 0;
        if (_token == ETH_ADDRESS) {
            account.safeTransferETH(tokenAmount);
        } else {
            _token.safeTransfer(account, tokenAmount);
        }

        emit Withdrawal(account, tokenAmount);
    }

    /// -----------------------------------------------------------------------
    /// functions - view & pure
    /// -----------------------------------------------------------------------

    /// Return tranches in an unpacked form
    /// @return recipients Addresses to waterfall payments to
    /// @return thresholds Absolute payment thresholds for waterfall recipients
    function getTranches()
        public
        pure
        returns (address[] memory recipients, uint256[] memory thresholds)
    {
        uint256 numRecipients = numTranches();
        uint256 numThresholds;
        unchecked {
            // shouldn't underflow
            numThresholds = numRecipients - 1;
        }
        recipients = new address[](numRecipients);
        thresholds = new uint256[](numThresholds);

        uint256 i = 0;
        uint256 tranche;
        for (; i < numThresholds;) {
            tranche = _getTranche(i);
            recipients[i] = address(uint160(tranche));
            thresholds[i] = tranche >> ADDRESS_BITS;
            unchecked {
                ++i;
            }
        }
        // recipients has one more entry than thresholds
        recipients[i] = address(uint160(_getTranche(i)));
    }

    /**
     * @notice Returns the balance for account `account`
     * @param account Account to return balance for
     * @return Account's balance waterfall token
     */
    function getPullBalance(address account) external view returns (uint256) {
        return pullBalances[account];
    }

    function _getTranche(uint256 i) internal pure returns (uint256) {
        unchecked {
            // shouldn't overflow
            return _getArgUint256(TRANCHES_OFFSET + i * ONE_WORD);
        }
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    function _waterfallFunds(uint256 pullFlowFlag) internal {
        /// checks

        /// effects

        // load storage into memory

        address _token = token();
        uint256 _startingDistributedFunds = uint256(distributedFunds);
        uint256 _endingDistributedFunds;
        uint256 _memoryFundsPendingWithdrawal = uint256(fundsPendingWithdrawal);
        unchecked {
            // shouldn't overflow
            _endingDistributedFunds = _startingDistributedFunds
            // fundsPendingWithdrawal is always <= _startingDistributedFunds
            - _memoryFundsPendingWithdrawal
            // recognizes 0x0 as ETH
            // shouldn't need to worry about re-entrancy from ERC20 view fn
            + (
                _token == ETH_ADDRESS
                    ? address(this).balance
                    : ERC20(_token).balanceOf(address(this))
            );
        }

        (address[] memory recipients, uint256[] memory thresholds) =
            getTranches();

        uint256 _firstPayoutTranche;
        uint256 _lastPayoutTranche;
        unchecked {
            // shouldn't underflow while numTranches() >= 2
            uint256 finalTranche = numTranches() - 1;
            // index inc shouldn't overflow
            for (; _firstPayoutTranche < finalTranche; ++_firstPayoutTranche) {
                if (
                    thresholds[_firstPayoutTranche] >= _startingDistributedFunds
                ) {
                    break;
                }
            }
            _lastPayoutTranche = _firstPayoutTranche;
            // index inc shouldn't overflow
            for (; _lastPayoutTranche < finalTranche; ++_lastPayoutTranche) {
                if (thresholds[_lastPayoutTranche] >= _endingDistributedFunds) {
                    break;
                }
            }
        }

        uint256 _payoutsLength;
        unchecked {
            // shouldn't underflow since _lastPayoutTranche >= _firstPayoutTranche
            _payoutsLength = _lastPayoutTranche - _firstPayoutTranche + 1;
        }
        address[] memory _payoutAddresses = new address[](_payoutsLength);
        uint256[] memory _payouts = new uint256[](_payoutsLength);

        // scope allows compiler to discard vars on stack to avoid stack-too-deep
        {
            uint256 _paidOut = _startingDistributedFunds;
            uint256 _index;
            uint256 _threshold;
            uint256 i; // = 0
            uint256 loopLength;
            unchecked {
                // shouldn't underflow since _payoutsLength >= 1
                loopLength = _payoutsLength - 1;
            }
            for (; i < loopLength;) {
                unchecked {
                    // shouldn't overflow
                    _index = _firstPayoutTranche + i;

                    _payoutAddresses[i] = recipients[_index];
                    _threshold = thresholds[_index];
                    // shouldn't underflow since _paidOut begins < active
                    // tranche's threshold and is then set to each preceding
                    // threshold (which are monotonically increasing)
                    _payouts[i] = _threshold - _paidOut;
                    _paidOut = _threshold;

                    // shouldn't overflow
                    ++i;
                }
            }
            // i = _payoutsLength - 1, i.e. last payout
            unchecked {
                // shouldn't overflow
                _payoutAddresses[i] = recipients[_firstPayoutTranche + i];
                // shouldn't underflow since _paidOut = last tranche threshold,
                // which should be <= _endingDistributedFunds by construction
                _payouts[i] = _endingDistributedFunds - _paidOut;
            }

            distributedFunds = uint128(_endingDistributedFunds);
        }

        /// interactions

        // pay outs
        // earlier external calls may try to re-enter but will cause fn to revert
        // when later external calls fail (bc balance is emptied early)
        for (uint256 i; i < _payoutsLength;) {
            if (pullFlowFlag == PULL) {
                pullBalances[_payoutAddresses[i]] += _payouts[i];
                _memoryFundsPendingWithdrawal += _payouts[i];
            } else if (_token == ETH_ADDRESS) {
                (_payoutAddresses[i]).safeTransferETH(_payouts[i]);
            } else {
                _token.safeTransfer(_payoutAddresses[i], _payouts[i]);
            }

            unchecked {
                // shouldn't overflow
                ++i;
            }
        }

        if (pullFlowFlag == PULL) {
            fundsPendingWithdrawal = uint128(_memoryFundsPendingWithdrawal);
        }

        emit WaterfallFunds(_payoutAddresses, _payouts, pullFlowFlag);
    }
}
