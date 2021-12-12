pragma solidity ^0.8.0;

interface IPlatformMaster {

    function getTotalFee() external view returns (uint256);

    function getFeeAggregatorFee() external view returns (uint256);

    function getPlatformFee() external view returns (uint256);

    function getReferrerFee() external view returns (uint256);

    function getRoyaltyFee() external view returns (uint256);

    function getPlatformOwner() external view returns (address);

    function getFeeAggregator() external view returns (address);

    function getPaymentTokens() external view returns (address[] memory);

    function modelIsBlacklisted(address) external view returns (bool);

    function getPlatform() external view returns (address);

    function getModelContract(address contractAddress) external view returns (address);

    function logReferralPay(address from, address to, uint256 amount, address token) external;

    function logTransferNft(address from, address to, uint256 nftId, uint256 tokenId) external;

    function logAddNft(uint256 nftId, string memory uri, uint256 mintCap, address token, uint256 tokenAmount, string memory description) external;

    function logPurchaseNft(address creator, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string memory modelName) external;

    function logBuyNft(address buyer, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string memory modelName) external;

    function logUpdateNftPrice(address owner, uint256 nftId, uint256 tokenId, uint256 price) external;

    function logBurnNft(address owner, uint256 nftId, uint256 tokenId) external;

}
