const BigNumber = web3.utils.BN;
const Chance = require('chance');
const Master = artifacts.require('Master');
const Modelcollection = artifacts.require("ModelCollection");
const catchRevert = require("./exceptions.js").catchRevert;
const BEP20 = artifacts.require("BEP20");
const timeMachine = require('ganache-time-traveler');

require('chai')
    .use(require('chai-bn')(BigNumber))
    .should();

contract('Master', accounts => {

    const deployModelContract = async (
        address,
        name = '',
        description = '',
        gender = '',
        referrer = '0x0000000000000000000000000000000000000000'
    ) => {

        await this.master.verifyModel(address, { from: accounts[0] });

        await this.master.newCollectionContract(
            name,
            description,
            gender,
            referrer,
            'salty',
            { from: address }
        );

        const modelContractAddr = await this.master.getModelContract.call(address);

        return Modelcollection.at(modelContractAddr);

    }

    before(async() => {

        this.chance = new Chance();

        this.master = await Master.deployed();

        this.deployer = accounts[0];

        await this.master.setFarmAddress(accounts[6]);
        await this.master.setFeeSplitter(accounts[5]);

        [primaryTokenAddress, secondaryTokenAddress] = await this.master.getPaymentTokens.call();

        this.secondaryBep20 = await BEP20.at(secondaryTokenAddress);
        this.bep20 = await BEP20.at(primaryTokenAddress);

    });

    describe('model contract', async () => {

        before(async() => {

            this.modelName = 'Colonel Sanders';
            this.modelDescription = 'Finger lickin\' good';
            this.modelGender = 'male';
            this.modelAddress = accounts[1];

            this.modelContract = await deployModelContract(
                this.modelAddress,
                this.modelName,
                this.modelDescription,
                this.modelGender
            );

        });

        describe('creation', async () => {

            it('should contain the correct name', async () => {
                const nameFromContract = await this.modelContract.modelName();
                await nameFromContract.should.equal(this.modelName);
            });

            it('should contain the correct description', async () => {
                const descriptionFromContract = await this.modelContract.modelDescription();
                await descriptionFromContract.should.equal(this.modelDescription);
            });

            it('should contain the correct gender', async () => {
                const genderFromContract = await this.modelContract.modelGender();
                await genderFromContract.should.equal(this.modelGender);
            });

            it('should contain the correct model address', async () => {
                const addressFromContract = await this.modelContract.modelAddress();
                await addressFromContract.should.equal(this.modelAddress);
            });

            it('should lock the initialiser', async () => {
                await catchRevert( this.modelContract.initialize(
                    this.master.address,
                    '',
                    '',
                    '',
                    accounts[1],
                    '0x0000000000000000000000000000000000000000',
                    0,
                    0,
                    { from: accounts[1] })
                );
            });

        });

        describe('add nft', async () => {

            it('should let the contract owner add an nft', async() => {
                await this.modelContract.addNft.call(
                    'https://nftaddress.io',
                    secondaryTokenAddress,
                    100,
                    10,
                    { from: accounts[1] }
                );
            });

            it('should not let anyone but the contract owner add an nft', async() => {
                await catchRevert(
                    this.modelContract.addNft.call(
                        'https://nftaddress.io',
                        secondaryTokenAddress,
                        100,
                        10,
                        { from: accounts[0] }
                    )
                );
            });

        });

        describe('purchase nft', async () => {

            before(async() => {

                await this.modelContract.addNft(
                    'https://nftaddress.io',
                    secondaryTokenAddress,
                    100,
                    10000,
                    { from: accounts[1] }
                );

            });

            it('should allow the purchasing of a valid nft', async () => {
                await this.secondaryBep20.transfer(accounts[2], 100, { from: accounts[0] })
                await this.secondaryBep20.approve(this.modelContract.address, 100, { from: accounts[2] });
                await this.modelContract.purchaseNft(0, { from: accounts[2] });
            });

            it('should not allow the purchasing of an nft which is not mintable', async () => {

                await this.modelContract.addNft(
                    'https://nftaddress.io',
                    secondaryTokenAddress,
                    100,
                    10,
                    { from: accounts[1] }
                );

                for(let i = 0; i < 10; ++i) {
                    await this.secondaryBep20.transfer(accounts[2], 100, { from: accounts[0] })
                    await this.secondaryBep20.approve(this.modelContract.address, 100, { from: accounts[2] });
                    await this.modelContract.purchaseNft(1, { from: accounts[2] });
                }

                await this.secondaryBep20.transfer(accounts[2], 100, { from: accounts[0] })
                await this.secondaryBep20.approve(this.modelContract.address, 100, { from: accounts[2] });
                await catchRevert( this.modelContract.purchaseNft(1, { from: accounts[2] }) );

            });

            it('should not allow the purchasing of an nft with the incorrect amount of tokens', async () => {
                await this.secondaryBep20.approve(this.modelContract.address, 99, { from: accounts[2] });
                await catchRevert( this.modelContract.purchaseNft(0, { from: accounts[2] }) );
            });

            it('should distribute fees correctly for the main token', async () => {

                await this.modelContract.addNft(
                    'https://nftaddress.io',
                    primaryTokenAddress,
                    100,
                    10000,
                    { from: accounts[1] }
                );

                const farmsBalanceBefore = await this.bep20.balanceOf.call(accounts[6]);
                const modelBalanceBefore = await this.bep20.balanceOf.call(accounts[1]);

                // Buy NFT
                await this.bep20.transfer(accounts[2], 100, { from: accounts[0] })
                await this.bep20.approve(this.modelContract.address, 100, { from: accounts[2] });
                await this.modelContract.purchaseNft(2, { from: accounts[2] });

                const farmsBalanceAfter = await this.bep20.balanceOf.call(accounts[6]);
                const modelBalanceAfter = await this.bep20.balanceOf.call(accounts[1]);

                // Check fee splits
                farmsBalanceAfter.sub(farmsBalanceBefore).should.be.a.bignumber.that.equals('15');
                modelBalanceAfter.sub(modelBalanceBefore).should.be.a.bignumber.that.equals('85');

            });

            it('should distribute fees correctly for the non main tokens', async () => {

                const feeSplitterBalanceBefore = await this.secondaryBep20.balanceOf.call(accounts[5]);
                const modelBalanceBefore = await this.secondaryBep20.balanceOf.call(accounts[1]);

                // Buy NFT
                await this.secondaryBep20.transfer(accounts[2], 100, { from: accounts[0] })
                await this.secondaryBep20.approve(this.modelContract.address, 100, { from: accounts[2] });
                await this.modelContract.purchaseNft(0, { from: accounts[2] });

                const feeSplitterBalanceAfter = await this.secondaryBep20.balanceOf.call(accounts[5]);
                const modelBalanceAfter = await this.secondaryBep20.balanceOf.call(accounts[1]);

                // Check fee splits
                feeSplitterBalanceAfter.sub(feeSplitterBalanceBefore).should.be.a.bignumber.that.equals('15');
                modelBalanceAfter.sub(modelBalanceBefore).should.be.a.bignumber.that.equals('85');

            });

            it('should return the correct token URI', async () => {

                const tokenURI = 'https://nftaddress2.io';

                await this.modelContract.addNft(
                    tokenURI,
                    secondaryTokenAddress,
                    100,
                    1,
                    { from: accounts[1] }
                );

                await this.secondaryBep20.transfer(accounts[2], 100, { from: accounts[0] })
                await this.secondaryBep20.approve(this.modelContract.address, 100, { from: accounts[2] });

                const tokenID = await this.modelContract.purchaseNft.call(3, { from: accounts[2] });

                await this.modelContract.purchaseNft(3, { from: accounts[2] });

                const returnedTokenURI = await this.modelContract.tokenURI(tokenID.toNumber());

                returnedTokenURI.should.equal(tokenURI);

            });

        });

        describe('referrals', async () => {

            before(async () => {

                this.referredModelContract = await deployModelContract(
                    accounts[2],
                    'The Burger King',
                    'Have it your way',
                    'male',
                    accounts[1]
                );

                await this.referredModelContract.addNft(
                    'https://nftaddress.io',
                    secondaryTokenAddress,
                    100,
                    10,
                    { from: accounts[2] }
                );

            });

            it('should pay dividends to the referrer', async() => {

                const modelBalanceBefore = await this.secondaryBep20.balanceOf.call(accounts[1]);
                const feeSplitterBalanceBefore = await this.secondaryBep20.balanceOf.call(accounts[5]);

                // Give the user the nessacary money
                await this.secondaryBep20.transfer(accounts[3], 100, { from: accounts[0] })
                await this.secondaryBep20.approve(this.referredModelContract.address, 100, { from: accounts[3] });
                await this.referredModelContract.purchaseNft(0, { from: accounts[3] });

                const modelBalanceAfter = await this.secondaryBep20.balanceOf.call(accounts[1]);
                const feeSplitterBalanceAfter = await this.secondaryBep20.balanceOf.call(accounts[5]);

                feeSplitterBalanceAfter.sub(feeSplitterBalanceBefore).should.be.a.bignumber.that.equals('10');
                modelBalanceAfter.sub(modelBalanceBefore).should.be.a.bignumber.that.equals('5');

            });

            it('should stop paying dividends to the referrer after the timeframe', async() => {

                let snapshot = await timeMachine.takeSnapshot();
                // advance time by a year
                await timeMachine.advanceTimeAndBlock(3.154e+7);

                const modelBalanceBefore = await this.secondaryBep20.balanceOf.call(accounts[1]);
                const feeSplitterBalanceBefore = await this.secondaryBep20.balanceOf.call(accounts[5]);

                // Give the user the nessacary money
                await this.secondaryBep20.transfer(accounts[3], 100, { from: accounts[0] })
                await this.secondaryBep20.approve(this.referredModelContract.address, 100, { from: accounts[3] });
                await this.referredModelContract.purchaseNft(0, { from: accounts[3] });

                const modelBalanceAfter = await this.secondaryBep20.balanceOf.call(accounts[1]);
                const feeSplitterBalanceAfter = await this.secondaryBep20.balanceOf.call(accounts[5]);

                feeSplitterBalanceAfter.sub(feeSplitterBalanceBefore).should.be.a.bignumber.that.equals('15');
                modelBalanceAfter.sub(modelBalanceBefore).should.be.a.bignumber.that.equals('0');

                await timeMachine.revertToSnapshot(snapshot['result']);

            });

            it('should stop paying dividends to to a blacklisted model', async() => {

                // advance time by a year
                await this.master.blacklist(accounts[1]);

                const modelBalanceBefore = await this.secondaryBep20.balanceOf.call(accounts[1]);
                const feeSplitterBalanceBefore = await this.secondaryBep20.balanceOf.call(accounts[5]);

                // Give the user the nessacary money
                await this.secondaryBep20.transfer(accounts[3], 100, { from: accounts[0] })
                await this.secondaryBep20.approve(this.referredModelContract.address, 100, { from: accounts[3] });
                await this.referredModelContract.purchaseNft(0, { from: accounts[3] });

                const modelBalanceAfter = await this.secondaryBep20.balanceOf.call(accounts[1]);
                const feeSplitterBalanceAfter = await this.secondaryBep20.balanceOf.call(accounts[5]);

                feeSplitterBalanceAfter.sub(feeSplitterBalanceBefore).should.be.a.bignumber.that.equals('15');
                modelBalanceAfter.sub(modelBalanceBefore).should.be.a.bignumber.that.equals('0');

            });

        });

    });

});
