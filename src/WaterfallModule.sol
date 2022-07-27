// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// TODO: convert to clone
// TODO: add erc20 support / prevent locking
// TODO: ? add create2 support
// TODO: natspec

// TODO: errors inside vs outside contract?
/// -----------------------------------------------------------------------
/// errors
/// -----------------------------------------------------------------------

// TODO: add error args?

/// Invalid number of recipients, must have at least 2
error InvalidWaterfall__TooFewRecipients();

/// Invalid recipient & threshold lengths; recipients must have one more entry
/// than thresholds
error InvalidWaterfall__RecipientsAndThresholdLengthMismatch();

/// Invalid threshold at `index` (thresholds must increase monotonically)
/// @param index Index of out-of-order threshold
error InvalidWaterfall__ThresholdOutOfOrder(uint256 index);

/// @title WaterfallModule
/// @author 0xSplits <will@0xSplits.xyz>
/// @notice
/// @dev

contract WaterfallModule {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;

    /// -----------------------------------------------------------------------
    /// types
    /// -----------------------------------------------------------------------

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

    // TODO: test gas vs memory
    constructor(
        address[] memory _trancheRecipient,
        uint256[] memory _trancheThreshold
    ) {
        // TODO: gas test
        // cache lengths in memory
        uint256 _trancheRecipientLength = _trancheRecipient.length;
        uint256 _trancheThresholdLength = _trancheThreshold.length;
        finalTranche = _trancheThresholdLength;

        // ensure recipients array has at least 2 entries
        if (_trancheRecipientLength < 2) revert
            InvalidWaterfall__TooFewRecipients();
        // ensure recipients array is one longer than thresholds array
        if (_trancheThresholdLength != _trancheRecipientLength - 1) revert
            InvalidWaterfall__RecipientsAndThresholdLengthMismatch();
        // ensure thresholds increase monotonically
        for (uint256 j = 1; j < _trancheThresholdLength;) {
            if (_trancheThreshold[j - 1] >= _trancheThreshold[j]) revert
                InvalidWaterfall__ThresholdOutOfOrder(j);
            // TODO: gas test
            unchecked {
                ++j;
            }
        }
        // TODO: check if first is non-zero? or do we care? technically doesn't make sense, but maybe don't want to revert on it

        // copy recipients & thresholds into storage
        uint256 i = 0;
        trancheRecipient = new address[](_trancheRecipientLength);
        trancheThreshold = new uint256[](_trancheThresholdLength);
        for (; i < _trancheThresholdLength;) {
            trancheThreshold[i] = _trancheThreshold[i];
            trancheRecipient[i] = _trancheRecipient[i];
            // TODO: gas test
            unchecked {
                ++i;
            }
        }
        // recipients array is one longer than thresholds array
        /* trancheRecipient[i] = _trancheRecipient[i]; */
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

    // payable?
    function waterfallFunds() external payable {
        /// load storage into memory

        uint256 _startingDistributedETH = distributedETH;
        // is there an issue w re-entrancy?
        // distributed eth will have increased but address.balance may still be positive
        // think not: og call will revert
        // unchecked?
        uint256 _distributedETH =
            _startingDistributedETH + address(this).balance;

        uint256 _startingActiveTranche = activeTranche;
        uint256 _activeTranche = _startingActiveTranche;

        /// effects

        // loop from _activeTranche to finalTranche to see how many tranches get hit
        // then re-loop with that knowledge to generate the _payouts array
        // then see if you can merge the for-loops?

        // generate arrays or indexes and amounts of payouts
        // or... one array of payouts where
        // [0] pays to recipient[active],
        // [1] pays to recipient[active+1], etc

        for (; _activeTranche < finalTranche;) {
            // >= ?
            // handle edge case where threshold == newDist
            if (trancheThreshold[_activeTranche] >= _distributedETH) {
                break;
            }
            unchecked {
                ++_activeTranche;
            }
        }

        uint256 _payoutsLength = _activeTranche - _startingActiveTranche + 1;
        address[] memory _payoutAddresses = new address[](_payoutsLength);
        uint256[] memory _payouts = new uint256[](_payoutsLength);

        uint256 _paidOut = _startingDistributedETH;
        uint256 _trancheIndex;
        uint256 _trancheThreshold;
        uint256 _payoutThreshold;
        uint256 i = 0;
        for (; i < _payoutsLength - 1;) {
            // unchecked?
            _trancheIndex = _startingActiveTranche + i;
            _payoutAddresses[i] = trancheRecipient[_trancheIndex];
            _trancheThreshold = trancheThreshold[_trancheIndex];
            _payouts[i] = _trancheThreshold - _paidOut;
            _paidOut = _trancheThreshold;
            unchecked {
                ++i;
            }
        }
        // i = _payoutsLength - 1, i.e. last payout
        _trancheIndex = _startingActiveTranche + i;
        _payoutAddresses[i] = trancheRecipient[_trancheIndex];
        /* _trancheThreshold = trancheThreshold[_trancheIndex]; */
        _payouts[i] = _distributedETH - _paidOut;

        distributedETH = _distributedETH;
        // TODO: unchecked?
        // if total amount of distributed ETH is equal to the last tranche threshold, advance
        // the active tranche by one
        activeTranche =
            _activeTranche + (_trancheThreshold == _distributedETH ? 1 : 0);

        /// interactions

        // pay outs
        for (uint256 i = 0; i < _payoutsLength;) {
            (_payoutAddresses[i]).safeTransferETH(_payouts[i]);
            unchecked {
                ++i;
            }
        }

        // event
    }
}
