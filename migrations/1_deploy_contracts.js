const Master = artifacts.require('Master');
const ModelCollection = artifacts.require('ModelCollection');

module.exports = async function (deployer, network, accounts) {

    const currentAccount = accounts[0];
    const referrerAccount = accounts[1];
    await deployer.deploy(ModelCollection);
    console.log('collectionContract Address: ', ModelCollection.address);

    if (network == 'development') {
    } else if (network == 'testnet') {
        const cummiesAddress = '0xd9c3602e2df40b32412ec2bbd7eeb33be7025bc9';
        await deployer.deploy(Master, ModelCollection.address, cummiesAddress);
        const masterContract = await Master.deployed();
        console.log('masterContract Address: ', Master.address);
        await masterContract.setPlatform(currentAccount);
        await masterContract.setFeeAggregator(referrerAccount);
        await masterContract.verifyModel(currentAccount);
        await masterContract.verifyModel(referrerAccount);
        console.log('modelAddress is verified.');
        const newCollectionAddress = await masterContract.newCollectionContract(
          'Icarus Resale',
          'Phoenix',
          'Male',
          referrerAccount,
          ''
        );
        console.log('newCollectionAddress: ', newCollectionAddress);
        // *** We should not forget approve ModelCollection Contract when purchase NFT(this should be done by frontend_
    } else {
    }

};
