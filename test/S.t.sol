// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import 'forge-std/Test.sol';
import '../src/SlotChain.sol'; // adjust path

/// @notice Minimal interface for testing the SlotChain contract
interface ISlotChain {
    /// @notice Returns the tokenId of the active or next upcoming booking for a user
    function activeBookingOf(
        address user
    ) external view returns (uint256 tokenId);
}

contract SlotChainTest is SlotChain, Test {
    SlotChain slotChain;

    function setUp() public {
        // Deploy the contract or load an existing address
        slotChain = SlotChain(0x325837D44cF0aeF6869A7Fdeac51626B34d29883);
    }

    function testS() public {
        address user = 0xF6211448a2f522EAdcbDbF2f46CeaE43237E2bA7;
        vm.startPrank(user);
        uint256 tokenId = slotChain.activeBookingOf(user);
        console.log('Active tokenId:', tokenId);
    }
}
