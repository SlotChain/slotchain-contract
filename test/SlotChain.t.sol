// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from 'forge-std/Test.sol';
import {SlotChain} from '../src/SlotChain.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

// Simple mintable ERC20 used as the booking token.
contract MockERC20 is ERC20 {
    constructor() ERC20('Mock USDT', 'mUSDT') {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SlotChainTest is Test {
    SlotChain internal implementation;
    SlotChain internal slotChain;
    MockERC20 internal baseToken;

    address internal owner = address(0xA11CE);
    address internal platformWallet = address(0xBEEF);
    address internal creator = address(0xCAFE);
    address internal user = address(0xF00D);
    address internal otherUser = address(0xF00E);

    uint256 internal constant INITIAL_BALANCE = 1_000 ether;
    uint256 internal constant HOURLY_RATE = 100 ether;
    string internal constant CREATOR_URI = 'ipfs://creator-profile';

    function setUp() public {
        baseToken = new MockERC20();
        implementation = new SlotChain();

        bytes memory initData = abi.encodeWithSelector(
            SlotChain.initialize.selector,
            owner,
            address(baseToken),
            platformWallet
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        slotChain = SlotChain(address(proxy));

        baseToken.mint(user, INITIAL_BALANCE);
        baseToken.mint(otherUser, INITIAL_BALANCE);

        vm.prank(user);
        baseToken.approve(address(slotChain), type(uint256).max);
        vm.prank(otherUser);
        baseToken.approve(address(slotChain), type(uint256).max);
    }

    function registerCreator() internal {
        vm.prank(creator);
        slotChain.createProfile(HOURLY_RATE, CREATOR_URI);
    }

    function book(
        address booker,
        uint256 start,
        uint256 end
    ) internal returns (uint256 tokenId) {
        vm.prank(booker);
        tokenId = slotChain.bookSlot(creator, start, end);
    }

    function testInitializeSetsState() public {
        assertEq(slotChain.owner(), owner);
        assertEq(address(slotChain.baseToken()), address(baseToken));
        assertEq(slotChain.platformWallet(), platformWallet);
        assertEq(slotChain.feeInPPM(), 50_000);
    }

    function testCreateProfileStoresValuesAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit SlotChain.CreatorRegistered(creator, HOURLY_RATE, CREATOR_URI);

        vm.prank(creator);
        slotChain.createProfile(HOURLY_RATE, CREATOR_URI);

        (
            address storedCreator,
            uint256 storedRate,
            string memory storedURI,
            bool exists
        ) = slotChain.creatorsProfiles(creator);

        assertEq(storedCreator, creator);
        assertEq(storedRate, HOURLY_RATE);
        assertEq(storedURI, CREATOR_URI);
        assertTrue(exists);
    }

    function testCreateProfileRevertsWhenRateIsZero() public {
        vm.expectRevert(SlotChain.ZeroValue.selector);
        vm.prank(creator);
        slotChain.createProfile(0, CREATOR_URI);
    }

    function testCreateProfileRevertsWhenUriIsEmpty() public {
        vm.expectRevert(SlotChain.InvalidURI.selector);
        vm.prank(creator);
        slotChain.createProfile(HOURLY_RATE, '');
    }

    function testCreateProfileRevertsWhenAlreadyRegistered() public {
        registerCreator();

        vm.expectRevert(SlotChain.AlreadyRegistered.selector);
        vm.prank(creator);
        slotChain.createProfile(HOURLY_RATE, CREATOR_URI);
    }

    function testUpdateProfileUpdatesValuesAndEmits() public {
        registerCreator();

        string memory updatedURI = 'ipfs://creator-updated';
        uint256 updatedRate = HOURLY_RATE + 10 ether;

        vm.expectEmit(true, true, true, true);
        emit SlotChain.ProfileUpdated(
            creator,
            CREATOR_URI,
            updatedURI,
            updatedRate
        );

        vm.prank(creator);
        slotChain.updateProfile(updatedRate, updatedURI);

        (, uint256 storedRate, string memory storedURI, ) = slotChain
            .creatorsProfiles(creator);

        assertEq(storedRate, updatedRate);
        assertEq(storedURI, updatedURI);
    }

    function testUpdateProfileRevertsWhenNotRegistered() public {
        vm.expectRevert(SlotChain.NotRegistered.selector);
        vm.prank(creator);
        slotChain.updateProfile(HOURLY_RATE, CREATOR_URI);
    }

    function testUpdateProfileRevertsWhenRateIsZero() public {
        registerCreator();

        vm.expectRevert(SlotChain.ZeroValue.selector);
        vm.prank(creator);
        slotChain.updateProfile(0, CREATOR_URI);
    }

    function testUpdateProfileRevertsWhenUriIsEmpty() public {
        registerCreator();

        vm.expectRevert(SlotChain.InvalidURI.selector);
        vm.prank(creator);
        slotChain.updateProfile(HOURLY_RATE, '');
    }

    function testBookSlotMintsTokenAndRecordsBooking() public {
        registerCreator();
        vm.warp(1_000);

        uint256 start = block.timestamp + 100;
        uint256 end = start + 1 hours;
        vm.expectEmit(true, true, true, true);
        emit SlotChain.SlotBooked(user, creator, 0, start, end, HOURLY_RATE);

        uint256 tokenId = book(user, start, end);
        uint256 expectedFee = (HOURLY_RATE * slotChain.feeInPPM()) / 1_000_000;
        uint256 expectedCreatorShare = HOURLY_RATE - expectedFee;

        verifyOwnershipAndBalances(tokenId, expectedFee, expectedCreatorShare);
    }

    function testBookSlotRevertsWhenCreatorNotRegistered() public {
        vm.expectRevert(SlotChain.CreatorNotFound.selector);
        vm.prank(user);
        slotChain.bookSlot(creator, block.timestamp + 1, block.timestamp + 2);
    }

    function testBookSlotRevertsWhenEndNotGreaterThanStart() public {
        registerCreator();

        uint256 start = block.timestamp + 10;
        vm.expectRevert(SlotChain.InvalidTime.selector);
        vm.prank(user);
        slotChain.bookSlot(creator, start, start);
    }

    function testBookSlotRevertsWhenEndNotInFuture() public {
        registerCreator();

        vm.warp(10_000);
        uint256 start = block.timestamp - 200;
        uint256 end = block.timestamp - 100;

        vm.expectRevert(SlotChain.InvalidTime.selector);
        vm.prank(user);
        slotChain.bookSlot(creator, start, end);
    }

    function testBookSlotRevertsWhenCreatorBooksOwnSlot() public {
        registerCreator();

        uint256 start = block.timestamp + 10;
        uint256 end = start + 1 hours;

        vm.expectRevert(SlotChain.InvalidRequest.selector);
        vm.prank(creator);
        slotChain.bookSlot(creator, start, end);
    }

    function testMultipleBookings_IncrementTokenIds() public {
        registerCreator();
        vm.warp(1_000);

        uint256 start1 = block.timestamp + 50;
        uint256 end1 = start1 + 1 hours;
        uint256 start2 = end1 + 50;
        uint256 end2 = start2 + 1 hours;

        uint256 tokenId1 = book(user, start1, end1);
        uint256 tokenId2 = book(user, start2, end2);

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);

        vm.warp(start1 + 10);
        vm.prank(user);
        assertEq(slotChain.activeBookingOf(user), tokenId1);

        vm.warp(end1 + 1);
        vm.prank(user);
        assertEq(slotChain.activeBookingOf(user), tokenId2);

        vm.warp(end2 + 1);
        vm.prank(user);
        assertEq(slotChain.activeBookingOf(user), 0);
    }

    function testTransferMovesOwnership() public {
        registerCreator();
        vm.warp(1_000);

        uint256 start = block.timestamp + 100;
        uint256 end = start + 1 hours;
        uint256 tokenId = book(user, start, end);

        vm.prank(user);
        slotChain.transferFrom(user, otherUser, tokenId);

        assertEq(slotChain.ownerOf(tokenId), otherUser);
        assertEq(slotChain.balanceOf(user), 0);
        assertEq(slotChain.balanceOf(otherUser), 1);
    }

    function testBurnRemovesTokenFromOwnerBalance() public {
        registerCreator();
        vm.warp(1_000);

        uint256 start = block.timestamp + 100;
        uint256 end = start + 1 hours;
        uint256 tokenId = book(user, start, end);

        vm.prank(user);
        slotChain.burn(tokenId);

        assertEq(slotChain.balanceOf(user), 0);
        vm.expectRevert('ERC721: invalid token ID');
        slotChain.ownerOf(tokenId);
    }

    function testActiveBookingOfReturnsZeroWhenNoBookings() public {
        vm.prank(user);
        assertEq(slotChain.activeBookingOf(user), 0);
    }

    function testActiveBookingOfReturnsZeroWhenOnlyPastBookingsExist() public {
        registerCreator();
        vm.warp(1_000);

        uint256 start = block.timestamp + 10;
        uint256 end = start + 1 hours;
        book(user, start, end);

        vm.warp(end + 10);
        vm.prank(user);
        assertEq(slotChain.activeBookingOf(user), 0);
    }

    function testActiveBookingOfReturnsUpcomingBookingForOwner() public {
        registerCreator();
        vm.warp(1_000);

        uint256 start = block.timestamp + 100;
        uint256 end = start + 30 minutes;
        uint256 tokenId = book(user, start, end);

        vm.prank(user);
        uint256 activeTokenId = slotChain.activeBookingOf(user);

        assertEq(activeTokenId, tokenId);
    }

    function testActiveBookingOfReturnsZeroForDifferentUser() public {
        registerCreator();
        vm.warp(1_000);

        uint256 start = block.timestamp + 100;
        uint256 end = start + 30 minutes;
        book(user, start, end);

        vm.prank(otherUser);
        uint256 activeTokenId = slotChain.activeBookingOf(user);

        assertEq(activeTokenId, 0);
    }

    function testActiveBookingOfPrefersInProgressBooking() public {
        registerCreator();
        vm.warp(1_000);

        uint256 startActive = block.timestamp + 100;
        uint256 endActive = startActive + 30 minutes;
        uint256 startFuture = endActive + 100;
        uint256 endFuture = startFuture + 30 minutes;

        uint256 activeTokenId = book(user, startActive, endActive);
        uint256 futureTokenId = book(user, startFuture, endFuture);

        assertEq(activeTokenId, 0);
        assertEq(futureTokenId, 1);

        vm.warp(startActive + 5 minutes);

        vm.prank(user);
        assertEq(slotChain.activeBookingOf(user), activeTokenId);
    }

    function testBookingsMappingStoresDetails() public {
        registerCreator();
        vm.warp(2_000);

        uint256 start = block.timestamp + 60;
        uint256 end = start + 45 minutes;
        uint256 tokenId = book(user, start, end);

        SlotChain.Booking memory stored = slotChain.bookings(tokenId);

        assertEq(stored.creator, creator);
        assertEq(stored.startsAt, start);
        assertEq(stored.expiresAt, end);
        assertEq(stored.amount, HOURLY_RATE);
    }

    function testIsActiveTracksLifecycle() public {
        registerCreator();
        vm.warp(3_000);

        uint256 start = block.timestamp + 30;
        uint256 end = start + 1 hours;
        uint256 tokenId = book(user, start, end);

        vm.warp(start + 10);
        assertTrue(slotChain.isActive(tokenId));

        vm.warp(end + 1);
        assertFalse(slotChain.isActive(tokenId));
    }

    function testUpdatePlatFormFeeUpdatesValue() public {
        uint256 newFee = 60_000;
        vm.prank(owner);
        slotChain.updatePlatFormFee(newFee);

        assertEq(slotChain.feeInPPM(), newFee);
    }

    function testUpdatePlatFormFeeRevertsForInvalidValue() public {
        vm.expectRevert(SlotChain.ZeroValue.selector);
        vm.prank(owner);
        slotChain.updatePlatFormFee(0);

        vm.expectRevert(SlotChain.InvalidFee.selector);
        vm.prank(owner);
        slotChain.updatePlatFormFee(slotChain.feeInPPM());
    }

    function testUpdatePlatFormFeeRevertsForNonOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        vm.prank(user);
        slotChain.updatePlatFormFee(60_000);
    }

    function testUpdatePlatformWalletUpdatesValue() public {
        address newWallet = address(0x1234);
        vm.prank(owner);
        slotChain.updatePlatformWallet(newWallet);

        assertEq(slotChain.platformWallet(), newWallet);
    }

    function testUpdatePlatformWalletRevertsForInvalidValue() public {
        vm.expectRevert(SlotChain.ZeroAddress.selector);
        vm.prank(owner);
        slotChain.updatePlatformWallet(address(0));

        vm.expectRevert(SlotChain.InvalidAddress.selector);
        vm.prank(owner);
        slotChain.updatePlatformWallet(platformWallet);
    }

    function testUpdatePlatformWalletRevertsForNonOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        vm.prank(user);
        slotChain.updatePlatformWallet(address(0x4321));
    }

    // Helpers -----------------------------------------------------------------

    function verifyOwnershipAndBalances(
        uint256 tokenId,
        uint256 expectedFee,
        uint256 expectedCreatorShare
    ) internal {
        assertEq(slotChain.ownerOf(tokenId), user);
        assertEq(slotChain.balanceOf(user), 1);
        assertEq(baseToken.balanceOf(address(slotChain)), expectedFee);
        assertEq(baseToken.balanceOf(creator), expectedCreatorShare);
        assertEq(baseToken.balanceOf(user), INITIAL_BALANCE - HOURLY_RATE);
        vm.prank(user);
        assertEq(slotChain.activeBookingOf(user), tokenId);
    }
}
