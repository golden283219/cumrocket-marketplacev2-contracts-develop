# marketplacev2-contracts
Solidity contracts for marketplace V2

Working branch: develop
Production branch: master

## Events
### New model collection contract
```js
event NewCollectionContract(address indexed contractAddress, address indexed walletAddress);
```
Returns
- contractAddress (address of models generated contract)
- walletAddress (address of the model)

### Referral payout
```js
    event ReferralPay(address indexed contractAddress, address indexed from, address indexed to, uint256 amount, address token);
```
Returns
- contractAddress (address of the model contract)
- from (address of model who used refferal)
- to (address of model who received referral reward)
- amount (amount of currency received)
- token (address of the token payout)

### Transfer NFT
```js
event TransferNft(address indexed contractAddress, address indexed from, address indexed to, uint256 nftId, uint256 tokenId);
```
Returns
- contractAddress (address of the model contract)
- from (address of the transferer)
- to (address of reciever)
- nftId (ID of the NFT being transfered)
- nftCollectionContract (address of the collection the NFT is from)

### Add NFT
```js
event AddNft(address indexed contractAddress, uint256 nftId, string uri, uint256 mintCap, address token, uint256 tokenAmount);
```
Returns
- contractAddress (address of the model contract)
- nftId (ID of the newly added NFT)
- uri (uri of the ipfs link to the nft json data)
- mintCap (max amount to be minted
- token (address of the token used for payment)
- tokenAmount (amount of the token needed to purchase the nft)

### Buy NFT
```js
event PurchaseNft(address indexed contractAddress, address buyer, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted);
```
Returns
- contractAddress (address of the model contract)
- buyer (address of the buyer)
- nftId (ID of the nft being purchased)
- tokenId (ID of the payment token)
- mintCap (mint cap of the nft)
- minted (counter of the total of this nft minted)



## Flows

### Create new collection

    1. Frontend send NewCollection (modelName is username that is name of collection).
    2. .then() -> get txHash and send the POST to backend.
    3. Backend gets the modelContractAddress (if txHash is successful). # TODO: Listen for the event. We need to add also the modelName (collection).
    4. Frontend pings to getTransactionReciept(txhash), 
      4.1 If successful, don't do nothing.
      4.2 If fails, send DELETE to backend.

### Add NFT. This won't create a NFT, just declare "metadata" stored in a list. It specifies number of max copies, token available to purchase and price.

    - We need the URI (base64? upload ipfs? research...)
    - Frontend send to the backend a POST with the media and price, token, categories, etc.
    
### Purchase NFT. This "mints" the NFT, which will create a copy (only if is less than maximum mint cap).

    - When you purchase the NFT this will create the nftId. Frontend can't get this as response (is an event).
    - Backend will get all the required data from the event. TODO: Add also the modelName (collection) to the event args.
