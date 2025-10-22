// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// OpenZeppelin upgradeable imports (v5.4+)
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {ERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import {ERC721BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title SlotChain Booking Contract
/// @notice Upgradeable ERC721 for booking slots with USDT payments & creator registration
contract SlotChain is
    Initializable,
    ERC721Upgradeable,
    ERC721BurnableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice this structs store the creators data
    /// @param creator is address of creator
    /// @hourlyRate is the rate of Creator
    /// @profileURI profile URi is the URI of creators data posted to IPFS
    struct Creator {
        address creator;
        uint256 hourlyRate;
        string profileURI;
        bool exists;
    }

    struct Booking {
        address creator;
        uint256 startsAt;
        uint256 expiresAt;
        uint256 amount;
    }

    struct UserBooking {
        uint256 tokenId;
        address creator;
        uint256 startTime;
        uint256 expireTime;
    }

    uint256 private _nextTokenId = 1;
    IERC20 public baseToken;
    uint256 public feeInPPM;
    uint256 immutable PPM = 1e6;
    address public platformWallet;

    mapping(address => Creator) public creatorsProfiles;
    mapping(address => UserBooking[]) allUserBookings;
    mapping(uint256 => Booking) private _bookings;

    event CreatorRegistered(
        address indexed creator,
        uint256 hourlyRate,
        string profileURI
    );
    event ProfileUpdated(
        address indexed creator,
        string oldURI,
        string newURI,
        uint256 newRate
    );
    event SlotBooked(
        address indexed user,
        address indexed creator,
        uint256 tokenId,
        uint256 slotStart,
        uint256 slotEnd,
        uint256 amount
    );
    event BookingCancelled(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed operator,
        address creator
    );

    error InvalidAddress();
    error ZeroAddress();
    error ZeroValue();
    error InvalidURI();
    error AlreadyRegistered();
    error NotRegistered();
    error CreatorNotFound();
    error InvalidTime();
    error InvalidRequest();
    error InvalidFee();
    error NotFound();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address _usdt,
        address wallet
    ) public initializer {
        if (initialOwner == address(0)) revert ZeroAddress();
        if (_usdt == address(0)) revert ZeroAddress();
        if (wallet == address(0)) revert ZeroAddress();

        __ERC721_init('SlotChain', 'SLOT');
        __ERC721Burnable_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        baseToken = IERC20(_usdt);
        platformWallet = wallet;

        feeInPPM = 50000;
    }

    function createProfile(
        uint256 _hourlyRate,
        string calldata _profileURI
    ) external {
        if (_hourlyRate == 0) revert ZeroValue();
        if (bytes(_profileURI).length == 0) revert InvalidURI();
        if (creatorsProfiles[msg.sender].exists) revert AlreadyRegistered();

        creatorsProfiles[msg.sender] = Creator({
            creator: msg.sender,
            hourlyRate: _hourlyRate,
            profileURI: _profileURI,
            exists: true
        });

        emit CreatorRegistered(msg.sender, _hourlyRate, _profileURI);
    }

    /// @notice Mint a booking NFT after payment in USDT
    /// @param creator Address of the creator being booked
    /// @param slotStart Timestamp of slot start
    /// @param slotEnd Timestamp of slot end
    function bookSlot(
        address creator,
        uint256 slotStart,
        uint256 slotEnd
    ) external nonReentrant returns (uint256) {
        address user = msg.sender;
        Creator memory c = creatorsProfiles[creator];
        if (!c.exists) revert CreatorNotFound();
        if (slotEnd <= slotStart) revert InvalidTime();
        if (slotEnd <= block.timestamp) revert InvalidTime();
        if (user == c.creator) revert InvalidRequest();

        // First, clean up any expired bookings
        _removeExpiredBookings(user);

        // Handle payments
        uint256 fee = (c.hourlyRate * feeInPPM) / PPM;
        uint256 creatorShare = c.hourlyRate - fee;

        baseToken.safeTransferFrom(user, address(this), c.hourlyRate);
        if (fee > 0) baseToken.safeTransfer(platformWallet, fee);
        baseToken.safeTransfer(creator, creatorShare);

        // Record booking
        uint256 tokenId = ++_nextTokenId;

        allUserBookings[user].push(
            UserBooking({
                tokenId: tokenId,
                creator: creator,
                startTime: slotStart,
                expireTime: slotEnd
            })
        );

        _bookings[tokenId] = Booking({
            creator: creator,
            startsAt: slotStart,
            expiresAt: slotEnd,
            amount: c.hourlyRate
        });

        _safeMint(msg.sender, tokenId);

        emit SlotBooked(
            user,
            creator,
            tokenId,
            slotStart,
            slotEnd,
            c.hourlyRate
        );
        return tokenId;
    }

    /// @notice Remove all expired bookings for a user
    function _removeExpiredBookings(address user) private {
        UserBooking[] storage userBookings = allUserBookings[user];
        uint256 len = userBookings.length;
        uint256 i = 0;

        while (i < len) {
            if (userBookings[i].expireTime <= block.timestamp) {
                // shift array left by 1 (overwrite current index)
                for (uint256 j = i; j < len - 1; j++) {
                    userBookings[j] = userBookings[j + 1];
                }
                userBookings.pop();
                len--; // reduce array length
            } else {
                i++; // only increment if we didn't remove current index
            }
        }
    }

    function updateProfile(
        uint256 _hourlyRate,
        string calldata _profileURI
    ) external {
        Creator storage c = creatorsProfiles[msg.sender];
        if (!c.exists) revert NotRegistered();
        if (_hourlyRate == 0) revert ZeroValue();
        if (bytes(_profileURI).length == 0) revert InvalidURI();

        string memory oldURI = c.profileURI;
        c.hourlyRate = _hourlyRate;
        c.profileURI = _profileURI;

        emit ProfileUpdated(msg.sender, oldURI, _profileURI, _hourlyRate);
    }

    ///@notice must be sent in PPM eg: 1% = 1000
    function updatePlatFormFee(uint256 newFee) external onlyOwner {
        if (newFee == 0) revert ZeroValue();
        if (newFee == feeInPPM) revert InvalidFee();
        feeInPPM = newFee;
    }

    function updatePlatformWallet(address _newWallet) external onlyOwner {
        if (_newWallet == address(0)) revert ZeroAddress();
        if (_newWallet == platformWallet) revert InvalidAddress();
        platformWallet = _newWallet;
    }

    /// @notice Returns the tokenId of the earliest upcoming booking for the caller
    /// @dev Returns 0 if no future bookings exist
    function activeBookingOf(
        address user
    ) external view returns (uint256 tokenId) {
        if (user != msg.sender) {
            revert InvalidRequest();
        }
        UserBooking[] memory bookings = allUserBookings[msg.sender];
        uint256 len = bookings.length;
        uint256 nowTs = block.timestamp;

        uint256 activeStart = type(uint256).max;
        uint256 activeId;
        bool hasActive;

        uint256 upcomingStart = type(uint256).max;
        uint256 upcomingId;
        bool hasUpcoming;

        for (uint256 i = 0; i < len; i++) {
            UserBooking memory booking = bookings[i];
            if (booking.expireTime <= nowTs) continue;

            if (booking.startTime <= nowTs) {
                if (!hasActive || booking.startTime < activeStart) {
                    activeStart = booking.startTime;
                    activeId = booking.tokenId;
                    hasActive = true;
                }
            } else if (!hasUpcoming || booking.startTime < upcomingStart) {
                upcomingStart = booking.startTime;
                upcomingId = booking.tokenId;
                hasUpcoming = true;
            }
        }

        if (hasActive) return activeId;
        if (hasUpcoming) return upcomingId;
        return 0;
    }

    function bookings(uint256 tokenId) external view returns (Booking memory) {
        return _bookings[tokenId];
    }

    function isActive(uint256 tokenId) external view returns (bool) {
        Booking memory booking = _bookings[tokenId];
        if (booking.expiresAt == 0) revert NotFound();

        address owner = _ownerOf(tokenId);
        if (owner == address(0)) revert NotFound();

        return
            booking.startsAt <= block.timestamp &&
            booking.expiresAt > block.timestamp;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
