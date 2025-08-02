# Contract-Based Permit System Architecture

## Overview

Instead of users granting permits to the backend wallet, they now grant permits to a smart contract that executes swaps atomically. This is more secure and decentralized.

## Architecture Flow

### 1. User Setup

- User connects external wallet (MetaMask, etc.)
- User signs EIP-2612 permit granting permission to **PermitAutoBuyContract** (not backend wallet)
- Permit includes USDC amount, deadline, and signature (v, r, s)
- Contract address as spender: `0x...` (deployed PermitAutoBuyContract)

### 2. Auto-Buy Execution

When auto-buy triggers:

1. Backend calls `PermitAutoBuyContract.executePermitAutoBuy()`
2. Contract validates user limits (daily, like/recast amounts)
3. Contract executes permit to transfer USDC from user to contract
4. Contract approves KyberSwap router for USDC spending
5. Contract calls KyberSwap router with swap data
6. Tokens are sent directly to user's wallet
7. Contract emits event for tracking

### 3. Security Benefits

- **No backend wallet custody**: Backend never holds user funds
- **Atomic execution**: Permit + swap happens in single transaction
- **User control**: Users can revoke permits anytime
- **Transparent**: All logic is on-chain and verifiable

## Smart Contract

```solidity
contract PermitAutoBuyContract {
    function executePermitAutoBuy(
        address user,
        uint256 usdcAmount,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s,  // Permit signature
        bytes calldata swapData,        // KyberSwap transaction data
        string calldata actionType      // "like" or "recast"
    ) external onlyOwner {
        // 1. Validate limits
        // 2. Execute permit
        // 3. Transfer USDC from user to contract
        // 4. Approve router
        // 5. Execute swap
        // 6. Tokens go directly to user
    }
}
```

## Frontend Changes

Users now sign permits for the contract address instead of backend wallet:

```typescript
const PERMIT_CONTRACT = "0x..."; // PermitAutoBuyContract address

const permit = await signUSDCPermit(
  walletAddress,
  PERMIT_CONTRACT, // <-- Contract, not backend wallet
  amount
);
```

## Backend Changes

- Remove relayer wallet transfer logic
- Call contract's `executePermitAutoBuy()` function
- Contract handles all USDC transfers and swaps
- Backend only pays gas for contract call

## Deployment

1. Deploy `PermitAutoBuyContract.sol`
2. Update frontend to use contract address for permits
3. Update backend to call contract instead of relayer
4. Test with small amounts first

This architecture is more secure, transparent, and follows DeFi best practices!
