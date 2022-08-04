// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import {Clone} from "clones-with-immutable-args/Clone.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// TODO: gas test: cache token()
// TODO: revisit event args
// TODO: add similar recovery for 721 / 1155 ?
// TODO: fuzz testing
// TODO: natspec
// TODO: docs that thresholds are absolute

/// @title WaterfallModule
/// @author 0xSplits
/// @notice TODO
/// @dev TODO
/// This contract uses token = address(0) to refer to ETH.

contract WaterfallModule is Clone {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    /// Invalid token recovery nonWaterfallToken
    error InvalidTokenRecovery_WaterfallToken();

    /// Invalid token recovery recipient
    error InvalidTokenRecovery_InvalidRecipient();

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    /// Emitted after each successful ETH transfer to proxy
    /// @param amount Amount of ETH received
    /// @dev embedded in & emitted from clone bytecode
    event ReceiveETH(uint256 amount);

    /// Emitted after funds are waterfall'd to recipients
    /// @param recipients x
    /// @param payouts x
    event WaterfallFunds(address[] recipients, uint256[] payouts);

    /// Emitted after non-waterfall'd tokens are recovered to a recipient
    /// @param nonWaterfallToken x
    /// @param recipient x
    /// @param amount x
    event RecoverNonWaterfallFunds(
        address nonWaterfallToken,
        address recipient,
        uint256 amount
    );

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    uint256 internal constant THRESHOLD_BITS = 96;
    uint256 internal constant ADDRESS_BITS = 160;
    // TODO: gas test ~0 vs type( uint256 ).max
    uint256 internal constant ADDRESS_BITMASK = uint256(~0 >> THRESHOLD_BITS);

    /// Address of ERC20 to waterfall (0x0 used for ETH)
    /// @dev equivalent to address public immutable token;
    function token() public pure returns (address) {
        return _getArgAddress(0);
    }

    // TODO: private / internal?
    /// Number of waterfall tranches
    /// @dev equivalent to uint256 public immutable numTranches;
    function numTranches() public pure returns (uint256) {
        return _getArgUint256(20);
    }

    /// Waterfall tranches
    /// @dev equivalent to uint256[] internal immutable tranches;
    function _tranches() internal pure returns (uint256[] memory) {
        return _getArgUint256Array(52, uint64(numTranches()));
    }

    uint256 public distributedFunds;
    // TODO: internal?
    // TODO: gas test calc'ing live (since array is immutable might be cheaper than SLOAD)
    uint256 public activeTranche;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    // solhint-disable-next-line no-empty-blocks
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
            _distributedFunds = _startingDistributedFunds
                +
                // recognizes 0x0 as ETH
                // shouldn't need to worry about re-entrancy from ERC20 view fn
                (
                    token() == address(0)
                        ? address(this).balance
                        : ERC20(token()).balanceOf(address(this))
                );
        }

        uint256 _startingActiveTranche = activeTranche;
        uint256 _activeTranche = _startingActiveTranche;

        (address[] memory trancheRecipients, uint256[] memory trancheThresholds)
            = getTranches();

        // TODO: could use single loop if willing to make array w size {numTranches() - _activeTranche}
        // may have to copy array over later pending final event args
        // could also .. edit length directly in memory w yul?
        // TODO: could get rid of _activeTranche & re-calc

        // TODO: cache?
        uint256 finalTranche = numTranches() - 1;
        for (; _activeTranche < finalTranche;) {
            if (trancheThresholds[_activeTranche] >= _distributedFunds) {
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

                _payoutAddresses[i] = trancheRecipients[_trancheIndex];
                _trancheThreshold = trancheThresholds[_trancheIndex];
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

            _payoutAddresses[i] = trancheRecipients[_trancheIndex];
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
            if (token() == address(0)) {
                (_payoutAddresses[i]).safeTransferETH(_payouts[i]);
            } else {
                ERC20(token()).safeTransfer(_payoutAddresses[i], _payouts[i]);
            }
            unchecked {
                // shouldn't overflow
                ++i;
            }
        }

        // TODO: are these the right args?
        // technically don't need ~any for subgraph, but nice for readability / devex
        emit WaterfallFunds(_payoutAddresses, _payouts);
    }

    // TODO: add similar fn for recovery of 721? 1155?

    function recoverNonWaterfallFunds(
        address nonWaterfallToken,
        address recipient
    )
        external
        payable
    {
        /// checks

        if (nonWaterfallToken == token()) revert
            InvalidTokenRecovery_WaterfallToken();

        // TODO: add fn to just pull recipients
        (address[] memory trancheRecipients,) = getTranches();
        bool validRecipient = false;
        // TODO: cache?
        for (uint256 i = 0; i < numTranches();) {
            if (trancheRecipients[i] == recipient) {
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

        uint256 amount;
        if (nonWaterfallToken == address(0)) {
            amount = address(this).balance;
            recipient.safeTransferETH(amount);
        } else {
            amount = ERC20(nonWaterfallToken).balanceOf(address(this));
            ERC20(nonWaterfallToken).safeTransfer(recipient, amount);
        }

        emit RecoverNonWaterfallFunds(nonWaterfallToken, recipient, amount);
    }

    /// -----------------------------------------------------------------------
    /// functions - views
    /// -----------------------------------------------------------------------

    // TODO: add custom getter / view for _tranches()

    function getTranches()
        public
        pure
        returns (
            address[] memory trancheRecipients,
            uint256[] memory trancheThresholds
        )
    {
        // TODO: gas test
        /* uint256 numTranches = numTranches(); */
        trancheRecipients = new address[](numTranches());
        unchecked {
            // shouldn't underflow
            trancheThresholds = new uint256[](numTranches() - 1);
        }

        uint256 i = 0;
        uint256 tranche;
        // TODO: gas test v numTranches() - 1 v caching earlier
        uint256 loopLength = trancheThresholds.length;
        for (; i < loopLength;) {
            // TODO: gas test vs loading full array
            tranche = _getTranche(i);
            trancheRecipients[i] = address(uint160(tranche & ADDRESS_BITMASK));
            trancheThresholds[i] = tranche >> ADDRESS_BITS;
            unchecked {
                ++i;
            }
        }
        // trancheRecipients has one more entry than trancheThresholds
        tranche = _getTranche(i);
        trancheRecipients[i] = address(uint160(tranche & ADDRESS_BITMASK));
    }

    function _getTranche(uint256 i) internal pure returns (uint256) {
        unchecked {
            // shouldn't overflow
            return _getArgUint256(52 + i * 32);
        }
    }
}
