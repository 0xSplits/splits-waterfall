// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// TODO: add erc20 support / prevent locking
// TODO: prevent non-target fund locking
// allow anyone to withdraw non-target erc20s (or eth) to ~any recipient
// TODO: ? add create2 support
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

/// @title WaterfallModule
/// @author 0xSplits <will@0xSplits.xyz>
/// @notice TODO
/// @dev TODO
contract WaterfallModule {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;

    /// -----------------------------------------------------------------------
    /// types
    /// -----------------------------------------------------------------------

    // TODO
    /* type Tranche is uint256; */

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

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

    uint256 public distributedETH;
    // TODO: private?
    uint256 public activeTranche;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(
        address[] memory _trancheRecipient,
        uint256[] memory _trancheThreshold
    ) {
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

        // TODO: event
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

        // TODO: add w erc20 support

        /// effects

        // load storage into memory

        uint256 _startingDistributedETH = distributedETH;
        // TODO: test against re-entrancy
        // distributed eth will have increased but address.balance may still be positive
        // think not: og call will revert
        uint256 _distributedETH;
        unchecked {
            // shouldn't overflow
            _distributedETH = _startingDistributedETH + address(this).balance;
        }

        uint256 _startingActiveTranche = activeTranche;
        uint256 _activeTranche = _startingActiveTranche;

        for (; _activeTranche < finalTranche;) {
            if (trancheThreshold[_activeTranche] >= _distributedETH) {
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

        uint256 _paidOut = _startingDistributedETH;
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
            // _paidOut = last tranche threshold, which should be <= _distributedETH by construction
            _payouts[i] = _distributedETH - _paidOut;

            distributedETH = _distributedETH;
            // if total amount of distributed ETH is equal to the last tranche threshold, advance
            // the active tranche by one
            // shouldn't overflow
            activeTranche =
                _activeTranche + (_trancheThreshold == _distributedETH ? 1 : 0);
        }

        /// interactions

        // pay outs
        for (i = 0; i < _payoutsLength;) {
            (_payoutAddresses[i]).safeTransferETH(_payouts[i]);
            unchecked {
                // shouldn't overflow
                ++i;
            }
        }

        // TODO: event
    }
}
