# **Lab 2: AMM Pool and MEV Attacks**

> COMP 5568 - Decentralized Finance (Semester 2, 2025/26)
>
> The Hong Kong Polytechnic University

The lab is designed for beginners to blockchain development. We will use minimal external tools and focus on understanding core concepts from Lecture 4. In this lab, you will:
1. Deploy a **private blockchain** for development.
2. Create and deploy a simple **Automated Market Maker (AMM) pool**.
3. Experience **slippage** and simulate a **sandwich attack**.

## Prerequisites

Before starting, ensure you have:
- **Node.js** (v16 or higher) installed (**npm** package manager is automatically included when you install Node.js).
- A code editor (VS Code recommended).
- Basic understanding of command line operations.

You may follow the installation guide below for your operating system.

### Installing Node.js and npm

#### For Windows Users

1. Visit the official Node.js website: **https://nodejs.org/**
2. Download the Windows installer (.msi file)
3. On the "Custom Setup" page, **keep all default options checked**:
   - Node.js runtime
   - npm package manager
   - **Add to PATH** (this is very important!)
4. If prompted by Windows User Account Control, click **"Yes"**
5. Restart your computer so that the PATH changes take effect.

##### Verify Installation

1. Open **Command Prompt** or **PowerShell**:
   - Press `Windows Key + R`
   - Type `cmd` or `powershell` and press Enter
2. Type the following command and press Enter:
   ```bash
   node -v
   ```
   You should see something like: `v20.11.0` (version number may vary)

3. Check npm installation:
   ```bash
   npm -v
   ```
   You should see something like: `10.2.4` (version number may vary)

If both commands show version numbers, Node.js and npm are successfully installed.

#### For MacOS Users

macOS users have two good options: the official installer or Homebrew (a popular package manager for Mac).

**Step 1: Install Homebrew (if not already installed)**

1. Open **Terminal**, use the command to install:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Follow any on-screen instructions to add Homebrew to your PATH

3. Update Homebrew with:

    ```bash
    brew update
    ```

**Step 2: Install Node.js and npm with Homebrew**

```bash
brew install node
```

**Step 3: Verify Installation**

Close and reopen Terminal. Then test the installation through:

```bash
node -v
npm -v
```

Both commands should display version numbers.



## Task 1: Deploy a Private Blockchain

In this section, we will set up a local Ethereum blockchain using Hardhat Network.

### Step 1.1: Download Lab Materials

Download lab materials from: https://github.com/EvanBin/COMP5568_Labs

Change to lab2 directory:

```bash
cd lab2_amm
```

### Step 1.2: Initialize Hardhat Project

Install the development dependency:

```bash
npm install
```

Run the Hardhat initialization:

```bash
npx hardhat init
```

When prompted:

- Select: **Create a JavaScript project**
- Hardhat project root: **./**
-  Do you want to add a .gitignore? (Y/n) ‣ **y**

This will create the following structure:

```
amm-lab/
├── contracts/         # Smart contracts folder
├── test/              # Test files
└── hardhat.config.js  # Hardhat configuration
```

### Step 1.3: Start Your Private Blockchain

In your terminal, run:

```bash
npx hardhat node
```

You should see output similar to:

```
Started HTTP and WebSocket JSON-RPC server at http://127.0.0.1:8545/

Accounts
========
Account #0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000 ETH)
Account #1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000 ETH)
...
```

**Important:** **Keep this terminal window open. Your private blockchain is now running!**

Each account has **10,000 ETH** for testing purposes.



## Task 2: Deploy an AMM Pool

Now we will create two ERC20 tokens and deploy a simple constant product AMM (x × y = k).

### Step 2.1: Clean Up Default Files

Open a **new terminal window** (keep the Hardhat node running in the first one).

Navigate to your project and remove the default contract:

```bash
cd lab2_amm
rm contracts/Lock.sol
```

Read and try to understand the implemented smart contracts:

```
amm-lab/
├── contracts/         	   # Smart contracts folder
	├── TokenA.sol         # ERC-20 of TokenA
	├── TokenB.sol         # ERC-20 of TokenB
	└── SimpleAMM.sol      # AMM smart contract
```

### Step 2.2: Compile Contracts

Compile all contracts:

```bash
npx hardhat compile
```

You should see:
```bash
Compiled 8 Solidity files successfully
```

### Step 2.3: Deploy Contracts to Local Blockchain

Deploy the contracts:

```bash
npx hardhat run scripts/deploy.js --network localhost
```

You should see output showing the deployed contract addresses. **Save these addresses** - you'll need them later in this lab session.

Example output:
```
Deployer address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
User1 address: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
User2 address: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

TokenA deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3
TokenB deployed to: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
SimpleAMM deployed to: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0

Transferred 10,000 TokenA and TokenB to User1 and User2

=== Save these addresses ===
TokenA: 0x5FbDB2315678afecb367f032d93F642f64180aa3
TokenB: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
SimpleAMM: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
```

### Step 2.4: Add Initial Liquidity

Create a new file `scripts/addLiquidity.js`:

```javascript
const hre = require("hardhat");

async function main() {
  // Replace with your deployed addresses
  const TOKEN_A = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const TOKEN_B = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
  const AMM = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";

  const [deployer] = await hre.ethers.getSigners();

  // Get contract instances
  const tokenA = await hre.ethers.getContractAt("TokenA", TOKEN_A);
  const tokenB = await hre.ethers.getContractAt("TokenB", TOKEN_B);
  const amm = await hre.ethers.getContractAt("SimpleAMM", AMM);

  // Amount to add: 100 TokenA and 300 TokenB (ratio 1:3)
  const amountA = hre.ethers.parseUnits("100", 18);
  const amountB = hre.ethers.parseUnits("300", 18);

  console.log("Adding liquidity to AMM pool...");
  console.log("Amount A:", hre.ethers.formatUnits(amountA, 18));
  console.log("Amount B:", hre.ethers.formatUnits(amountB, 18));

  // Approve AMM to spend tokens
  await tokenA.approve(AMM, amountA);
  await tokenB.approve(AMM, amountB);
  console.log("Tokens approved\n");

  // Add liquidity
  const tx = await amm.addLiquidity(amountA, amountB);
  await tx.wait();
  console.log("Liquidity added successfully!\n");

  // Check reserves
  const [reserveA, reserveB] = await amm.getReserves();
  console.log("Pool Reserves:");
  console.log("Reserve A:", hre.ethers.formatUnits(reserveA, 18));
  console.log("Reserve B:", hre.ethers.formatUnits(reserveB, 18));
  console.log("K (constant):", hre.ethers.formatUnits(reserveA * reserveB / BigInt(1e18), 18));

  // Check price
  const [priceA, priceB] = await amm.getPrice();
  console.log("\nPrices:");
  console.log("Price of A in B:", hre.ethers.formatUnits(priceA, 18));
  console.log("Price of B in A:", hre.ethers.formatUnits(priceB, 18));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

**Important:** Replace the addresses in the script with your actual deployed addresses. You may play to tune the parameters in the script for better understanding the AMM smart contract.

Run the script:

```bash
npx hardhat run scripts/addLiquidity.js --network localhost
```

You should see:
```bash
Adding liquidity to AMM pool...
Amount A: 100.0
Amount B: 300.0
Tokens approved

Liquidity added successfully!

Pool Reserves:
Reserve A: 100.0
Reserve B: 300.0
K (constant): 30000.0

Prices:
Price of A in B: 3.0
Price of B in A: 0.333333333333333333
```

Try to read and understand the outputs on the **Hardhat Network terminal**:

```bash
eth_getTransactionByHash
eth_blockNumber
eth_feeHistory
eth_sendTransaction
  Contract call:       <UnrecognizedContract>
  Transaction:         0xab6e71a4f806e2ae72d64d65749cfb5056498d3031e5aaae39d4ddde7da0a5db
  From:                0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
  To:                  0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0
  Value:               0 ETH
  Gas used:            228595 of 16777216
  Block #10:           0xc3cc9546891a4563dc2a866de55e30df2f6d2817a5b494ebd3aa2db4cd35e1b3

eth_getTransactionByHash
eth_getTransactionReceipt
eth_call
  Contract call:       <UnrecognizedContract>
  From:                0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
  To:                  0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0

eth_call
  Contract call:       <UnrecognizedContract>
  From:                0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
  To:                  0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0
```

**Congratulations!** You've created an AMM pool with initial liquidity. The pool now has:

- 100 TokenA
- 300 TokenB
- Price: 1 TokenA = 3 TokenB



## Task 3: Experience Slippage and Sandwich Attack

Now we'll observe how slippage works and simulate a sandwich attack.

### Step 3.1: Understanding Slippage

**Slippage** is the difference between the expected price and the execution price. It increases with trade size.

Let's see this in action. Create `scripts/testSlippage.js`:

```javascript
const hre = require("hardhat");

async function main() {
  // Replace with your deployed addresses
  const TOKEN_A = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const TOKEN_B = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
  const AMM = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";

  const [deployer, user1] = await hre.ethers.getSigners();

  // Get contract instances (connect as user1)
  const tokenA = await hre.ethers.getContractAt("TokenA", TOKEN_A, user1);
  const tokenB = await hre.ethers.getContractAt("TokenB", TOKEN_B, user1);
  const amm = await hre.ethers.getContractAt("SimpleAMM", AMM, user1);

  console.log("=== Slippage Demonstration ===\n");

  // Get initial state
  let [reserveA, reserveB] = await amm.getReserves();
  console.log("Initial Pool State:");
  console.log("Reserve A:", hre.ethers.formatUnits(reserveA, 18));
  console.log("Reserve B:", hre.ethers.formatUnits(reserveB, 18));
  console.log("Initial Price (B per A):", hre.ethers.formatUnits(reserveB * BigInt(1e18) / reserveA, 18));
  console.log();

  // Test different swap amounts
  const swapAmounts = ["5", "10", "20", "50"];

  console.log("=== Testing Different Swap Sizes ===\n");

  for (const amount of swapAmounts) {
    const amountIn = hre.ethers.parseUnits(amount, 18);
    const amountOut = await amm.getAmountOut(amountIn, reserveA, reserveB);
    
    // Calculate effective price
    const effectivePrice = (amountOut * BigInt(1e18)) / amountIn;
    const startPrice = (reserveB * BigInt(1e18)) / reserveA;
    const priceImpact = ((startPrice - effectivePrice) * BigInt(100)) / startPrice;

    console.log(`Swap ${amount} TokenA:`);
    console.log(`  You get: ${hre.ethers.formatUnits(amountOut, 18)} TokenB`);
    console.log(`  Effective price: ${hre.ethers.formatUnits(effectivePrice, 18)} B per A`);
    console.log(`  Price impact: ${priceImpact.toString()}%`);
    console.log();
  }

  console.log("=== Executing a 10 TokenA Swap ===\n");

  // Now actually execute a swap
  const swapAmount = hre.ethers.parseUnits("10", 18);
  const expectedOut = await amm.getAmountOut(swapAmount, reserveA, reserveB);
  
  // Approve and swap
  await tokenA.approve(AMM, swapAmount);
  
  // Set slippage tolerance to 1% (minAmountOut = 99% of expected)
  const minAmountOut = (expectedOut * BigInt(99)) / BigInt(100);
  
  console.log("Expected output:", hre.ethers.formatUnits(expectedOut, 18), "TokenB");
  console.log("Min output (1% slippage):", hre.ethers.formatUnits(minAmountOut, 18), "TokenB");
  
  const tx = await amm.swapAforB(swapAmount, minAmountOut);
  await tx.wait();
  console.log("Swap executed!\n");

  // Check new state
  [reserveA, reserveB] = await amm.getReserves();
  const newPrice = hre.ethers.formatUnits(reserveB * BigInt(1e18) / reserveA, 18);
  
  console.log("New Pool State:");
  console.log("Reserve A:", hre.ethers.formatUnits(reserveA, 18));
  console.log("Reserve B:", hre.ethers.formatUnits(reserveB, 18));
  console.log("New Price (B per A):", newPrice);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

Run the script:

```bash
npx hardhat run scripts/testSlippage.js --network localhost
```

**Observe:** As swap size increases, price impact (slippage) increases significantly.

### Step 3.2: Simulate Sandwich Attack

Now let's simulate a sandwich attack. Create `scripts/sandwhichAttack.js`:

```javascript
const hre = require("hardhat");

async function main() {
  // Replace with your deployed addresses
  const TOKEN_A = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const TOKEN_B = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
  const AMM = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";

  const [deployer, user1, attacker] = await hre.ethers.getSigners();

  console.log("=== Sandwich Attack Simulation ===\n");
  console.log("Victim: User1", user1.address);
  console.log("Attacker:", attacker.address);
  console.log();

  // Get contract instances
  const tokenA_victim = await hre.ethers.getContractAt("TokenA", TOKEN_A, user1);
  const tokenB_victim = await hre.ethers.getContractAt("TokenB", TOKEN_B, user1);
  const amm_victim = await hre.ethers.getContractAt("SimpleAMM", AMM, user1);

  const tokenA_attacker = await hre.ethers.getContractAt("TokenA", TOKEN_A, attacker);
  const tokenB_attacker = await hre.ethers.getContractAt("TokenB", TOKEN_B, attacker);
  const amm_attacker = await hre.ethers.getContractAt("SimpleAMM", AMM, attacker);

  // Transfer tokens to attacker
  const attackerFunds = hre.ethers.parseUnits("5000", 18);
  await tokenA_victim.transfer(attacker.address, attackerFunds);
  await tokenB_victim.transfer(attacker.address, attackerFunds);
  console.log("Attacker funded with 5000 TokenA and TokenB\n");

  // Get initial state
  let [reserveA, reserveB] = await amm_victim.getReserves();
  const initialPrice = (reserveB * BigInt(1e18)) / reserveA;
  console.log("Initial Pool State:");
  console.log("Reserve A:", hre.ethers.formatUnits(reserveA, 18));
  console.log("Reserve B:", hre.ethers.formatUnits(reserveB, 18));
  console.log("Price (B per A):", hre.ethers.formatUnits(initialPrice, 18));
  console.log();

  // Victim wants to swap 10 TokenA for TokenB
  const victimSwap = hre.ethers.parseUnits("10", 18);
  console.log("🎯 VICTIM plans to swap 10 TokenA for TokenB\n");

  // Calculate what victim SHOULD get without attack
  const expectedVictimOut = await amm_victim.getAmountOut(victimSwap, reserveA, reserveB);
  console.log("Without attack, victim would get:", hre.ethers.formatUnits(expectedVictimOut, 18), "TokenB\n");

  // ===== SANDWICH ATTACK BEGINS =====
  console.log("💰 ATTACKER detects victim's transaction in mempool!\n");

  // Track attacker's initial balance
  const attackerInitialB = await tokenB_attacker.balanceOf(attacker.address);

  // === Step 1: FRONT-RUN ===
  console.log("--- Step 1: Front-run (Attacker buys first) ---");
  const attackerFrontRun = hre.ethers.parseUnits("15", 18); // Attacker buys 15 TokenA worth
  
  await tokenA_attacker.approve(AMM, attackerFrontRun);
  const frontRunOut = await amm_attacker.getAmountOut(attackerFrontRun, reserveA, reserveB);
  
  const tx1 = await amm_attacker.swapAforB(attackerFrontRun, 0);
  await tx1.wait();
  
  console.log("Attacker swaps 15 TokenA for", hre.ethers.formatUnits(frontRunOut, 18), "TokenB");
  
  [reserveA, reserveB] = await amm_victim.getReserves();
  const priceAfterFrontRun = (reserveB * BigInt(1e18)) / reserveA;
  console.log("Price after front-run:", hre.ethers.formatUnits(priceAfterFrontRun, 18), "B per A");
  console.log();

  // === Step 2: VICTIM'S TRANSACTION ===
  console.log("--- Step 2: Victim's transaction executes ---");
  
  await tokenA_victim.approve(AMM, victimSwap);
  const victimActualOut = await amm_victim.getAmountOut(victimSwap, reserveA, reserveB);
  
  const tx2 = await amm_victim.swapAforB(victimSwap, 0);
  await tx2.wait();
  
  console.log("Victim swaps 10 TokenA for", hre.ethers.formatUnits(victimActualOut, 18), "TokenB");
  console.log("Victim LOSS due to sandwich:", 
    hre.ethers.formatUnits(expectedVictimOut - victimActualOut, 18), "TokenB");
  
  [reserveA, reserveB] = await amm_victim.getReserves();
  const priceAfterVictim = (reserveB * BigInt(1e18)) / reserveA;
  console.log("Price after victim:", hre.ethers.formatUnits(priceAfterVictim, 18), "B per A");
  console.log();

  // === Step 3: BACK-RUN ===
  console.log("--- Step 3: Back-run (Attacker sells) ---");
  
  // Attacker sells the TokenB they got
  await tokenB_attacker.approve(AMM, frontRunOut);
  const backRunOut = await amm_attacker.getAmountOut(frontRunOut, reserveB, reserveA);
  
  const tx3 = await amm_attacker.swapBforA(frontRunOut, 0);
  await tx3.wait();
  
  console.log("Attacker swaps", hre.ethers.formatUnits(frontRunOut, 18), "TokenB for", 
    hre.ethers.formatUnits(backRunOut, 18), "TokenA");
  
  [reserveA, reserveB] = await amm_victim.getReserves();
  const finalPrice = (reserveB * BigInt(1e18)) / reserveA;
  console.log("Final price:", hre.ethers.formatUnits(finalPrice, 18), "B per A");
  console.log();

  // Calculate attacker profit
  const attackerProfit = backRunOut - attackerFrontRun;
  console.log("=== ATTACK COMPLETE ===");
  console.log("💰 Attacker PROFIT:", hre.ethers.formatUnits(attackerProfit, 18), "TokenA");
  console.log("😢 Victim LOSS:", hre.ethers.formatUnits(expectedVictimOut - victimActualOut, 18), "TokenB");
  console.log();
  console.log("How it works:");
  console.log("1. Attacker front-runs victim by buying first → Price increases");
  console.log("2. Victim's trade executes at worse price → Victim pays more");
  console.log("3. Attacker back-runs by selling at inflated price → Attacker profits");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

Run the sandwich attack simulation:

```bash
npx hardhat run scripts/sandwhichAttack.js --network localhost
```

**Observe:**

1. The attacker front-runs the victim's transaction.
2. The victim gets a worse price than expected.
3. The attacker profits by back-running (selling at the inflated price).



## Understanding What You've Learned

### Constant Product Formula (x × y = k)

In your AMM:
- When someone swaps TokenA for TokenB, the product of reserves stays constant.
- Formula: `reserveA × reserveB = k` (constant)
- Price changes based on the ratio of reserves.

**Example from your pool:**
- Initial: 100 TokenA × 300 TokenB = 30,000 (k)
- After swap: Different reserves, but product ≈ 30,000

### Slippage

**Why does slippage occur?**
- Large trades move the price significantly.
- The bigger your trade, the worse the price you get.
- This is unavoidable in constant product AMMs.

**Slippage protection:**
- You set a `minAmountOut` parameter.
- If actual `output < minAmountOut`, transaction reverts.
- This prevents "unexpected slippage".

### Sandwich Attack

**Attack mechanics:**
1. **Attacker monitors mempool** - sees your pending transaction
2. **Front-run** - attacker buys first (with higher gas fee)
3. **Your transaction executes** - at a worse price
4. **Back-run** - attacker sells at the inflated price

**Key insight from lecture:**

> "This one is harmful for users! If you are a miner, you heard a transaction where someone intends to exchange for 10 asset Y from the pool, what will you do?"

The attacker exploits the **predictable price impact** of your trade.

### Arbitrage vs Sandwich Attack

From the lecture:
- **Arbitrage** is neutral - it aligns prices across markets
- **Sandwich attacks** are harmful - they exploit individual users for profit



## Lab Questions & Exercises

### Exercise 1: Calculate Slippage

Based on the lecture formula, if the pool has:
- Reserve A = 100
- Reserve B = 300
- k = 30,000

**Question:** How much TokenB do you receive if you swap 10 TokenA?

Use the formula from the smart contract:
```
amountOut = (amountIn × 998 × reserveOut) / (reserveIn × 1000 + amountIn × 998)
```

% **Hide Answer** %

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

%%%%%%%%%%

**Answer:**

```
amountOut = (10 × 998 × 300) / (100 × 1000 + 10 × 998)
          = 2,994,000 / 109,980
          = 27.218 TokenB
```

**Price impact:** Initial price was 3.0 B per A, but you got 2.7218 B per A (9.3% slippage!)



### Exercise 2: Experiment with Pool Size

Modify `addLiquidity.js` to create pools with different sizes:
- Small pool: 10 TokenA, 30 TokenB
- Large pool: 1000 TokenA, 3000 TokenB

**Question:** How does pool size affect slippage for the same trade?



### Exercise 3: Defend Against Sandwich Attacks

Modify `testSlippage.js` to add proper slippage protection:
- Set `minAmountOut` to 95% of expected output (5% slippage tolerance)
- Try to execute the sandwich attack again
- What happens?



## Troubleshooting

### Problem: "Transaction reverted"

**Solution:** Check if you have approved the AMM to spend your tokens:

```javascript
await tokenA.approve(AMM_ADDRESS, amount);
```

### Problem: "Insufficient liquidity"

**Solution:** Make sure you've run the `addLiquidity.js` script first.

### Problem: "Cannot find module"

**Solution:** Install dependencies:
```bash
npm install
```

### Problem: Hardhat node not running

**Solution:** Start the node in a separate terminal:
```bash
npx hardhat node
```



## Summary

In this lab, you:

1. ✅ **Deployed a private blockchain** using Hardhat Network
2. ✅ **Created an AMM pool** implementing the constant product formula (x × y = k)
3. ✅ **Experienced slippage** and understood how trade size affects price impact
4. ✅ **Simulated a sandwich attack** and observed how attackers exploit MEV

**Key Takeaways:**

- AMMs use mathematical formulas to determine prices automatically
- Slippage increases with trade size due to the constant product formula
- Sandwich attacks exploit transaction ordering in the mempool
- Slippage protection (minAmountOut) helps prevent unexpected losses

**Next Steps:**

- Experiment with different fee rates in the AMM
- Try implementing a different AMM formula (constant sum, constant mean)
- Research how Layer 2 solutions reduce MEV attacks
- Explore tools like Flashbots that provide MEV protection



## Further Readings

- Uniswap V2 Whitepaper: https://uniswap.org/whitepaper.pdf
- Hardhat Documentation (**Note: We are using hardhat 2**): https://hardhat.org/docs
- OpenZeppelin Contracts: https://docs.openzeppelin.com/contracts

