// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// TODO: clones-with-immutable-args
// TODO: natspec

/// -----------------------------------------------------------------------
/// errors
/// -----------------------------------------------------------------------

/// Invalid number of recipients, must have at least 2
error InvalidWaterfall__TooFewRecipients();

/// Invalid recipient & threshold lengths; recipients must have one more entry
/// than thresholds
error InvalidWaterfall__RecipientsAndThresholdLengthMismatch();

/// Thresholds must be positive
error InvalidWaterfall__ZeroThreshold();

/// Invalid threshold at `index` (thresholds must increase monotonically)
/// @param index Index of out-of-order threshold
error InvalidWaterfall__ThresholdOutOfOrder(uint256 index);

/// Invalid token recovery nonTargetToken
error InvalidTokenRecovery_InvalidNonTargetToken();

/// Invalid token recovery beneficiary
error InvalidTokenRecovery_InvalidBeneficiary();

/// @title WaterfallModule
/// @author 0xSplits <will@0xSplits.xyz>
/// @notice TODO
/// @dev TODO
/// This contract uses token = address(0) to refer to ETH.
contract WaterfallModule {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// types
    /// -----------------------------------------------------------------------

    // TODO
    /* type Tranche is uint256; */

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    /// New waterfall module deployed
    /// @param waterfallModule Address of newly created WaterfallModule clone
    /// @param token x
    /// @param trancheRecipient x
    /// @param trancheThreshold x
    event CreateWaterfallModule(
        address indexed waterfallModule,
        address token,
        address[] trancheRecipient,
        uint256[] trancheThreshold
    );

    /// Emitted after each successful ETH transfer to proxy
    /// @param amount Amount of ETH received
    event ReceiveETH(uint256 amount);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    // TODO: bitpack into uint256[]; maybe use custom struct for setter / getter
    // TODO: use type aliasing?
    // TODO: immutable (clones-with-immutable-args)
    address[] public trancheRecipient;
    uint256[] public trancheThreshold;
    // TODO: private?
    uint256 public immutable finalTranche;

    address public immutable token;
    uint256 public distributedFunds;
    // TODO: private?
    uint256 public activeTranche;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(
        address _token,
        address[] memory _trancheRecipient,
        uint256[] memory _trancheThreshold
    ) {
        token = _token;

        // cache lengths in memory
        uint256 _trancheRecipientLength = _trancheRecipient.length;
        uint256 _trancheThresholdLength = _trancheThreshold.length;
        finalTranche = _trancheThresholdLength;

        // ensure recipients array has at least 2 entries
        if (_trancheRecipientLength < 2) revert
            InvalidWaterfall__TooFewRecipients();
        // ensure recipients array is one longer than thresholds array
        unchecked {
            // shouldn't underflow since _trancheRecipientLength >= 2
            if (_trancheThresholdLength != _trancheRecipientLength - 1) revert
                InvalidWaterfall__RecipientsAndThresholdLengthMismatch();
        }
        // ensure first threshold isn't zero
        if (_trancheThreshold[0] == 0) revert InvalidWaterfall__ZeroThreshold();
        // ensure thresholds increase monotonically
        uint256 i = 1;
        for (; i < _trancheThresholdLength;) {
            unchecked {
                // shouldn't underflow since i >= 1
                if (_trancheThreshold[i - 1] >= _trancheThreshold[i]) revert
                    InvalidWaterfall__ThresholdOutOfOrder(i);
                // shouldn't overflow
                ++i;
            }
        }

        // copy recipients & thresholds into storage
        i = 0;
        trancheRecipient = new address[](_trancheRecipientLength);
        trancheThreshold = new uint256[](_trancheThresholdLength);
        for (; i < _trancheThresholdLength;) {
            trancheThreshold[i] = _trancheThreshold[i];
            trancheRecipient[i] = _trancheRecipient[i];
            unchecked {
                // shouldn't overflow
                ++i;
            }
        }
        // recipients array is one longer than thresholds array; set last item after loop
        trancheRecipient[i] = _trancheRecipient[i];

        emit CreateWaterfallModule(
            address(this), _token, _trancheRecipient, _trancheThreshold
            );
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    /// emit event when receiving ETH
    /// @dev implemented w/i clone bytecode
    receive() external payable {
        emit ReceiveETH(msg.value);
    }

    function waterfallFunds() external payable {
        /// checks

        /// effects

        // load storage into memory

        uint256 _startingDistributedFunds = distributedFunds;
        // TODO: test against re-entrancy
        // distributed eth will have increased but address.balance may still be positive
        // think not: og call will revert
        uint256 _distributedFunds;
        unchecked {
            // shouldn't overflow
            _distributedFunds =
                _startingDistributedFunds + address(this).balance;
        }

        uint256 _startingActiveTranche = activeTranche;
        uint256 _activeTranche = _startingActiveTranche;

        for (; _activeTranche < finalTranche;) {
            if (trancheThreshold[_activeTranche] >= _distributedFunds) {
                break;
            }
            unchecked {
                // shouldn't overflow
                ++_activeTranche;
            }
        }

        uint256 _payoutsLength;
        unchecked {
            // shouldn't underflow since _activeTranche >= _startingActiveTranche
            _payoutsLength = _activeTranche - _startingActiveTranche + 1;
        }
        address[] memory _payoutAddresses = new address[](_payoutsLength);
        uint256[] memory _payouts = new uint256[](_payoutsLength);

        uint256 _paidOut = _startingDistributedFunds;
        uint256 _trancheIndex;
        uint256 _trancheThreshold;
        uint256 i = 0;
        uint256 loopLength;
        unchecked {
            // shouldn't underflow since _payoutsLength >= 1
            loopLength = _payoutsLength - 1;
        }
        for (; i < loopLength;) {
            unchecked {
                // shouldn't overflow
                _trancheIndex = _startingActiveTranche + i;

                _payoutAddresses[i] = trancheRecipient[_trancheIndex];
                _trancheThreshold = trancheThreshold[_trancheIndex];
                // shouldn't underflow since _paidOut begins < active tranche's threshold and
                // is then set to each preceding threshold (which are monotonically increasing)
                _payouts[i] = _trancheThreshold - _paidOut;

                _paidOut = _trancheThreshold;
                // shouldn't overflow
                ++i;
            }
        }
        // i = _payoutsLength - 1, i.e. last payout
        unchecked {
            // shouldn't overflow
            _trancheIndex = _startingActiveTranche + i;

            _payoutAddresses[i] = trancheRecipient[_trancheIndex];
            // _paidOut = last tranche threshold, which should be <= _distributedFunds by construction
            _payouts[i] = _distributedFunds - _paidOut;

            distributedFunds = _distributedFunds;
            // if total amount of distributed funds is equal to the last tranche threshold, advance
            // the active tranche by one
            // shouldn't overflow
            activeTranche =
                _activeTranche + (_trancheThreshold == _distributedFunds ? 1 : 0);
        }

        /// interactions

        // pay outs
        for (i = 0; i < _payoutsLength;) {
            if (token == address(0)) {
                (_payoutAddresses[i]).safeTransferETH(_payouts[i]);
            } else {
                ERC20(token).safeTransfer(_payoutAddresses[i], _payouts[i]);
            }
            unchecked {
                // shouldn't overflow
                ++i;
            }
        }

        // TODO: event
    }

    function recoverNonTargetFunds(address nonTargetToken, address beneficiary)
        external
        payable
    {
        /// checks

        if (nonTargetToken == token) revert
            InvalidTokenRecovery_InvalidNonTargetToken();

        bool validBeneficiary = false;
        for (uint256 i = 0; i < finalTranche;) {
            if (trancheRecipient[i] == beneficiary) {
                validBeneficiary = true;
                break;
            }
            unchecked {
                // shouldn't overflow
                ++i;
            }
        }
        if (!validBeneficiary) {
            revert InvalidTokenRecovery_InvalidBeneficiary();
        }

        /// effects

        /// interactions

        if (nonTargetToken == address(0)) {
            beneficiary.safeTransferETH(address(this).balance);
        } else {
            ERC20(nonTargetToken).safeTransfer(
                beneficiary, ERC20(nonTargetToken).balanceOf(address(this))
            );
        }

        // TODO: event
    }
}
