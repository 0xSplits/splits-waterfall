// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import {WaterfallModule} from "./WaterfallModule.sol";
import {ClonesWithImmutableArgs} from
    "clones-with-immutable-args/ClonesWithImmutableArgs.sol";

/// @title WaterfallModule
/// @author 0xSplits
/// @notice  A factory contract for cheaply deploying WaterfallModules.
/// @dev This factory uses our own extension of clones-with-immutable-args to avoid
/// `DELEGATECALL` inside `receive()` to accept hard gas-capped `sends` & `transfers`
/// for maximum backwards composability.

contract WaterfallModuleFactory {
    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    /// Invalid number of recipients, must have at least 2
    error InvalidWaterfall__TooFewRecipients();

    /// Invalid recipient & threshold lengths; recipients must have one more entry
    /// than thresholds
    error InvalidWaterfall__RecipientsAndThresholdsLengthMismatch();

    /// Thresholds must be positive
    error InvalidWaterfall__ZeroThreshold();

    /// Invalid threshold at `index` (thresholds must increase monotonically)
    /// @param index Index of out-of-order threshold
    error InvalidWaterfall__ThresholdsOutOfOrder(uint256 index);

    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using ClonesWithImmutableArgs for address;

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    /// Emitted after a new waterfall module is deployed
    /// @param waterfallModule Address of newly created WaterfallModule clone
    /// @param token Address of ERC20 to waterfall (0x0 used for ETH)
    /// @param trancheRecipients Addresses to waterfall payments to
    /// @param trancheThresholds Absolute thresholds for payment waterfall
    event CreateWaterfallModule(
        address indexed waterfallModule,
        address token,
        address[] trancheRecipients,
        uint256[] trancheThresholds
    );

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    uint256 internal constant ADDRESS_BITS = 160;

    WaterfallModule public immutable wmImpl;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor() {
        wmImpl = new WaterfallModule();
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    // TODO: test memory v calldata
    // TODO: uint96 v uint256 & check manually? may not need to check, just truncate
    // if you don't check, need to run checks after truncating (e.g. no zero, sorted etc)

    /// Creates new WaterfallModule clone
    /// @param token Address of ERC20 to waterfall (0x0 used for ETH)
    /// @param trancheRecipients Addresses to waterfall payments to
    /// @param trancheThresholds Absolute thresholds for payment waterfall
    /// @return wm Address of new WaterfallModule clone
    function createWaterfallModule(
        address token,
        address[] calldata trancheRecipients,
        uint256[] calldata trancheThresholds
    )
        external
        returns (WaterfallModule wm)
    {
        /// checks

        // TODO: gas test caching lengths

        // ensure recipients array has at least 2 entries
        if (trancheRecipients.length < 2) revert
            InvalidWaterfall__TooFewRecipients();
        // ensure recipients array is one longer than thresholds array
        unchecked {
            // shouldn't underflow since _trancheRecipientsLength >= 2
            if (trancheThresholds.length != trancheRecipients.length - 1) revert
                InvalidWaterfall__RecipientsAndThresholdsLengthMismatch();
        }
        // ensure first threshold isn't zero
        if (trancheThresholds[0] == 0) revert InvalidWaterfall__ZeroThreshold();
        // ensure thresholds increase monotonically
        uint256 i = 1;
        for (; i < trancheThresholds.length;) {
            unchecked {
                // shouldn't underflow since i >= 1
                if (trancheThresholds[i - 1] >= trancheThresholds[i]) revert
                    InvalidWaterfall__ThresholdsOutOfOrder(i);
                // shouldn't overflow
                ++i;
            }
        }

        // copy recipients & thresholds into storage
        i = 0;
        uint256[] memory tranches = new uint256[](trancheRecipients.length);
        uint256 loopLength = tranches.length - 1;
        for (; i < loopLength;) {
            tranches[i] = (trancheThresholds[i] << ADDRESS_BITS)
                | uint256(uint160(trancheRecipients[i]));
            unchecked {
                // shouldn't overflow
                ++i;
            }
        }
        // recipients array is one longer than thresholds array; set last item after loop
        tranches[i] = uint256(uint160(trancheRecipients[i]));

        /// effects

        bytes memory data = abi.encodePacked(token, tranches.length, tranches);
        wm = WaterfallModule(address(wmImpl).clone(data));
        emit CreateWaterfallModule(
            address(wm), token, trancheRecipients, trancheThresholds
            );
    }
}
