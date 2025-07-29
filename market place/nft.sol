// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFTMarketplace
 * @dev A decentralized marketplace for buying and selling NFTs
 */
contract NFTMarketplace is ReentrancyGuard, Ownable {
    
    // Marketplace fee percentage (2.5%)
    uint256 public marketplaceFee = 250; // 250 basis points = 2.5%
    uint256 private constant BASIS_POINTS = 10000;
    
    // Listing counter for unique listing IDs
    uint256 private listingCounter = 0;
    
    // Struct to represent an NFT listing
    struct Listing {
        uint256 listingId;
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 price;
        bool active;
    }
    
    // Mapping from listing ID to Listing struct
    mapping(uint256 => Listing) public listings;
    
    // Mapping to track listings by seller
    mapping(address => uint256[]) public sellerListings;
    
    // Events
    event ItemListed(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );
    
    event ItemSold(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );
    
    event ListingCanceled(
        uint256 indexed listingId,
        address indexed seller
    );
    
    event PriceUpdated(
        uint256 indexed listingId,
        uint256 oldPrice,
        uint256 newPrice
    );
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev List an NFT for sale
     * @param _nftContract Address of the NFT contract
     * @param _tokenId Token ID of the NFT
     * @param _price Price in wei
     */
    function listItem(
        address _nftContract,
        uint256 _tokenId,
        uint256 _price
    ) external nonReentrant {
        require(_price > 0, "Price must be greater than zero");
        
        IERC721 nft = IERC721(_nftContract);
        require(nft.ownerOf(_tokenId) == msg.sender, "You don't own this NFT");
        require(
            nft.isApprovedForAll(msg.sender, address(this)) || 
            nft.getApproved(_tokenId) == address(this),
            "Marketplace not approved to transfer NFT"
        );
        
        listingCounter++;
        
        listings[listingCounter] = Listing({
            listingId: listingCounter,
            nftContract: _nftContract,
            tokenId: _tokenId,
            seller: msg.sender,
            price: _price,
            active: true
        });
        
        sellerListings[msg.sender].push(listingCounter);
        
        emit ItemListed(listingCounter, _nftContract, _tokenId, msg.sender, _price);
    }
    
    /**
     * @dev Buy an NFT from the marketplace
     * @param _listingId ID of the listing to purchase
     */
    function buyItem(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.active, "Listing is not active");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Cannot buy your own NFT");
        
        IERC721 nft = IERC721(listing.nftContract);
        require(nft.ownerOf(listing.tokenId) == listing.seller, "Seller no longer owns NFT");
        
        // Mark listing as inactive
        listing.active = false;
        
        // Calculate fees
        uint256 fee = (listing.price * marketplaceFee) / BASIS_POINTS;
        uint256 sellerProceeds = listing.price - fee;
        
        // Transfer NFT to buyer
        nft.safeTransferFrom(listing.seller, msg.sender, listing.tokenId);
        
        // Transfer payment to seller
        (bool success, ) = payable(listing.seller).call{value: sellerProceeds}("");
        require(success, "Transfer to seller failed");
        
        // Refund excess payment
        if (msg.value > listing.price) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - listing.price}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit ItemSold(
            _listingId,
            listing.nftContract,
            listing.tokenId,
            listing.seller,
            msg.sender,
            listing.price
        );
    }
    
    /**
     * @dev Cancel a listing
     * @param _listingId ID of the listing to cancel
     */
    function cancelListing(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.seller == msg.sender, "Only seller can cancel listing");
        require(listing.active, "Listing is not active");
        
        listing.active = false;
        
        emit ListingCanceled(_listingId, msg.sender);
    }
    
    /**
     * @dev Update the price of a listing
     * @param _listingId ID of the listing to update
     * @param _newPrice New price in wei
     */
    function updatePrice(uint256 _listingId, uint256 _newPrice) external {
        Listing storage listing = listings[_listingId];
        
        require(listing.seller == msg.sender, "Only seller can update price");
        require(listing.active, "Listing is not active");
        require(_newPrice > 0, "Price must be greater than zero");
        
        uint256 oldPrice = listing.price;
        listing.price = _newPrice;
        
        emit PriceUpdated(_listingId, oldPrice, _newPrice);
    }
    
    /**
     * @dev Get all active listings (view function)
     * @return activeListings Array of active listing IDs
     */
    function getActiveListings() external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        
        // Count active listings
        for (uint256 i = 1; i <= listingCounter; i++) {
            if (listings[i].active) {
                activeCount++;
            }
        }
        
        // Create array of active listing IDs
        uint256[] memory activeListings = new uint256[](activeCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 1; i <= listingCounter; i++) {
            if (listings[i].active) {
                activeListings[currentIndex] = i;
                currentIndex++;
            }
        }
        
        return activeListings;
    }
    
    /**
     * @dev Get listings by seller
     * @param _seller Address of the seller
     * @return Array of listing IDs
     */
    function getListingsBySeller(address _seller) external view returns (uint256[] memory) {
        return sellerListings[_seller];
    }
    
    /**
     * @dev Withdraw marketplace fees (only owner)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    /**
     * @dev Update marketplace fee (only owner)
     * @param _newFee New fee in basis points (max 1000 = 10%)
     */
    function updateMarketplaceFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Fee cannot exceed 10%");
        marketplaceFee = _newFee;
    }
    
    /**
     * @dev Get total number of listings created
     */
    function getTotalListings() external view returns (uint256) {
        return listingCounter;
    }
}
