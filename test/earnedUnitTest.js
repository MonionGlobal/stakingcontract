const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
// const { ethers } = require("ethers");

describe("Setup of Architecture", function () {
  let deployer, alice, bob, charlie, david;
  let admin, monion, rewardPool, staking;
  let unlockTime;
  let ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
  before(async function () {
    unlockTime = (await time.latest()) + ONE_YEAR_IN_SECS;

    [deployer, alice, bob, charlie, david] = await ethers.getSigners();
    const AdminConsole = await ethers.getContractFactory("Admin", deployer);
    admin = await AdminConsole.deploy();
    await admin.deployed();

    const MonionToken = await ethers.getContractFactory("Monion", deployer);
    monion = await MonionToken.deploy(2000000);
    await monion.deployed();

    const RewardPool = await ethers.getContractFactory("Distributor", deployer);
    rewardPool = await RewardPool.deploy(monion.address, admin.address);
    await rewardPool.deployed();

    const StakingContract = await ethers.getContractFactory(
      "StakingRewards",
      deployer
    );
    staking = await StakingContract.deploy(monion.address, rewardPool.address);
    await staking.deployed();

    await admin.setStakingAddress(staking.address);
  });

  describe("Deployed Processes", function () {
    it("should confirm the staking period of 1 year", async function () {
      expect(await staking.validityPeriod()).to.equal(ONE_YEAR_IN_SECS);
    });
    it("should confirm maximum staked tokens of 100000", async function () {
      expect(await staking.maximumPoolMonions()).to.equal(100000);
    });
    it("should confirm that the size of the pool is 20000", async function () {
      expect(await staking.totalReward()).to.equal(20000);
    });
  });

  describe("Test staking operations", function () {
    it("should confirm that the reward pool is funded", async function () {
      // await monion.connect(deployer).approve(rewardPool.address, 20000);
      // await monion.connect(deployer).transferFrom(deployer.address, rewardPool.address, 20000);
      await monion.connect(deployer).transfer(rewardPool.address, 20000);
      expect(await rewardPool.poolBalance()).to.equal(20000);
    });
    it("the deployer should fund alice, bob", async function () {
        
        await monion.connect(deployer).transfer(alice.address, 30000);
        await monion.connect(deployer).transfer(bob.address, 34000);
        expect(await monion.balanceOf(alice.address)).to.equal(30000);
        expect(await monion.balanceOf(bob.address)).to.equal(34000);
    });
    it("should allow Alice stake at the start of day 3", async function () {
      const aliceStakedTime = await time.increase(60 * 60 * 24 * 3);
      await monion.connect(alice).approve(staking.address, 20000);
      await staking.connect(alice).stake(2000);
      expect(await staking.balanceOf(alice.address)).to.equal(2000);
      console.log(
        `Alice staked at ${new Date(aliceStakedTime * 1000)
          .toISOString()
          .slice(0, 19)
          .replace("T", " ")}`
      );
      
    //   console.log(`Alice's rewards earned are ${await staking.connect(alice).rewards(alice.address)}`);
    });
    it("should allow Alice stake again at the start of day 20", async function () {
      const aliceStakedTime = await time.increase(60 * 60 * 24 * 17);
      
      console.log(
        `Alice's rewards earned at the start of day 20 are ${await staking
          .connect(alice)
          .rewards(alice.address)}`
      );
      let rewardsCalculated = await staking.connect(alice)._calcReward();
      console.log(
        `Alice's rewards earned IN MEMORY at the start of day 20 are ${rewardsCalculated.toNumber()}`
      );

      let getRewardVariables = await staking
        .connect(alice)
        .getCalcRewardVariables();
        console.log(`Rewards variables are ${getRewardVariables}`);
        // console.log(getRewardVariables)
    //   await staking.connect(alice).stake(5000);
    //   expect(await staking.balanceOf(alice.address)).to.equal(7000);
    //   console.log(
    //     `Alice staked at ${new Date(aliceStakedTime * 1000)
    //       .toISOString()
    //       .slice(0, 19)
    //       .replace("T", " ")}`
    //   );
    //   rewardsCalculated = await staking.connect(alice)._calcReward();
    //   console.log(
    //     `Alice's rewards earned IN MEMORY after staking at the start of day 20 are ${rewardsCalculated.toNumber()}`
    //   );
    //   console.log(
    //     `Alice's rewards earned IN STORAGE after staking at the start of day 20 are ${await staking
    //       .connect(alice)
    //       .rewards(alice.address)}`
    //   );

    
    });
    xit("should allow Bob stake at the start of day 25 (22 days after Alice)", async function () {
      const bobStakedTime = await time.increase(60 * 60 * 24 * 22);
      console.log(
        `Alice's rewards earned are ${staking
          .connect(alice)
          .rewards(alice.address)}`
      );
      await monion.connect(bob).approve(staking.address, 30000);
      await staking.connect(bob).stake(30000);
      expect(await staking.balanceOf(bob.address)).to.equal(30000);
      console.log(
        `Bob staked at ${new Date(bobStakedTime * 1000)
          .toISOString()
          .slice(0, 19)
          .replace("T", " ")}`
      );
    });

    xit("should allow Bob to unstake by day 201", async function () {
      const initiateUnstakedTime = await time.increase(60 * 60 * 24 * 21);
      console.log(
        `Bob initiated unstaking at ${new Date(initiateUnstakedTime * 1000)
          .toISOString()
          .slice(0, 19)
          .replace("T", " ")}`
      );
      await staking.connect(bob).initiateUnstake(21000);
      const unstakedTime = await time.increase(60 * 60 * 24 * 1);
      console.log(
        `Bob unstaked 21000 at ${new Date(unstakedTime * 1000)
          .toISOString()
          .slice(0, 19)
          .replace("T", " ")}`
      );
      const balBefore = await monion.balanceOf(bob.address);
      await staking.connect(bob).initiateUnstake(21000);
      const balAfter = await monion.balanceOf(bob.address);
      console.log(
        `Bob's balance before withdrawal was ${balBefore}, balance after withdrawal is ${balAfter}`
      );
      // assert(balAfter.toNumber() > balBefore.toNumber());
      expect(balAfter.toNumber()).to.be.greaterThan(balBefore.toNumber());
    });
    xit("should allow Bob to claim rewards from the pool", async function () {
      console.log(
        "Pool balance is: ",
        await monion.balanceOf(rewardPool.address)
      );
      const balBefore = await monion.balanceOf(bob.address);
      console.log(
        "Rewards balance due to Bob: ",
        await staking.rewards(bob.address)
      );
      await staking.connect(bob).claimRewards();
      const balAfter = await monion.balanceOf(bob.address);
      console.log(
        `Bob's balance before claiming reward was ${balBefore}, balance after claiming is ${balAfter}`
      );
    });
  });
});
