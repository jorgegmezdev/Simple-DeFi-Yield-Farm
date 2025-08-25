import { expect } from "chai";
import { ethers } from "hardhat";
import { DAppToken, LPToken, TokenFarm } from "../typechain-types";

describe("TokenFarm (Bonus 3 tests)", async function () {
  let deployer: any, user1: any, user2: any;
  let dappToken: DAppToken;
  let lpToken: LPToken;
  let tokenFarm: TokenFarm;

  const initialReward = 1000;
  const minReward = 500;
  const maxReward = 1500;
  const feePercent = 200; // 2%

  beforeEach(async function () {
    [deployer, user1, user2] = await ethers.getSigners();

    // Deploy DAppToken
    const DAppTokenFactory = await ethers.getContractFactory("DAppToken");
    dappToken = (await DAppTokenFactory.deploy(deployer.address)) as DAppToken;
    await dappToken.waitForDeployment();

    // Deploy LPToken
    const LPTokenFactory = await ethers.getContractFactory("LPToken");
    lpToken = (await LPTokenFactory.deploy(deployer.address)) as LPToken;
    await lpToken.waitForDeployment();

    // Deploy TokenFarm
    const TokenFarmFactory = await ethers.getContractFactory("TokenFarm");
    tokenFarm = (await TokenFarmFactory.deploy(
      dappToken.getAddress(),
      lpToken.getAddress(),
      initialReward,
      minReward,
      maxReward,
      feePercent
    )) as TokenFarm;
    await tokenFarm.waitForDeployment();
  });

  it("Should mint LP tokens for user and allow deposit", async function () {
    // Mint LP tokens to user1
    await lpToken.mint(user1.address, 1000);
    expect(await lpToken.balanceOf(user1.address)).to.equal(1000);

    // Approve and deposit
    await lpToken.connect(user1).approve(tokenFarm.getAddress(), 500);
    await tokenFarm.connect(user1).deposit(500);

    const staker = await tokenFarm.stakersInfo(user1.address);
    expect(staker.balance).to.equal(500);
    expect(staker.isStaking).to.be.true;
  });

  it("Should distribute rewards correctly", async function () {
    // Mint LP and deposit
    await lpToken.mint(user1.address, 1000);
    await lpToken.connect(user1).approve(tokenFarm.getAddress(), 1000);
    await tokenFarm.connect(user1).deposit(1000);

    // Move blocks forward (simulate by mining)
    await ethers.provider.send("evm_mine", []);

    // Distribute rewards
    await tokenFarm.distributeRewardsAll();

    const pending = await tokenFarm.pendingRewardsView(user1.address);
    expect(pending).to.be.gt(0);
  });

  it("User should claim rewards with fee applied", async function () {
    // Mint LP and deposit
    await lpToken.mint(user1.address, 1000);
    await lpToken.connect(user1).approve(tokenFarm.getAddress(), 1000);
    await tokenFarm.connect(user1).deposit(1000);

    // Mine a block
    await ethers.provider.send("evm_mine", []);

    // Distribute rewards
    await tokenFarm.distributeRewardsAll();

    const pendingBefore = await tokenFarm.pendingRewardsView(user1.address);

    // Claim rewards
    await tokenFarm.connect(user1).claimRewards();

    const pendingAfter = await tokenFarm.pendingRewardsView(user1.address);
    expect(pendingAfter).to.equal(0);

    const dappBalance = await dappToken.balanceOf(user1.address);
    // 2% fee
    const expected = (pendingBefore * BigInt(10000 - feePercent)) / 10000n;
    expect(dappBalance).to.equal(expected);

    // Owner should have accumulated fee
    const tokenFarmState = await tokenFarm.stakersInfo(user1.address);
    expect(tokenFarmState.pendingRewards).to.equal(0);
  });

  it("User should withdraw LP tokens and claim remaining rewards", async function () {
    // Mint LP and deposit
    await lpToken.mint(user1.address, 1000);
    await lpToken.connect(user1).approve(tokenFarm.getAddress(), 1000);
    await tokenFarm.connect(user1).deposit(1000);

    // Mine some blocks
    await ethers.provider.send("evm_mine", []);
    await ethers.provider.send("evm_mine", []);

    // Distribute rewards
    await tokenFarm.distributeRewardsAll();

    const pendingBefore = await tokenFarm.pendingRewardsView(user1.address);

    // Withdraw all LP
    await tokenFarm.connect(user1).withdraw();

    const staker = await tokenFarm.stakersInfo(user1.address);
    expect(staker.balance).to.equal(0);
    expect(staker.isStaking).to.be.false;

    // Claim rewards
    await tokenFarm.connect(user1).claimRewards();

    const dappBalance = await dappToken.balanceOf(user1.address);
    const expected = (pendingBefore * BigInt(10000 - feePercent)) / 10000n;

    expect(dappBalance).to.equal(expected);
  });
});
