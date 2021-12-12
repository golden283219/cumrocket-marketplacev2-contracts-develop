pragma solidity ^0.8.0;

import './interfaces/IPlatformMaster.sol';
import './ModelCollection.sol';

contract Master is IPlatformMaster {

    event NewCollectionContract(address indexed contractAddress, address indexed walletAddress, string modelName);
    event ReferralPay(address indexed contractAddress, address indexed from, address indexed to, uint256 amount, address token);
    event TransferNft(address indexed contractAddress, address indexed from, address indexed to, uint256 nftId, uint256 tokenId);
    event AddNft(address indexed contractAddress, uint256 nftId, string uri, uint256 mintCap, address token, uint256 tokenAmount, string description);
    event PurchaseNft(address indexed contractAddress, address creator, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string modelName);
    event BuyNft(address indexed contractAddress, address buyer, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string modelName);
    event UpdateNftPrice(address indexed contractAddress, address owner, uint256 nftId, uint256 tokenId, uint256 price);
    event BurnNft(address indexed contractAddress, address owner, uint256 nftId, uint256 tokenId);

    // The owner of the contract
    address private masterOwner;

    // Store a list of model collections: modelsAddress => contractAddress
    mapping(address => address) public models;

    // Store a list of admins who can verify models
    mapping(address => bool) public admins;

    // Array of verified models (those who can make their own collection)
    mapping(address => bool) public verifiedModels;

    // Mapping of blacklisted models
    mapping(address => bool) private blackListedModels;

    // Mapping of child contracts
    mapping(address => bool) private childContracts;

    // The address of the fee-aggregator (the address that NFT buying fees are sent to)
    address private feeAggregator;

    uint256 public totalFee = 15;

    uint256 public platformFee = 10;

    uint256 public referrerFee = 5;

    uint256 public feeAggregatorFee = 5;

    uint256 public royaltyFee = 5;

    // How long the referral duration lasts for
    uint256 public referralDuration = 365 days;

    // A list of all BEP20 tokens currently accepted as a payment method for NFTs by the platform
    address[] public paymentTokens;

    // The address of the already deployed model contract to use as a base for spawning clones (see EIP11667)
    address private modelContractBase;

    // The address of the farming contract
    address private platform;

    address private cummies;

    modifier onlyOwner() {
        require(msg.sender == masterOwner, 'Error: You are not authorised to execute this function');
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], 'Error: You are not authorised to execute this function');
        _;
    }

    modifier onlyChildContract() {
        require(childContracts[msg.sender]);
        _;
    }

    constructor(address _modelContractBase, address _cummies) {
        masterOwner = msg.sender;
        admins[msg.sender] = true;
        paymentTokens.push(_cummies);
        modelContractBase = _modelContractBase;
        cummies = _cummies;
    }

    /**s
     * @notice Add a new admin to verify models
     *
     * @param newAdminAddress The new admin address
     * @return A boolean indicating success
     */
    function addAdmin(address newAdminAddress) external onlyOwner returns (bool) {
        require(!admins[newAdminAddress], 'addAdmin: Address is already an admin');
        admins[newAdminAddress] = true;
        return true;
    }

    /**
     * @notice Remove an admin
     *
     * @param newAdminAddress The new admin address
     * @return A boolean indicating success
     */
    function removeAdmin(address newAdminAddress) external onlyOwner returns (bool) {
        require(admins[newAdminAddress], 'removeAdmin: Address is not an admin');
        admins[newAdminAddress] = false;
        return true;
    }

    /**
     * @notice Add a token to be accepted as payment by models for NFTs
     *
     * @param tokenAddress The address of a BEP20 token
     * @return A boolean indicating success
     */
    function addPaymentToken(address tokenAddress) external onlyOwner returns (bool) {
        // Quick dirty BEP20 check should revert if this is not a valid BEP20 token (could be spoofed but mainly to reduce human error)
        IBEP20(tokenAddress).totalSupply();
        paymentTokens.push(tokenAddress);
        return true;
    }

    /**
     * @notice Remove a token to be accepted as payment by models for NFTs
     * NFTs minted before the token was removed will still be able to accept the token
     *
     * @param tokenAddress The address of a BEP20 token
     * @return A boolean indicating the successful removal of the token
     */
    function removePaymentToken(address tokenAddress) external onlyOwner returns (bool) {
        uint256 index = 0;
        for(uint256 i = 0; i < paymentTokens.length; ++i) {
            if(address(paymentTokens[i]) == tokenAddress) {
                index = i;
                break;
            }
        }
        delete paymentTokens[index];
        return false;
    }

    /**
     * @notice Returns a list of all of the currently accepted BEP20 token addresses for NFT buying
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return A list of BEP20 token addresses
     */
    function getPaymentTokens() override external view returns (address[] memory) {
        return paymentTokens;
    }

    /**
     * @notice Blacklist a model; this stops them from minting any new NFTs and halts their NFTs
     * from being sold
     *
     * @param modelAddress the address of the model's wallet
     * @return A boolean indicating success
     */
    function blacklist(address modelAddress) external onlyAdmin returns (bool) {
        require(!blackListedModels[modelAddress], 'blacklist: Model is already blacklisted');
        blackListedModels[modelAddress] = true;
        return true;
    }

    /**
     * @notice Remove a model from the blacklist; this reinstates their minting and selling permissions
     *
     * @param modelAddress The address of the model's wallet
     * @return A boolean indicating success
     */
    function unBlacklist(address modelAddress) external onlyAdmin returns (bool) {
        require(blackListedModels[modelAddress], 'unBlacklist: Model is not blacklisted');
        blackListedModels[modelAddress] = false;
        return true;
    }

    /**
     * @notice Remove a model from the blacklist; this reinstates their minting and selling permissions
     *
     * @param modelAddress The address of the model's wallet
     */
    function modelIsBlacklisted(address modelAddress) override external view returns (bool) {
        return blackListedModels[modelAddress];
    }

    /**
     * @notice Sets the cut that the total takes from NFT sales in %
     *
     * @param _totalFee The platform cut in %
     * @return A boolean indicating success
     */
    function setTotalFee(uint256 _totalFee) external onlyOwner returns (bool) {
        require(_totalFee <= 15, 'total fee cannot be larger than 15%');
        require(_totalFee >= referrerFee && _totalFee >= feeAggregatorFee, 'setPlatformFee: platform fee cannot be smaller than the referrer and fee aggregator fee');
        totalFee = _totalFee;
        return true;
    }

    /**
     * @notice Sets the cut that the platform takes from NFT sales in %
     *
     * @param _platformFee The platform cut in %
     * @return A boolean indicating success
     */
    function setPlatformFee(uint256 _platformFee) external onlyOwner returns (bool) {
        require(_platformFee <= 15, 'setPlatformFee: platform fee cannot be larger than 15%');
        require(_platformFee >= referrerFee, 'setPlatformFee: platform fee cannot be smaller than the referrer fee');
        platformFee = _platformFee;
        return true;
    }

    /**
     * @notice Sets the cut that the feeAggregator takes from NFT sales in %
     *
     * @param _feeAggregatorFee The platform cut in %
     * @return A boolean indicating success
     */
    function setFeeAggregatorFee(uint256 _feeAggregatorFee) external onlyOwner returns (bool) {
        require(_feeAggregatorFee >= 5 && _feeAggregatorFee <= 10,  'feeAggregatorFee is between 5 and 10.');
        feeAggregatorFee = _feeAggregatorFee;
        return true;
    }

    /**
     * @notice Sets the cut that a royalty gets of a resales
     *
     * @param _royaltyFee The royalty cut in %
     * @return A boolean indicating success
     */
    function setRoyaltyFee(uint256 _royaltyFee) external onlyOwner returns (bool) {
        require(royaltyFee >= 5 && royaltyFee <= 10,  'setRoyaltyFee: royaltyFee is between 5 and 10.');
        royaltyFee = _royaltyFee;
        return true;
    }

    /**
     * @notice Sets the cut that a refferer gets of a referrees sales
     *
     * @param _referrerFee The referrer cut in %
     * @return A boolean indicating success
     */
    function setReferrerFee(uint256 _referrerFee) external onlyOwner returns (bool) {
        require(_referrerFee <= platformFee, 'setReferrerFee: referrer fee cannot be larger than the platform fee');
        referrerFee = _referrerFee;
        return true;
    }

    /**
     * @notice Sets the address of the platform wallet so we can send tax to kep rewards topped up
     *
     * @param _platform The address of the platform wallet
     * @return A boolean indicating success
     */
    function setPlatform(address _platform) external onlyOwner returns (bool) {
        require(platform != _platform, 'setFarmAddress: farm is already set to this address');
        platform = _platform;
        return true;
    }

    /**
     * @notice Returns the contract address of the farm
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The farm address
     */
    function getPlatform() override external view returns (address) {
        return platform;
    }

    /**
     * @notice Sets how long referrers wil recieve a cut of a referrees sales (in seconds)
     *
     * @param _referralDuration The duration in seconds
     * @return A boolean indicating success
     */
    function setReferralDuration(uint256 _referralDuration) external onlyOwner returns (bool) {
        referralDuration = _referralDuration;
        return true;
    }

    /**
     * @notice Returns the current set total fee
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The current set total fee
     */
    function getTotalFee() override external view returns (uint256) {
        return totalFee;
    }

    /**
    * @notice Returns the current set platform fee
    * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
    *
    * @return The current set total fee
    */
    function getPlatformFee() override external view returns (uint256) {
        return platformFee;
    }

    /**
    * @notice Returns the current set feeAggregator fee
    * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
    *
    * @return The current set total fee
    */
    function getFeeAggregatorFee() override external view returns (uint256) {
        return feeAggregatorFee;
    }

    /**
    * @notice Returns the current set referrer fee
    * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
    *
    * @return The current set total fee
    */
    function getReferrerFee() override external view returns (uint256) {
        return referrerFee;
    }

    /**
     * @notice Returns the current set royalty fee
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The current set royalty fee
     */
    function getRoyaltyFee() override external view returns (uint256) {
        return royaltyFee;
    }

    /**
     * @notice Returns the platform owner's address
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The address of the current platform owner
     */
    function getPlatformOwner() override external view returns (address) {
        return masterOwner;
    }

    /**
     * @notice Transfer ownership of the master contract
     *
     * @param _masterOwner The address of the new platform owner
     * @return A boolean indicating success
     */
    function transferOwnership(address _masterOwner) external onlyOwner returns (bool) {
        require(masterOwner != _masterOwner, 'transferOwnership: specified address is already owner');
        masterOwner = _masterOwner;
        return true;
    }

    /**
     * @notice Returns the current fee-splitter address
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The address of the current fee-splitter
     */
    function getFeeAggregator() override external view returns (address) {
        return feeAggregator;
    }

    /**
     * @notice Set the address of the fee-splitter
     *
     * @param _feeAggregator The address of the new fee-splitter (can be a wallet or a contract)
     * @return A boolean indicating success
     */
    function setFeeAggregator(address _feeAggregator) external onlyOwner returns (bool) {
        require(feeAggregator != _feeAggregator, 'setFeeAggregator: feeAggregator is already set to this address');
        feeAggregator = _feeAggregator;
        return true;
    }

    /**
     * @notice Verify a model from their wallet address; this allows them to spawn a modelCollection contract
     *
     * @param modelAddress The address of the verified model
     * @return A boolean indicating success
     */
    function verifyModel(address modelAddress) external onlyAdmin returns (bool) {
        require(!verifiedModels[modelAddress], 'verifyModel: model is already verified');
        verifiedModels[modelAddress] = true;
        return true;
    }

    /**
     * @notice Get the address of a model's ModelCollection contract from their wallet address
     *
     * @param modelAddress The address of the model
     * @return The address of the model's ModelCollection contract
     */
    function getModelContract(address modelAddress) external override view returns (address) {
        return models[modelAddress];
    }

    /**
     * @notice Spawn a new ModelCollection contract for the caller (only if they have been verified by an admin)
     *
     * @param modelName The name of the model
     * @param modelDesc The description of the model
     * @param modelGender The gender of the model
     * @return modelContractAddress The address of the newly spawned model's ModelCollection contract
     */
    function newCollectionContract(
        string memory modelName,
        string memory modelDesc,
        string memory modelGender,
        address referrer,
        string memory _salt
    ) external returns (address modelContractAddress) {

        require(verifiedModels[msg.sender], 'newCollectionContract: You are not authorized to create a collection');
        require(models[msg.sender] == address(0), 'newCollectionContract: You have already created a collection');


        // EIP1167 standard proxy

        bytes20 targetBytes = bytes20(modelContractBase);
        bytes32 salt = keccak256(abi.encodePacked(_salt, msg.sender));
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            modelContractAddress := create2(0, clone, 0x37, salt)
        }

        // make sure that the referrer is a model and isn't blacklisted

        if (models[referrer] == address(0) || blackListedModels[referrer] == true) {
            referrer = address(0);
        }

        ModelCollection(modelContractAddress).initialize(
            address(this),
            modelName,
            modelDesc,
            modelGender,
            msg.sender,
            referrer,
            referrer == address(0) ? 0 : referrerFee,
            referralDuration,
            cummies
        );

        models[msg.sender] = modelContractAddress;
        childContracts[modelContractAddress] = true;

        emit NewCollectionContract(modelContractAddress, msg.sender, modelName);

        return modelContractAddress;
    }

    // CHILD CONTRACT EVENT LOGGING

    function logReferralPay(address from, address to, uint256 amount, address token) external override onlyChildContract {
        emit ReferralPay(msg.sender, from, to, amount, token);
    }

    function logTransferNft(address from, address to, uint256 nftId, uint256 tokenId) external override onlyChildContract {
        emit TransferNft(msg.sender, from, to, nftId, tokenId);
    }

    function logAddNft(uint256 nftId, string memory uri, uint256 mintCap, address token, uint256 tokenAmount, string memory description) external override onlyChildContract {
        emit AddNft(msg.sender, nftId, uri, mintCap, token, tokenAmount, description);
    }

    function logPurchaseNft(address creator, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string memory modelName) external override onlyChildContract {
        emit PurchaseNft(msg.sender, creator, nftId, tokenId, mintCap, minted, modelName);
    }

    function logBuyNft(address buyer, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string memory modelName) external override onlyChildContract {
        emit BuyNft(msg.sender, buyer, nftId, tokenId, mintCap, minted, modelName);
    }

    function logUpdateNftPrice(address owner, uint256 nftId, uint256 tokenId, uint256 price) external override onlyChildContract {
        emit UpdateNftPrice(msg.sender, owner, nftId, tokenId, price);
    }

    function logBurnNft(address owner, uint256 nftId, uint256 tokenId) external override onlyChildContract {
        emit BurnNft(msg.sender, owner, nftId, tokenId);
    }

}
