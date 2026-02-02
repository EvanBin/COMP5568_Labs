# **Lab 1: Smart Contracts for DeFi**

> COMP 5568 - Decentralized Finance (Semester 2, 2025/26)
>
> The Hong Kong Polytechnic University

In this lab, you will learn how to use the online IDE to build, test, and deploy your first smart contract. You will build an ERC-20 token contract in `Remix`, then you will test the transaction functionality in `Remix VM`.



## Task 1: Deploy ERC-20 Token Contract

- Open the web3 online IDE: https://remix.ethereum.org/
- Click `Create a new Workspace` on the upper right.
- Create a new Workspace from `ERC-20` template, name the token name to: `AwesomeToken`
- Copy the following code to `AwesomeToken.sol`. You may explore the functions by reading the detailed comments.
  - Implement the logic in place of the **@TODO** on lines 51 to change the contract owner according to the input `newOwner`. 


```solidity
// SPDX-License-Identifier: MIT
// This tells the compiler which version of Solidity to use.
// ^0.8.27 means "version 0.8.27 or newer within the 0.8.x series".
pragma solidity ^0.8.27;

// We import the ERC20 contract from OpenZeppelin. ERC20 is a standard interface for tokens on Ethereum. It already includes functions like transfer(), balanceOf(), approve(), etc.
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Our contract "AwesomeToken" inherits from ERC20. This means it automatically gets all ERC20 functions and state variables.
contract AwesomeToken is ERC20 {
	// "owner" stores the address that has special privileges (can mint tokens).
	// "public" means Solidity auto-creates a getter function so anyone can read it.
	address public owner;
	
	// A modifier is reusable code that runs BEFORE a function executes.
	// "onlyOwner" checks if the person calling the function is the owner. If msg.sender is NOT the owner, the transaction stops (reverts) with the error message.
	// The underscore represents where the actual function code will run. If the require() check passes, execution continues to the function body.
	modifier onlyOwner() {
		require(msg.sender == owner, "Not the owner!");
		_;
	}

	// The constructor runs ONLY ONCE when the contract is deployed.
    constructor() ERC20("AwesomeToken", "ASM") {
        owner = msg.sender;
        
        // "_mint" is an internal ERC20 function that creates new tokens.
		// Parameters:
		//   1. msg.sender - WHO receives the tokens (the deployer's wallet)
		//   2. amount - HOW MANY tokens to create
		//
		// Why multiply by 10 ** decimals()?
		// - ERC20 tokens use "decimals" (default is 18) to handle fractions.
		// - To create 1,000,000 tokens, we calculate: 1000000 * 10^18
		_mint(msg.sender, 1000000 * 10 ** decimals());
	}
	
	// This function allows the owner to create NEW tokens after deployment. This increases totalSupply and the balance of the "to" address.
    // Example: To mint 500 tokens to address 0x123..., call: mint(0x123..., 500 * 10**18)
	function mint(address to, uint256 amount) public onlyOwner {
		_mint(to, amount);
	}
	
	// This function lets the current owner transfer control to someone else.
	function transferOwnership(address newOwner) public onlyOwner {
	
	// Security check: prevent setting owner to the zero address (0x0000...0000).
	// The zero address is used to represent "no address" and cannot sign transactions. If ownership is transferred to zero address, the contract becomes ownerless forever!
	require(newOwner != address(0), "New owner is zero address.");
	
	// @TODO: Update the owner state variable to the new owner's address.
    
    //
    
    }
	
    // INHERITED FUNCTIONS (automatically available from ERC20)
    // You DON'T need to write these - they come from the ERC20 import:
    //
    // - transfer(address to, uint256 amount)
    //   Send tokens from YOUR wallet to another address.
    //   Example: transfer(0xABC..., 100 * 10**18) sends 100 tokens to 0xABC...
    //
    // - approve(address spender, uint256 amount)
    //   Give permission to "spender" to transfer tokens FROM your wallet.
    //   Used for decentralized exchanges and smart contracts.
    //
    // - transferFrom(address from, address to, uint256 amount)
    //   If you have approval, transfer tokens FROM someone else's wallet.
    //
    // - balanceOf(address account)
    //   Check how many tokens an address owns.
    //
    // - totalSupply()
    //   Returns the total number of tokens that exist.
    //
    // - allowance(address owner, address spender)
    //   Check how many tokens "spender" is allowed to transfer from "owner".
}

```

- Compile `AwesomeToken.sol` with `Remix`.
- Deploy your `AwesomeToken` contract to `Remix VM (Osaka)` with account: `0x5B38Da6a701c568545dCfcB03FcB875f56beddC4`.



## Task 2: Transfer the ERC-20 Token

You may use the addresses for all the followings tasks.

### Account Address Info

```json
{
    "Account1": "0x5B38Da6a701c568545dCfcB03FcB875f56beddC4",
    "Account2": "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2",
    "Account3": "0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db",
}
```

### Direct Token Transfer

- Use `Account1` for following operations.
- Use `transfer` function:
  - Transfer `100` units `AwesomeToken` to account `Account2`.
  - Try to read and understand the logs returned by the `Remix VM`. For example:

```json
[
	{
		"from": "0xf8e81D47203A594245E36C48e151709F0C19fBe8",
		"topic": "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
		"event": "Transfer",
		"args": {
			"0": "0x5B38Da6a701c568545dCfcB03FcB875f56beddC4",
			"1": "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2",
			"2": "100"
		}
	}
]
```

- Use `balanceOf` function:
  - Check the balance of `AwesomeToken`  of account `Account1` and `Account2`.
  - Try to read and understand the decoded output returned by the `Remix VM`. For example:

```json
{
	"0": "uint256: 100"
}
```

### Approve and Allowance

- Use `Account2` for following operations:
  - Use `approve` function:
    - Grant 1000 `AwesomeToken` to `Account1`.
  - Use `allowance` function:
    - Check the allowance of `Account2` (owner) to `Account1` (spender).
  - Why is this allowance approved despite the fact that `Account2`’s balance is lower?
- Use `Account1` for following operations:
  - Use `transferFrom` function:
    - Transfer 1000 `AwesomeToken` from `Account2` to `Account1`.
    - Why does the transaction fail? Check the error log.
  - Use `transferFrom` function:
    - Transfer 40 `AwesomeToken` from `Account2` to `Account1`.
    - Check the balance of `Account1`, `Account2`, and the remaining allowance.
  - Use `transferFrom` function:
    - Transfer 40 `AwesomeToken` from `Account2` to `Account3`.
    - Check the balance of all three addresses and the remaining allowance.
- Use `Account3` for following operations:
  - Use `transferFrom` function:
    - Transfer 20 `AwesomeToken` from `Account2` to `Account1`.
    - Why this doesn’t work?
