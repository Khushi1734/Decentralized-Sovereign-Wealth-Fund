// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFT Marketplace
 * @dev A decentralized marketplace for trading NFTs with royalty support
 */
contract NFTMarketplace is ReentrancyGuard, Ownable {
    
    // Struct to represent a marketplace listing
    struct Listing {
        uint256 tokenId;
        address nftContract;
        address seller;
        uint256 price;
        bool active;
        uint256 createdAt;
    }
    
    // Mapping from listing ID to Listing struct
    mapping(uint256 => Listing) public listings;
    
    // Mapping to track royalties (nftContract => royaltyPercentage)
    mapping(address => uint256) public royalties;
    
    // Mapping to track original creators (nftContract => tokenId => creator)
    mapping(address => mapping(uint256 => address)) public creators;
    
    uint256 public listingCounter;
    uint256 public platformFee = 250; // 2.5% in basis points (10000 = 100%)
    address public feeRecipient;
    
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
    
    event ListingCancelled(
        uint256 indexed listingId,
        address indexed seller
    );
    
    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }
    
    /**
     * @dev List an NFT for sale on the marketplace
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
        require(nft.ownerOf(_tokenId) == msg.sender, "Not the owner of this NFT");
        require(
            nft.getApproved(_tokenId) == address(this) || 
            nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved to transfer NFT"
        );
        
        uint256 listingId = listingCounter++;
        
        listings[listingId] = Listing({
            tokenId: _tokenId,
            nftContract: _nftContract,
            seller: msg.sender,
            price: _price,
            active: true,
            createdAt: block.timestamp
        });
        
        // Set creator if not already set
        if (creators[_nftContract][_tokenId] == address(0)) {
            creators[_nftContract][_tokenId] = msg.sender;
        }
        
        emit ItemListed(listingId, _nftContract, _tokenId, msg.sender, _price);
    }
    
    /**
     * @dev Buy an NFT from the marketplace
     * @param _listingId ID of the listing to purchase
     */
    function buyItem(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        require(listing.active, "Listing is not active");
        require(msg.value >= listing.price, "Insufficient payment");
        
        IERC721 nft = IERC721(listing.nftContract);
        require(nft.ownerOf(listing.tokenId) == listing.seller, "Seller no longer owns the NFT");
        
        // Mark listing as inactive
        listing.active = false;
        
        // Calculate fees
        uint256 totalPrice = listing.price;
        uint256 platformFeeAmount = (totalPrice * platformFee) / 10000;
        uint256 royaltyAmount = 0;
        
        // Calculate royalty if applicable
        address creator = creators[listing.nftContract][listing.tokenId];
        if (creator != address(0) && creator != listing.seller) {
            uint256 royaltyRate = royalties[listing.nftContract];
            if (royaltyRate > 0) {
                royaltyAmount = (totalPrice * royaltyRate) / 10000;
            }
        }
        
        uint256 sellerAmount = totalPrice - platformFeeAmount - royaltyAmount;
        
        // Transfer NFT to buyer
        nft.safeTransferFrom(listing.seller, msg.sender, listing.tokenId);
        
        // Distribute payments
        if (platformFeeAmount > 0) {
            payable(feeRecipient).transfer(platformFeeAmount);
        }
        
        if (royaltyAmount > 0 && creator != address(0)) {
            payable(creator).transfer(royaltyAmount);
        }
        
        payable(listing.seller).transfer(sellerAmount);
        
        // Refund excess payment
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }
        
        emit ItemSold(
            _listingId,
            listing.nftContract,
            listing.tokenId,
            listing.seller,
            msg.sender,
            totalPrice
        );
    }
    
    /**
     * @dev Cancel a listing
     * @param _listingId ID of the listing to cancel
     */
    function cancelListing(uint256 _listingId) external {
        Listing storage listing = listings[_listingId];
        require(listing.seller == msg.sender || msg.sender == owner(), "Not authorized");
        require(listing.active, "Listing is not active");
        
        listing.active = false;
        
        emit ListingCancelled(_listingId, listing.seller);
    }
    
    /**
     * @dev Set royalty percentage for an NFT contract (only contract owner can call)
     * @param _nftContract Address of the NFT contract
     * @param _royaltyPercentage Royalty percentage in basis points (500 = 5%)
     */
    function setRoyalty(address _nftContract, uint256 _royaltyPercentage) external {
        require(_royaltyPercentage <= 1000, "Royalty cannot exceed 10%"); // Max 10%
        
        // Only the owner of the NFT contract or marketplace owner can set royalties
        require(
            msg.sender == owner() || 
            (Ownable(_nftContract).owner() == msg.sender),
            "Not authorized to set royalty"
        );
        
        royalties[_nftContract] = _royaltyPercentage;
    }
    
    /**
     * @dev Get listing details
     * @param _listingId ID of the listing
     */
    function getListing(uint256 _listingId) external view returns (Listing memory) {
        return listings[_listingId];
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFee New fee in basis points
     */
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Fee cannot exceed 10%");
        platformFee = _newFee;
    }
    
    /**
     * @dev Update fee recipient (only owner)
     * @param _newRecipient New fee recipient address
     */
    function updateFeeRecipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid address");
        feeRecipient = _newRecipient;
    }
    
    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
