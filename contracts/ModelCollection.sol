pragma solidity ^0.8.0;

import "./interfaces/IBEP20.sol";
import './interfaces/IPlatformMaster.sol';
import "./utils/Counters.sol";
import "./token/ERC721/ERC721.sol";

contract ModelCollection is ERC721 {

    using Counters for Counters.Counter;

    /**
     * uri:                  Points to relevant json not unique per person, NFT is unique but metadata and image are not
     * mintable:             Ensures the nft is mintable before allowing it to be minted
     * purchaseTokenAddress: The address of the BEP20 token used to purchase this NFT
     * purchaseTokenAmount:  The amount of the specified token required to purchase this NFT
     * mintCap:              How many Nfts can be minted for this particular NFT.  0 = infinite
     * numberMinted:         How many of this NFT have been minted so far.  Cannot exceed mintCap
     * admin:                The model's address that owns the NFT
     */
    struct Nft {
        string uri;
        bool mintable;
        address purchaseTokenAddress;
        uint256 purchaseTokenAmount;
        uint256 mintCap;
        uint256 numberMinted;
        address admin;
        address originalCreator;
        string description;
    }

    // The master contract
    IPlatformMaster private master;

    // The address of the contract deployer (master contract address)
    address private deployer;

    // If the model was referred by another model, we share the platform fee for six months
    address private referrer;

    // The percentage cut of sales that go to the referrer
    uint256 private referrerFee;

    // How long the referral duration lasts for
    uint256 private referralDuration;

    // What time the contract was initialized at (used for referrals)
    uint256 private initializedAt;

    // Internal counter for tracking the amount of NFTs minted
    Counters.Counter private tokenIds;

    // A mapping to join the tokenID to the underlying nftId
    mapping (uint256 => uint256) private modelNftIds;

    // A mapping to join the tokenID to the underlying tokenURI
    mapping (uint256 => string) private tokenURIs;

    // Model info
    address public modelAddress;
    string public modelName;
    string public modelDescription;
    string public modelGender;

    address private cummies;

    // Array of model NFTs
    Nft[] public nfts;

    Nft[] private tempNfts;

    bool initializerLocked;

    modifier onlyModel {
        require(msg.sender == modelAddress);
        _;
    }

    modifier onlyDeployer {
        require(msg.sender == deployer);
        _;
    }

    modifier onlyPlatformOwner {
        require(msg.sender == master.getPlatformOwner());
        _;
    }

    modifier lockInitializer {
        require(!initializerLocked);
        _;
        initializerLocked = true;
    }

    modifier checkBlacklist {
        require(!master.modelIsBlacklisted(modelAddress));
        _;
    }

    constructor() ERC721("", "CRNFT") { }

    /**
     * @notice Initialisation method to be called after this contract has been spawned by the master
     * to initialise data
     *
     * @param _masterAddress The address of the master contract
     * @param _modelName The name of the model that this contract belongs to
     * @param _modelDescription The description of the model that this contract belongs to
     * @param _modelGender The gender of the model that this contract belongs to
     * @param _modelAddress The wallet address of the model that this contract belongs to
     */
    function initialize (
        address _masterAddress,
        string memory _modelName,
        string memory _modelDescription,
        string memory _modelGender,
        address _modelAddress,
        address _referrer,
        uint256 _referrerFee,
        uint256 _referralDuration,
        address _cummies
    ) external lockInitializer {

        master = IPlatformMaster(_masterAddress);
        modelName = _modelName;
        modelDescription = _modelDescription;
        modelGender = _modelGender;
        modelAddress = _modelAddress;
        deployer = msg.sender;

        referrer = _referrer;
        referrerFee = _referrerFee;
        referralDuration = _referralDuration;
        initializedAt = block.timestamp;
        cummies = _cummies;
    }

    function name() public view virtual override returns (string memory) {
        return modelName;
    }

    /**
     * @notice Create an NFT ready for minting/purchase
     *
     * @param _uri The URI of the NFT data
     * @param _purchaseTokenAddress The address of the BEP20 token to be accepted as payment for this NFT
     * @param _purchaseTokenAmount The amount of BEP20 tokens required to purchase this NFT
     * @param _mintCap The amount of times this NFT can be minted
     */
    function addNft(
        string memory _uri,
        address _purchaseTokenAddress,
        uint256 _purchaseTokenAmount,
        uint256 _mintCap,
        string memory _description
    ) onlyModel checkBlacklist external returns (uint256) {

        // Verify that the purchase token address is in the master's list of allowed tokens

        bool tokenAllowed = false;
        address[] memory allowedTokens = master.getPaymentTokens();

        for (uint256 i = 0; i < allowedTokens.length; ++i) {
            if(allowedTokens[i] == _purchaseTokenAddress) {
                tokenAllowed = true;
                break;
            }
        }

        require(tokenAllowed, "addNft: Purchase token not allowed by master");

        nfts.push(
            Nft({
                uri: _uri,
                mintable: true,
                purchaseTokenAddress: _purchaseTokenAddress,
                purchaseTokenAmount: _purchaseTokenAmount,
                mintCap: _mintCap,
                numberMinted: 0,
                admin: modelAddress,
                originalCreator: address(0),
                description: _description
            })
        );

        master.logAddNft(nfts.length - 1, _uri, _mintCap, _purchaseTokenAddress, _purchaseTokenAmount, _description);

        return nfts.length - 1;

    }

    /**
     * @notice Get the underlying ID of the NFT the token was minted from
     *
     * @param tokenID The token id
     */
    function tokenNftId(uint256 tokenID) external view returns (uint256)  {
        require(_exists(tokenID), "tokenNftId: Token has not been minted yet");
        return modelNftIds[tokenID];
    }

    /**
     * @notice Purchase an NFT from this model
     *
     * @param nftId The id of the NFT to purchase/mint
     * @return The id of the purchased token
     */
    function purchaseNFT(uint256 nftId) checkBlacklist external returns (uint256) {

        require(nftId <= nfts.length - 1, "PurchaseNft: NFT Does not exist");

        Nft storage nft = nfts[nftId];

        require(nft.mintable, "PurchaseNft: NFT is not Mintable");

        makePayment(nft.admin, nft.purchaseTokenAmount, nft.purchaseTokenAddress);

        mintNFT(nft.uri, nftId);
        nft.numberMinted = nft.numberMinted + 1;

        if (nft.numberMinted == nft.mintCap) {
            nft.mintable = false;
        }

        nft.originalCreator = msg.sender;

        master.logPurchaseNft(msg.sender, nftId, tokenIds.current(), nft.mintCap, nft.numberMinted, modelName);

        return tokenIds.current();

    }

    /**
     * @notice Override the referrer address (used only if the referrer wallet has been compromised)
     *
     * @param _referrer The new address of the referrer
     */
    function overrideReferrer(address _referrer) external onlyPlatformOwner {
        referrer = _referrer;
    }

    /**
     * @notice Attempt to mint an NFT token from a the base NFT
     *
     * @param _tokenURI The uri of the base NFT
     * @param _nftId The id of the base NFT
     * @return The id of the newly created NFT
     */
    function mintNFT(string memory _tokenURI, uint256 _nftId) internal returns (uint256) {

        tokenIds.increment();
        uint256 newItemId = tokenIds.current();
        _safeMint(msg.sender, newItemId);
        setTokenURI(newItemId, _tokenURI);
        setTokenNftId(newItemId, _nftId); // Set nftId internally to NFT so it can determine which NFT the tokenID represents.
        return newItemId;

    }

    /**
     * @notice Associate a token ID with its base NFT ID
     *
     * @param tokenID The ID of the token
     * @param nftId The ID of the NFT
     */
    function setTokenNftId(uint256 tokenID, uint256 nftId) internal virtual {
        require(_exists(tokenID), "setTokenNftId:  nftId set of nonexistent token");
        modelNftIds[tokenID] = nftId;
    }

    /**
     * @notice Keep track of the uri of each each token
     *
     * @param tokenID The id of the token
     * @param uri The uri of the base NFT
     */
    function setTokenURI(uint256 tokenID, string memory uri) internal {
        tokenURIs[tokenID] = uri;
    }

    /**
     * @notice Distribute the tokens used to purchase an NFT between the platform and the seller
     *
     * @param to The address of the NFT owner
     * @param amount The amount of tokens to transfer
     * @param purchaseTokenAddress The address of the BEP20 token being used for purchase
     */
    function makePayment(address to, uint256 amount, address purchaseTokenAddress) internal {

        require(master.getPlatform() != address(0), "Platform is not set.");
        require(master.getFeeAggregator() != address(0), "FeeAggregator is not set.");

        IBEP20 purchaseToken = IBEP20(purchaseTokenAddress); // Set the purchase token for the NFT.

        uint256 purchaseTokenBalance =  purchaseToken.balanceOf(msg.sender);
        require(purchaseTokenBalance >= amount, 'PurchaseNft: Insufficient balance');

        uint256 totalFee = master.getTotalFee();
        uint256 platformFee = master.getPlatformFee();
        uint256 feeAggregatorFee = master.getFeeAggregatorFee();
        referrerFee = master.getReferrerFee();

        if (
            referrer != address(0)
            && block.timestamp - initializedAt < referralDuration
            && !master.modelIsBlacklisted(referrer)
        ) {
            feeAggregatorFee = 0;
            platformFee = totalFee - referrerFee;
        } else {
            referrerFee = 0;
            platformFee = totalFee - feeAggregatorFee;
        }

        if (purchaseTokenAddress == cummies) {  // tokenomics for cummies
            if (platformFee >= 5) {
                platformFee = platformFee - 5;
            } else {
                platformFee = 0;
            }
        }
        uint256 platformAmount = amount * platformFee / 100;
        uint256 referrerAmount = amount * referrerFee / 100;
        uint256 feeAggregatorAmount = amount * feeAggregatorFee / 100;
        uint256 restAmount = amount - platformAmount - referrerAmount - feeAggregatorAmount;

        if (referrerAmount > 0) {
            purchaseToken.transferFrom(msg.sender, referrer, referrerAmount);
            master.logReferralPay(msg.sender, referrer, referrerAmount, purchaseTokenAddress);
        }
        if (platformAmount > 0) {
            purchaseToken.transferFrom(msg.sender, master.getPlatform(), platformAmount);
        }
        if (feeAggregatorAmount > 0) {
            purchaseToken.transferFrom(msg.sender, master.getFeeAggregator(), feeAggregatorAmount);
        }
        if (restAmount > 0) {
            purchaseToken.transferFrom(msg.sender, to, restAmount);
        }
    }

    /**
     * @notice Get the uri of a token
     *
     * @param tokenID The id of the token
     */
    function tokenURI(uint256 tokenID) public view virtual override returns (string memory) {
        require(_exists(tokenID), "tokenURI: Token has not been minted yet");
        return tokenURIs[tokenID];
    }

    // Add logging to transfers
    function _transfer(address from, address to, uint256 tokenId) internal override {
        master.logTransferNft(from, to, modelNftIds[tokenId], tokenId);
        super._transfer(from, to, tokenId);
    }

    function removeItemFromArray(uint index) internal {
        if (index >= nfts.length) return;
        delete tempNfts;
        for (uint i = 0; i < nfts.length; i++) {
            if (i != index) {
                tempNfts.push(nfts[i]);
            }
        }
        delete nfts;
        for (uint i = 0; i < tempNfts.length; i++) {
            nfts.push(tempNfts[i]);
        }
        delete tempNfts;
    }

    function burnNFT(uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        super._burn(tokenId);
        uint256 nftId = modelNftIds[tokenId];
        delete modelNftIds[tokenId];
        delete tokenURIs[tokenId];
        removeItemFromArray(nftId);
        master.logBurnNft(owner, nftId, tokenId);
    }

    function updateNFTPrice(uint256 tokenId, uint256 amount) public {
        require(ownerOf(tokenId) == msg.sender, "You are not owner.");
        uint256 nftId = modelNftIds[tokenId];
        Nft storage nft = nfts[nftId];
        nft.purchaseTokenAmount = amount;
        master.logUpdateNftPrice(msg.sender, nftId, tokenId, nft.purchaseTokenAmount);
    }

    function buyNFT(uint256 tokenId) public {
        require(ownerOf(tokenId) != msg.sender, "You are already owner.");
        uint256 nftId = modelNftIds[tokenId];
        Nft storage nft = nfts[nftId];
        require(nft.mintable == true, "You can't buy this anymore.");
        IBEP20 purchaseToken = IBEP20(nft.purchaseTokenAddress);
        require(purchaseToken.balanceOf(msg.sender) >= nft.purchaseTokenAmount, 'buyNft: Insufficient balance');

        uint256 royaltyFee = master.getRoyaltyFee();
        uint256 feeAggregatorFee = master.getFeeAggregatorFee();
        uint256 platformFee = master.getTotalFee() - royaltyFee;
        if (nft.purchaseTokenAddress == cummies) {
            feeAggregatorFee = 0;
        }
        platformFee = platformFee - feeAggregatorFee;

        if (nft.purchaseTokenAddress == cummies) {
            if (platformFee >= 5) {
                platformFee = platformFee - 5;
            } else {
                platformFee = 0;
            }
        }
        uint256 royaltyAmount = nft.purchaseTokenAmount * royaltyFee / 100;
        uint256 platformAmount = nft.purchaseTokenAmount * platformFee / 100;
        uint256 feeAggregatorAmount = nft.purchaseTokenAmount * feeAggregatorFee / 100;
        uint256 restAmount = nft.purchaseTokenAmount - royaltyAmount - platformAmount - feeAggregatorAmount;

        if (royaltyAmount > 0) {
            purchaseToken.transferFrom(msg.sender, nft.originalCreator, royaltyAmount);
        }
        if (platformAmount > 0) {
            purchaseToken.transferFrom(msg.sender, master.getPlatform(), platformAmount);
        }
        if (feeAggregatorAmount > 0) {
            purchaseToken.transferFrom(msg.sender, master.getFeeAggregator(), feeAggregatorAmount);
        }
        if (restAmount > 0) {
            purchaseToken.transferFrom(msg.sender, ownerOf(tokenId), restAmount);
        }
        _transfer(ownerOf(tokenId), msg.sender, tokenId);
        nft.numberMinted = nft.numberMinted + 1;
        if (nft.numberMinted == nft.mintCap) {
            nft.mintable = false;
        }
        master.logBuyNft(msg.sender, nftId, tokenId, nft.mintCap, nft.numberMinted, modelName);
    }

}
