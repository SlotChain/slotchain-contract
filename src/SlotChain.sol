// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// OpenZeppelin upgradeable imports (v5.4+)
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    uint256 private _nextTokenId;
    IERC20 public baseToken;
    uint256 public feeInPPM;
    uint256 immutable PPM = 1_000_000;
    address public platformWallet;

    mapping(address => Creator) public creatorsProfiles;
    mapping(uint256 => Booking) public bookings;

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

    error InvalidAddress();
    error ZeroAddress();
    error ZeroValue();
    error InvalidURI();
    error AlreadyRegistered();
    error NotRegistered();
    error CreatorNotFound();
    error InvalidTime();
    error InvalidRequest();
    error InvalidValue();
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
        require(initialOwner != address(0), ZeroAddress());
        require(_usdt != address(0), ZeroAddress());
        require(wallet != address(0), ZeroAddress());

        __ERC721_init("SlotChain", "SLOT");
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
        require(_hourlyRate > 0, ZeroValue());
        require(bytes(_profileURI).length > 0, InvalidURI());
        require(!creatorsProfiles[msg.sender].exists, AlreadyRegistered());

        creatorsProfiles[msg.sender] = Creator({
            creator: msg.sender,
            hourlyRate: _hourlyRate,
            profileURI: _profileURI,
            exists: true
        });

        emit CreatorRegistered(msg.sender, _hourlyRate, _profileURI);
    }

    function updateProfile(
        uint256 _hourlyRate,
        string calldata _profileURI
    ) external {
        Creator storage c = creatorsProfiles[msg.sender];
        require(c.exists, NotRegistered());
        require(_hourlyRate > 0, ZeroValue());
        require(bytes(_profileURI).length > 0, InvalidURI());

        string memory oldURI = c.profileURI;
        c.hourlyRate = _hourlyRate;
        c.profileURI = _profileURI;

        emit ProfileUpdated(msg.sender, oldURI, _profileURI, _hourlyRate);
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
        Creator memory c = creatorsProfiles[creator];
        require(c.exists, CreatorNotFound());
        require(slotEnd > slotStart, InvalidTime());
        require(slotEnd > block.timestamp, InvalidTime());
        require(msg.sender != c.creator, InvalidRequest());

        uint256 fee = (c.hourlyRate * feeInPPM) / PPM;
        baseToken.safeTransferFrom(msg.sender, address(this), fee);

        uint256 creatorShare = c.hourlyRate - fee;
        baseToken.safeTransferFrom(msg.sender, creator, creatorShare);

        // Mint NFT as booking receipt
        uint256 tokenId = _nextTokenId++;
        // _safeMint(msg.sender, tokenId);

        bookings[tokenId] = Booking({
            creator: creator,
            startsAt: slotStart,
            expiresAt: slotEnd,
            amount: c.hourlyRate
        });

        emit SlotBooked(
            msg.sender,
            creator,
            tokenId,
            slotStart,
            slotEnd,
            c.hourlyRate
        );
        return tokenId;
    }

    ///@notice must be sent in PPM eg: 1% = 1000
    function updatePlatFormFee(uint256 newFee) external onlyOwner {
        require(newFee > 0, ZeroValue());
        require(newFee != feeInPPM, InvalidFee());
        feeInPPM = newFee;
    }

    function updatePlatformWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), ZeroAddress());
        require(_newWallet != platformWallet, InvalidAddress());
        platformWallet = _newWallet;
    }

    /// @notice Check if a booking is still active
    function isActive(uint256 tokenId) public view returns (bool) {
        require(balanceOf(msg.sender) > 0, NotFound());
        return block.timestamp < bookings[tokenId].expiresAt;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
