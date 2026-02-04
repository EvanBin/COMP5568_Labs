const hre = require("hardhat");

async function main() {
  console.log("Deploying contracts...\n");

  // Get signers
  const [deployer, user1, user2] = await hre.ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("User1 address:", user1.address);
  console.log("User2 address:", user2.address);
  console.log();

  // Deploy TokenA
  const TokenA = await hre.ethers.getContractFactory("TokenA");
  const tokenA = await TokenA.deploy(1000000); // 1 million tokens
  await tokenA.waitForDeployment();
  const tokenAAddress = await tokenA.getAddress();
  console.log("TokenA deployed to:", tokenAAddress);

  // Deploy TokenB
  const TokenB = await hre.ethers.getContractFactory("TokenB");
  const tokenB = await TokenB.deploy(1000000); // 1 million tokens
  await tokenB.waitForDeployment();
  const tokenBAddress = await tokenB.getAddress();
  console.log("TokenB deployed to:", tokenBAddress);

  // Deploy SimpleAMM
  const SimpleAMM = await hre.ethers.getContractFactory("SimpleAMM");
  const amm = await SimpleAMM.deploy(tokenAAddress, tokenBAddress);
  await amm.waitForDeployment();
  const ammAddress = await amm.getAddress();
  console.log("SimpleAMM deployed to:", ammAddress);
  console.log();

  // Transfer tokens to user1 and user2 for testing
  const transferAmount = hre.ethers.parseUnits("10000", 18);
  await tokenA.transfer(user1.address, transferAmount);
  await tokenB.transfer(user1.address, transferAmount);
  await tokenA.transfer(user2.address, transferAmount);
  await tokenB.transfer(user2.address, transferAmount);
  console.log("Transferred 10,000 TokenA and TokenB to User1 and User2\n");

  // Save addresses for later use
  console.log("=== Save these addresses ===");
  console.log("TokenA:", tokenAAddress);
  console.log("TokenB:", tokenBAddress);
  console.log("SimpleAMM:", ammAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });