// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import {Clone} from "clones-with-immutable-args/Clone.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// TODO: add similar recovery for 721 / 1155
// TODO: natspec

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

    address internal constant ETH_ADDRESS = address(0);
    uint256 internal constant THRESHOLD_BITS = 96;
    uint256 internal constant ADDRESS_BITS = 160;
    uint256 internal constant ADDRESS_BITMASK = uint256(~0 >> THRESHOLD_BITS);

    /// Address of ERC20 to waterfall (0x0 used for ETH)
    /// @dev equivalent to address public immutable token;
    function token() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// Number of waterfall tranches
    /// @dev equivalent to uint256 internal immutable numTranches;
    function numTranches() internal pure returns (uint256) {
        return _getArgUint256(20);
    }

    /// Waterfall tranches
    /// @dev equivalent to uint256[] internal immutable tranches;
    function _tranches() internal pure returns (uint256[] memory) {
        return _getArgUint256Array(52, uint64(numTranches()));
    }

    uint256 public distributedFunds;
    uint256 internal activeTranche;

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

        address _token = token();
        uint256 _startingDistributedFunds = distributedFunds;
        uint256 _distributedFunds;
        unchecked {
            // shouldn't overflow
            _distributedFunds = _startingDistributedFunds
                +
                // recognizes 0x0 as ETH
                // shouldn't need to worry about re-entrancy from ERC20 view fn
                (
                    _token == ETH_ADDRESS
                        ? address(this).balance
                        : ERC20(_token).balanceOf(address(this))
                );
        }

        uint256 _startingActiveTranche = activeTranche;
        uint256 _activeTranche = _startingActiveTranche;

        (address[] memory trancheRecipients, uint256[] memory trancheThresholds)
            = getTranches();

        // combine loop; activeTranche; general gas

        // TODO: could use single loop if willing to make array w size {numTranches() - _activeTranche}
        // and edit length directly in memory w assembly
        // TODO: could get rid of _activeTranche & calc breakeven (should save gas for smaller waterfalls)
        // what's the breakeven?

        // adding scope allows compiler to discard vars on stack to avoid stack-too-deep
        {
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
        }

        uint256 _payoutsLength;
        unchecked {
            // shouldn't underflow since _activeTranche >= _startingActiveTranche
            _payoutsLength = _activeTranche - _startingActiveTranche + 1;
        }
        address[] memory _payoutAddresses = new address[](_payoutsLength);
        uint256[] memory _payouts = new uint256[](_payoutsLength);

        // adding scope allows compiler to discard vars on stack to avoid stack-too-deep
        {
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
                activeTranche = _activeTranche
                    + (_trancheThreshold == _distributedFunds ? 1 : 0);
            }
        }

        /// interactions

        // pay outs
        // earlier external calls may try to re-enter but will cause fn to revert
        // when later external calls fail (bc balance is emptied early)
        for (uint256 i = 0; i < _payoutsLength;) {
            if (_token == ETH_ADDRESS) {
                (_payoutAddresses[i]).safeTransferETH(_payouts[i]);
            } else {
                ERC20(_token).safeTransfer(_payoutAddresses[i], _payouts[i]);
            }
            unchecked {
                // shouldn't overflow
                ++i;
            }
        }

        // TODO: finalize args
        // technically don't need ~any for subgraph, but nice for readability / devex
        // but also kind of already replicated by etherscan's ui showing xfrs
        // could either have no args or token & amount distributed
        emit WaterfallFunds(_payoutAddresses, _payouts);
    }

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

        (address[] memory trancheRecipients,) = getTranches();
        bool validRecipient = false;
        uint256 _numTranches = numTranches();
        for (uint256 i = 0; i < _numTranches;) {
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
        if (nonWaterfallToken == ETH_ADDRESS) {
            amount = address(this).balance;
            recipient.safeTransferETH(amount);
        } else {
            amount = ERC20(nonWaterfallToken).balanceOf(address(this));
            ERC20(nonWaterfallToken).safeTransfer(recipient, amount);
        }

        emit RecoverNonWaterfallFunds(nonWaterfallToken, recipient, amount);
    }

    /// -----------------------------------------------------------------------
    /// functions - view & pure
    /// -----------------------------------------------------------------------

    function getTranches()
        public
        pure
        returns (
            address[] memory trancheRecipients,
            uint256[] memory trancheThresholds
        )
    {
        uint256 numRecipients = numTranches();
        uint256 numThresholds;
        unchecked {
            // shouldn't underflow
            numThresholds = numRecipients - 1;
        }
        trancheRecipients = new address[](numRecipients);
        trancheThresholds = new uint256[](numThresholds);

        uint256 i = 0;
        uint256 tranche;
        for (; i < numThresholds;) {
            tranche = _getTranche(i);
            trancheRecipients[i] = address(uint160(tranche));
            trancheThresholds[i] = tranche >> ADDRESS_BITS;
            unchecked {
                ++i;
            }
        }
        // trancheRecipients has one more entry than trancheThresholds
        trancheRecipients[i] = address(uint160(_getTranche(i)));
    }

    function _getTranche(uint256 i) internal pure returns (uint256) {
        unchecked {
            // shouldn't overflow
            return _getArgUint256(52 + i * 32);
        }
    }
}
