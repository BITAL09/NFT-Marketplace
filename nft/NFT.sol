// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title NFT Marketplace
 * @dev A comprehensive decentralized marketplace for trading NFTs
 * @author Your Name
 */
contract NFTMarketplace is ReentrancyGuard, Ownable, IERC721Receiver {
    using Counters for Counters.Counter;
    
    // State variables
    Counters.Counter private _listingIds;
    uint256 public platformFee = 250; // 2.5% (250/10000)
    uint256 public constant MAX_FEE = 1000; // 10% maximum fee
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public totalVolume; // Total trading volume
    uint256 public totalSales; // Total number of sales
    
    // Structs
    struct Listing {
        uint256 listingId;
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 price;
        bool active;
        uint256 listedAt;
        string category; // e.g., "Art", "Gaming", "Music"
    }
    
    struct UserStats {
        uint256 totalSold;
        uint256 totalBought;
        uint256 volumeSold;
        uint256 volumeBought;
    }
    
    // Mappings
    mapping(uint256 => Listing) public listings;
    mapping(address => mapping(uint256 => uint256)) public tokenToListingId;
    mapping(address => UserStats) public userStats;
    mapping(string => uint256) public categoryCount;
    
    // Events
    event NFTListed(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price,
        string category,
        uint256 timestamp
    );
    
    event NFTSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        uint256 platformFeeAmount,
        uint256 timestamp
    );
    
    event ListingCancelled(
        uint256 indexed listingId,
        address indexed seller,
        uint256 timestamp
    );
    
    event PriceUpdated(
        uint256 indexed listingId,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );
    
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    
    event FeesWithdrawn(address indexed owner, uint256 amount);
    
    // Modifiers
    modifier validListing(uint256 listingId) {
        require(listingId > 0 && listingId <= _listingIds.current(), "Invalid listing ID");
        require(listings[listingId].active, "Listing not active");
        _;
    }
    
    modifier onlySeller(uint256 listingId) {
        require(listings[listingId].seller == msg.sender, "Only seller can perform this action");
        _;
    }
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Function 1: List an NFT for sale with category
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param price Listing price in wei
     * @param category Category of the NFT (e.g., "Art", "Gaming", "Music")
     */
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        string memory category
    ) external nonReentrant {
        require(nftContract != address(0), "Invalid NFT contract address");
        require(price > 0, "Price must be greater than zero");
        require(bytes(category).length > 0, "Category cannot be empty");
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "You don't own this NFT"
        );
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "Marketplace not approved to transfer NFT"
        );
        require(
            tokenToListingId[nftContract][tokenId] == 0,
            "NFT already listed"
        );
        
        _listingIds.increment();
        uint256 listingId = _listingIds.current();
        
        listings[listingId] = Listing({
            listingId: listingId,
            nftContract: nftContract,
            tokenId: tokenId,
            seller: msg.sender,
            price: price,
            active: true,
            listedAt: block.timestamp,
            category: category
        });
        
        tokenToListingId[nftContract][tokenId] = listingId;
        categoryCount[category]++;
        
        emit NFTListed(listingId, nftContract, tokenId, msg.sender, price, category, block.timestamp);
    }
    
    /**
     * @dev Function 2: Buy an NFT from the marketplace
     * @param listingId ID of the listing to purchase
     */
    function buyNFT(uint256 listingId) external payable nonReentrant validListing(listingId) {
        Listing storage listing = listings[listingId];
        require(msg.value == listing.price, "Incorrect payment amount");
        require(msg.sender != listing.seller, "Cannot buy your own NFT");
        
        // Calculate fees
        uint256 platformFeeAmount = (listing.price * platformFee) / FEE_DENOMINATOR;
        uint256 sellerAmount = listing.price - platformFeeAmount;
        
        // Update statistics
        userStats[listing.seller].totalSold++;
        userStats[listing.seller].volumeSold += listing.price;
        userStats[msg.sender].totalBought++;
        userStats[msg.sender].volumeBought += listing.price;
        totalVolume += listing.price;
        totalSales++;
        categoryCount[listing.category]--;
        
        // Update listing status
        listing.active = false;
        tokenToListingId[listing.nftContract][listing.tokenId] = 0;
        
        // Transfer NFT to buyer
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );
        
        // Transfer payment to seller
        if (sellerAmount > 0) {
            payable(listing.seller).transfer(sellerAmount);
        }
        // Platform fee remains in contract
        
        emit NFTSold(listingId, msg.sender, listing.seller, listing.price, platformFeeAmount, block.timestamp);
    }
    
    /**
     * @dev Function 3: Cancel an active listing
     * @param listingId ID of the listing to cancel
     */
    function cancelListing(uint256 listingId) 
        external 
        nonReentrant 
        validListing(listingId) 
        onlySeller(listingId) 
    {
        Listing storage listing = listings[listingId];
        
        listing.active = false;
        tokenToListingId[listing.nftContract][listing.tokenId] = 0;
        categoryCount[listing.category]--;
        
        emit ListingCancelled(listingId, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Function 4: Update the price of an active listing
     * @param listingId ID of the listing to update
     * @param newPrice New price in wei
     */
    function updatePrice(uint256 listingId, uint256 newPrice) 
        external 
        nonReentrant 
        validListing(listingId) 
        onlySeller(listingId) 
    {
        require(newPrice > 0, "Price must be greater than zero");
        
        Listing storage listing = listings[listingId];
        uint256 oldPrice = listing.price;
        listing.price = newPrice;
        
        emit PriceUpdated(listingId, oldPrice, newPrice, block.timestamp);
    }
    
    /**
     * @dev Function 5: Get listing details
     * @param listingId ID of the listing
     * @return Listing struct with all details
     */
    function getListing(uint256 listingId) external view returns (Listing memory) {
        require(listingId > 0 && listingId <= _listingIds.current(), "Invalid listing ID");
        return listings[listingId];
    }
    
    /**
     * @dev Function 6: Get marketplace statistics
     * @return totalListings Total number of listings created
     * @return activeListings Current active listings count
     * @return totalTradingVolume Total volume traded
     * @return totalSalesCount Total number of completed sales
     */
    function getMarketplaceStats() external view returns (
        uint256 totalListings,
        uint256 activeListings,
        uint256 totalTradingVolume,
        uint256 totalSalesCount
    ) {
        totalListings = _listingIds.current();
        
        // Count active listings
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= totalListings; i++) {
            if (listings[i].active) {
                activeCount++;
            }
        }
        
        return (totalListings, activeCount, totalVolume, totalSales);
    }
    
    /**
     * @dev Function 7: Get user statistics
     * @param user Address of the user
     * @return stats UserStats struct containing user's trading statistics
     */
    function getUserStats(address user) external view returns (UserStats memory stats) {
        return userStats[user];
    }
    
    /**
     * @dev Function 8: Withdraw accumulated platform fees (owner only)
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        payable(owner()).transfer(balance);
        emit FeesWithdrawn(owner(), balance);
    }
    
    // Additional owner functions (bonus - these don't count toward the 8 main functions)
    
    /**
     * @dev Update platform fee (owner only)
     * @param newFee New platform fee in basis points (e.g., 250 = 2.5%)
     */
    function updatePlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, "Fee exceeds maximum allowed");
        uint256 oldFee = platformFee;
        platformFee = newFee;
        emit PlatformFeeUpdated(oldFee, newFee);
    }
    
    // Required by IERC721Receiver
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
    
    // Emergency function to recover stuck NFTs (if any)
    function emergencyRecoverNFT(
        address nftContract,
        uint256 tokenId,
        address to
    ) external onlyOwner {
        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
    }
}
