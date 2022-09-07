const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect, assert } = require("chai");
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
    monion = await MonionToken.deploy(20000000);
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
      expect(await staking.VALIDITY_PERIOD()).to.equal(ONE_YEAR_IN_SECS);
    });
    it("should confirm maximum staked tokens of 500000", async function () {
      expect(await staking.MAXIMUM_POOL_MONIONS()).to.equal(500000);
    });
    it("should confirm that the size of the pool is 100000", async function () {
      expect(await staking.TOTAL_REWARD()).to.equal(100000);
    });
  });

  describe("Test staking operations", function () {
    it("should confirm that the reward pool is funded", async function () {
      // await monion.connect(deployer).approve(rewardPool.address, 20000);
      // await monion.connect(deployer).transferFrom(deployer.address, rewardPool.address, 20000);
      await monion.connect(deployer).transfer(rewardPool.address, 100000);
      expect(await rewardPool.poolBalance()).to.equal(100000);
    });
    it("the deployer should fund alice, bob and charlie", async function () {
      await monion.connect(deployer).transfer(alice.address, 3000);
      await monion.connect(deployer).transfer(bob.address, 34000);
      await monion.connect(deployer).transfer(charlie.address, 18000);
      await monion.connect(deployer).transfer(david.address, 500001);
      expect(await monion.balanceOf(alice.address)).to.equal(3000);
      expect(await monion.balanceOf(bob.address)).to.equal(34000);
      expect(await monion.balanceOf(charlie.address)).to.equal(18000);
      expect(await monion.balanceOf(david.address)).to.equal(500001);
    });
    it("should allow Alice stake at the start of day 3", async function () {
      const aliceStakedTime = await time.increase(60 * 60 * 24 * 3);
      await monion.connect(alice).approve(staking.address, 2000);
      await staking.connect(alice).stake(2000);
      expect(await staking.balanceOf(alice.address)).to.equal(2000);
      console.log(
        `Alice staked at ${new Date(aliceStakedTime * 1000)
          .toISOString()
          .slice(0, 19)
          .replace("T", " ")}`
      );
      // expect(await monion.balanceOf(alice.address)).to.equal(3000);
    });
    it("should allow Bob stake at the start of day 25 (22 days after Alice)", async function () {
      const bobStakedTime = await time.increase(60 * 60 * 24 * 22);
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
    it("should allow Charlie stake at the start of day 180 (178 days after Alice)", async function () {
      const charlieStakedTime = await time.increase(60 * 60 * 24 * 155);
      await monion.connect(charlie).approve(staking.address, 18000);
      await staking.connect(charlie).stake(18000);
      expect(await staking.balanceOf(charlie.address)).to.equal(18000);
      console.log(
        `Charlie staked at ${new Date(charlieStakedTime * 1000)
          .toISOString()
          .slice(0, 19)
          .replace("T", " ")}`
      );
    });

    it("should allow Bob to unstake by day 201", async function () {
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
    it("should allow Bob to claim rewards from the pool", async function () {
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
    it("should enforce unbonding time error for Charlie's unstaking at day 201", async function () {
      try {
        await staking.connect(charlie).initiateUnstake(6000);
        await staking.connect(charlie).initiateUnstake(6000);
      } catch (error) {
        console.log(error.message);
        assert(error.message.includes("Staking__UnbondingIncomplete"));
        return false;
      }
      assert(false);
      // await staking.connect(charlie).unstake(6000);
      //     await expect(lock.withdraw()).to.changeEtherBalances(
      //   [owner, lock],
      //   [lockedAmount, -lockedAmount]
    });
    it("should attempt to stake more than the pool limit", async function () {
      await monion.connect(david).approve(staking.address, 500001);
      try {
        await staking.connect(david).stake(500001);
      } catch (error) {
        console.log(error.message);
        return;
      }
      assert(false);
    });
    xdescribe("Test Pause and Unpause features", function () {
      before(async function () {
        await staking.connect(deployer).pauseContract();
      });
      it("should allow the admin to pause the contract and limit staking features", async function () {
        await monion.connect(bob).approve(staking.address, 3000);
        try {
          expect(await staking.connect(bob).stake(3000));
        } catch (error) {
          assert(error.message.includes("Pausable: paused"));
          return;
        }
        assert(false);
      });
      it("should allow the admin to pause the contract and limit unstaking features", async function () {
        // await staking.connect(deployer).pauseContract();
        try {
          expect(await staking.connect(bob).initiateUnstake(3000));
        } catch (error) {
          // console.log(error.message);
          assert(error.message.includes("Pausable: paused"));
          return;
        }
        assert(false);
      });
      it("should allow the admin to pause the contract and limit claiming features", async function () {
        // await staking.connect(deployer).pauseContract();
        try {
          expect(await staking.connect(alice).claimRewards());
        } catch (error) {
          // console.log(error.message);
          assert(error.message.includes("Pausable: paused"));
          return;
        }
        assert(false);
      });
      it("should unpause", async function () {
        await staking.connect(deployer).unpauseContract();
      });
    });

    xdescribe("Post Validity test", function () {
      before(async function () {
        const timeSkipEnd = await time.increase(60 * 60 * 24 * 165);
        console.log(
          `Current time period is ${new Date(timeSkipEnd * 1000)
            .toISOString()
            .slice(0, 19)
            .replace("T", " ")}`
        );
      });
      it("should not allow for staking", async function () {
        await monion.connect(bob).approve(staking.address, 3000);
        try {
          await staking.connect(bob).stake(3000);
        } catch (error) {
          console.log(error.message);
          // assert.equal(
          //   error.message,
          //   "VM Exception while processing transaction: reverted with reason string 'Pool has exceeded period'"
          // );
          assert(error.message.includes("Staking__PoolExceededValidityPeriod"));
          return;
        }
        assert(false);
      });
      it("should allow for unstaking of tokens", async function () {
        let alicebalBefore, alicebalAfter;
        alicebalBefore = await monion.balanceOf(alice.address);
        await staking.connect(alice).initiateUnstake(2000);
        const inContractBalance = await staking.balanceOf(alice.address);
        assert.equal(inContractBalance.toNumber(), 0);
        alicebalAfter = await monion.balanceOf(alice.address);
        // console.log(alicebalBefore)
        expect(alicebalAfter.toNumber()).to.be.greaterThan(
          alicebalBefore.toNumber()
        );
      });
      it("should allow for claiming of rewards", async function () {
        alicebalBefore = await monion.balanceOf(alice.address);
        await staking.connect(alice).claimRewards();
        alicebalAfter = await monion.balanceOf(alice.address);
        console.log(
          `Alice's balance before claiming rewards was ${alicebalBefore.toNumber()}`
        );
        console.log(
          `Alice's balance after claiming rewards was ${alicebalAfter.toNumber()}`
        );
        expect(alicebalAfter.toNumber()).to.be.greaterThan(
          alicebalBefore.toNumber()
        );
      });
      describe("Tests after owner has closed Pool", function () {
        before(async function () {
          await staking.connect(deployer).pauseContract();
          await staking.connect(deployer).closePool();
        });
        it("should NOT allow any withdrawals of rewards", async function () {
          try {
            await staking.connect(charlie).claimRewards();
          } catch (error) {
            console.log(error.message);
            return;
          }
          assert(false);
        });
      });
    });
  });
});
