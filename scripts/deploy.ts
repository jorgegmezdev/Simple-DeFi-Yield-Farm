import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deploying contracts with account:", deployerAddress);

  // --- Deploy DAppToken ---
  const DAppTokenFactory = await ethers.getContractFactory("DAppToken");
  const dappToken = await DAppTokenFactory.deploy(deployerAddress);
  await dappToken.waitForDeployment();
  console.log("DAppToken deployed at:", await dappToken.getAddress());

  // --- Deploy LPToken ---
  const LPTokenFactory = await ethers.getContractFactory("LPToken");
  const lpToken = await LPTokenFactory.deploy(deployerAddress);
  await lpToken.waitForDeployment();
  console.log("LPToken deployed at:", await lpToken.getAddress());

  // --- Deploy TokenFarm ---
  const initialReward = 1000;
  const minReward = 500;
  const maxReward = 1500;
  const feePercent = 200; // 2%

  const TokenFarmFactory = await ethers.getContractFactory("TokenFarm");
  const tokenFarm = await TokenFarmFactory.deploy(
    dappToken.getAddress(),
    lpToken.getAddress(),
    initialReward,
    minReward,
    maxReward,
    feePercent
  );
  await tokenFarm.waitForDeployment();
  console.log("TokenFarm deployed at:", await tokenFarm.getAddress());

  // --- Deploy TokenFarmV2 (master for proxy clones) ---
  const TokenFarmV2Factory = await ethers.getContractFactory("TokenFarmV2");
  const tokenFarmV2 = await TokenFarmV2Factory.deploy();
  await tokenFarmV2.waitForDeployment();
  console.log("TokenFarmV2 deployed at:", await tokenFarmV2.getAddress());

  // --- Deploy TokenFarmFactory ---
  const TokenFarmFactoryFactory = await ethers.getContractFactory("TokenFarmFactory");
  const tokenFarmFactory = await TokenFarmFactoryFactory.deploy(tokenFarmV2.getAddress());
  await tokenFarmFactory.waitForDeployment();
  console.log("TokenFarmFactory deployed at:", await tokenFarmFactory.getAddress());

  // --- Create a new farm via the factory ---
  const createTx = await tokenFarmFactory.createFarm(
    lpToken.getAddress(),
    dappToken.getAddress(),
    1000, // initialReward
    500,  // minReward
    1500, // maxReward
    200   // claimFee
  );

  // Wait for the transaction to be mined
  const receipt = await createTx.wait();

  console.log(
    "New TokenFarmV2 clone created via factory, tx hash:",
    receipt!.hash
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
