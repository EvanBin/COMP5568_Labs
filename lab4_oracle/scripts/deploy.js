const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const e18 = hre.ethers.parseEther;

  // 1. Deploy tokens
  const TokenA = await hre.ethers.getContractFactory("TokenA");
  const tokenA = await TokenA.deploy(e18("1000000"));
  await tokenA.waitForDeployment();
  console.log("TokenA:", await tokenA.getAddress());

  const TokenB = await hre.ethers.getContractFactory("TokenB");
  const tokenB = await TokenB.deploy(e18("1000000"));
  await tokenB.waitForDeployment();
  console.log("TokenB:", await tokenB.getAddress());

  // 2. Deploy exchange and add liquidity (1 TKA = 100 TKB)
  const Exchange = await hre.ethers.getContractFactory("SimpleExchange");
  const exchange = await Exchange.deploy(
    await tokenA.getAddress(),
    await tokenB.getAddress()
  );
  await exchange.waitForDeployment();
  console.log("Exchange:", await exchange.getAddress());

  await tokenA.approve(await exchange.getAddress(), e18("10000"));
  await tokenB.approve(await exchange.getAddress(), e18("1000000"));
  await exchange.addLiquidity(e18("10000"), e18("1000000"));
  console.log("Liquidity added: 10,000 TKA + 1,000,000 TKB");

  // Check spot price
  const price = await exchange.getSpotPrice();
  console.log("Spot price (TKB per TKA):", hre.ethers.formatEther(price));

  // 3. Deploy vulnerable lending
  const Lending = await hre.ethers.getContractFactory("VulnerableLending");
  const lending = await Lending.deploy(
    await tokenA.getAddress(),
    await tokenB.getAddress(),
    await exchange.getAddress()
  );
  await lending.waitForDeployment();
  console.log("VulnerableLending:", await lending.getAddress());

  // Fund lending pool
  await tokenA.approve(await lending.getAddress(), e18("50000"));
  await lending.fundPool(e18("50000"));
  console.log("Lending pool funded with 50,000 TKA");

  console.log("\n✅ All contracts deployed.");
}

main().catch(console.error);