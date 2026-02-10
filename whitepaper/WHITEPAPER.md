# Web3 ESOP -- Technical Whitepaper

> On-chain Employee Stock Option Plan built on Ethereum

**Version:** 1.0
**Solidity:** 0.8.28
**License:** MIT

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Problem Statement](#2-problem-statement)
3. [Solution Overview](#3-solution-overview)
4. [System Architecture](#4-system-architecture)
5. [Smart Contract Specification](#5-smart-contract-specification)
   - 5.1 [ESOPToken](#51-esoptoken)
   - 5.2 [ESOPOptionNFT](#52-esopoptionnft)
   - 5.3 [VestingMath Library](#53-vestingmath-library)
6. [Grant Lifecycle](#6-grant-lifecycle)
7. [Vesting Model](#7-vesting-model)
8. [Exercise Mechanics](#8-exercise-mechanics)
9. [Termination and Forfeiture](#9-termination-and-forfeiture)
10. [Soulbound Transfer and Wallet Recovery](#10-soulbound-transfer-and-wallet-recovery)
11. [Access Control Model](#11-access-control-model)
12. [Security Model](#12-security-model)
13. [Storage Layout and Gas Optimization](#13-storage-layout-and-gas-optimization)
14. [Events and Indexing](#14-events-and-indexing)
15. [Error Handling](#15-error-handling)
16. [Testing Strategy](#16-testing-strategy)
17. [Deployment](#17-deployment)
18. [Risks and Considerations](#18-risks-and-considerations)

---

## 1. Introduction

Employee Stock Option Plans (ESOPs) are a cornerstone of startup compensation. They align employee incentives with company growth by granting the right to purchase company equity at a predetermined price after a vesting period.

Traditional ESOPs are managed through paper agreements, spreadsheets, and centralized cap-table software. These systems are opaque to employees, prone to administrative error, and expensive to audit.

Web3 ESOP moves the entire option lifecycle on-chain: granting, vesting, exercising, termination, and cleanup are governed by immutable smart contracts. Employees hold their option grants as non-transferable (soulbound) NFTs, and all state transitions emit verifiable events.

---

## 2. Problem Statement

| Problem | Impact |
|---|---|
| **Opaque vesting** | Employees cannot independently verify how many options have vested or what they are worth. |
| **Administrative error** | Manual cap-table management leads to miscalculations, duplicate grants, or lost records. |
| **Costly audits** | Verifying option state requires access to internal systems and manual reconciliation. |
| **No self-service exercise** | Exercising typically requires HR coordination, paperwork, and manual payment processing. |
| **Key-person risk** | If the company's cap-table administrator leaves, institutional knowledge may be lost. |
| **Lack of trust** | Employees must trust that the company will honor the terms encoded in their offer letter. |

---

## 3. Solution Overview

Web3 ESOP replaces the traditional cap-table with two cooperating smart contracts:

1. **ESOPOptionNFT** (ERC-721) -- Each option grant is a soulbound NFT that stores the grant terms (strike price, vesting schedule, total options) directly on-chain. The employee holds this NFT in their wallet.

2. **ESOPToken** (ERC-20) -- A capped fungible token representing company equity. Tokens are minted only when an employee exercises options by paying the strike price in USDC.

Together, they provide:

- **Transparency** -- Any party can read grant terms and vesting state from the blockchain.
- **Self-service exercise** -- Employees exercise directly from their wallet, paying USDC and receiving tokens atomically.
- **Immutable terms** -- Once a grant is created, its core parameters (strike price, vesting schedule, total options) cannot be altered.
- **Auditability** -- Every state change emits an indexed event, creating a permanent audit trail.

---

## 4. System Architecture

```
                          +-----------------+
                          |   Company Admin  |
                          |   (Multi-Sig)    |
                          +--------+--------+
                                   |
                    Roles: DEFAULT_ADMIN_ROLE
                           ADMIN_ROLE
                           GRANTOR_ROLE
                                   |
          +------------------------+------------------------+
          |                                                 |
+---------v---------+                            +----------v----------+
|   ESOPOptionNFT   |--------- MINTER_ROLE ----->|     ESOPToken       |
|   (ERC-721)       |                            |     (ERC-20)        |
|                   |                            |                     |
| - Grant storage   |                            | - Capped supply     |
| - Vesting logic   |                            | - Mint on exercise  |
| - Exercise flow   |                            +---------------------+
| - Soulbound       |
+---------+---------+
          |
          | exercise(tokenId, amount)
          |
  +-------v--------+         +-----------+
  |   Employee      |-------->|   USDC    |-------> Treasury
  |   Wallet        | pays    | (ERC-20)  |
  +----------------+         +-----------+
```

### Contract Relationships

| From | To | Relationship |
|---|---|---|
| ESOPOptionNFT | ESOPToken | Calls `mint()` when options are exercised. Holds `MINTER_ROLE`. |
| ESOPOptionNFT | USDC | Calls `safeTransferFrom()` to collect strike price payment from employee. |
| Employee | ESOPOptionNFT | Holds soulbound NFT. Calls `exercise()` to convert options to tokens. |
| Admin | ESOPOptionNFT | Grants options, terminates grants, approves wallet recovery transfers. |
| Admin | ESOPToken | Holds `DEFAULT_ADMIN_ROLE` to manage role assignments. |

---

## 5. Smart Contract Specification

### 5.1 ESOPToken

**File:** `src/ESOPToken.sol`
**Inherits:** `ERC20`, `ERC20Capped`, `AccessControl`

A standard ERC-20 token with a hard supply cap. No tokens exist at deployment -- they are minted exclusively by the ESOPOptionNFT contract when employees exercise options.

#### Constructor

```solidity
constructor(
    string memory name,     // Token name (e.g., "ESOP Token")
    string memory symbol,   // Token symbol (e.g., "ESOP")
    uint256 maxSupply,      // Hard cap in wei (18 decimals)
    address admin           // Receives DEFAULT_ADMIN_ROLE
)
```

#### Roles

| Role | Holder | Permission |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Company multi-sig | Can grant/revoke all roles |
| `MINTER_ROLE` | ESOPOptionNFT contract | Can mint tokens up to the cap |

#### Functions

| Function | Access | Description |
|---|---|---|
| `mint(address to, uint256 amount)` | `MINTER_ROLE` | Mints tokens. Reverts if `totalSupply + amount > cap`. |
| `cap()` | Public | Returns the maximum supply cap. |

#### Key Properties

- **Immutable cap** -- Set at construction, cannot be changed.
- **No burn** -- No burn function is exposed; tokens are permanent once minted.
- **No pre-mint** -- Supply starts at zero.
- **Standard ERC-20** -- Fully compatible with wallets, DEXs, and DeFi protocols.

---

### 5.2 ESOPOptionNFT

**File:** `src/ESOPOptionNFT.sol`
**Inherits:** `ERC721`, `ERC721Enumerable`, `AccessControl`, `ReentrancyGuard`, `Pausable`, `IESOPOptionNFT`

The core contract. Each NFT represents a single option grant and stores the full vesting schedule on-chain.

#### Constructor

```solidity
constructor(
    string memory name,          // NFT collection name
    string memory symbol,        // NFT collection symbol
    address esopTokenAddress,    // ESOPToken contract (immutable)
    address usdcAddress,         // USDC contract (immutable)
    address treasury,            // Initial USDC treasury (mutable)
    address admin                // Receives all admin roles
)
```

All address parameters are validated against `address(0)`. The `esopToken` and `usdc` references are stored as immutable to save gas.

#### OptionGrant Struct

Each NFT's on-chain state is stored in the following struct, packed into 3 storage slots:

```
Slot 1 (256 bits):
  ├── totalOptions        uint128   Total options granted
  └── exercisedOptions    uint128   Options already exercised

Slot 2 (256 bits):
  ├── strikePrice         uint128   Price per option in USDC (6 decimals)
  ├── vestingStart        uint64    Vesting start timestamp
  └── cliffDuration       uint64    Cliff period in seconds

Slot 3 (200 bits):
  ├── vestingDuration     uint64    Total vesting period in seconds
  ├── terminationTimestamp uint64   When employment ended (0 if active)
  ├── postTerminationWindow uint64  Exercise window after termination
  └── terminated          bool      Whether grant has been terminated
```

#### Functions -- Grant Management

| Function | Access | Description |
|---|---|---|
| `grantOptions(employee, totalOptions, strikePrice, vestingStart, cliffDuration, vestingDuration, postTerminationWindow)` | `GRANTOR_ROLE` | Creates a new option grant, mints a soulbound NFT to the employee. Returns the `tokenId`. |

**Validation rules:**
- `employee` must not be `address(0)`
- `totalOptions`, `strikePrice`, `vestingDuration`, `postTerminationWindow` must be > 0
- `vestingDuration` must be >= `cliffDuration`

#### Functions -- Exercise

| Function | Access | Description |
|---|---|---|
| `exercise(tokenId, amount)` | NFT holder | Exercises `amount` vested options. Transfers USDC to treasury. Mints ESOP tokens to the employee. |

**Modifiers:** `nonReentrant`, `whenNotPaused`

**Exercise flow (detailed in Section 8):**
1. Verify caller owns the NFT
2. Check grant is not expired
3. Calculate vested and exercisable amounts
4. Validate requested amount
5. Calculate USDC cost
6. Update state (CEI pattern)
7. Transfer USDC from employee to treasury
8. Mint ESOP tokens to employee

#### Functions -- Termination

| Function | Access | Description |
|---|---|---|
| `terminateGrant(tokenId)` | `ADMIN_ROLE` | Terminates the grant. Freezes vesting at the current timestamp. Starts the post-termination exercise window. |

#### Functions -- Burn

| Function | Access | Description |
|---|---|---|
| `burnGrant(tokenId)` | Holder or `ADMIN_ROLE` | Burns the NFT and deletes grant data. Only allowed when the grant is in a terminal state (see Section 6). |

**Burn conditions (any one must be true):**
1. All options have been exercised (`exercisedOptions == totalOptions`)
2. Grant is terminated AND the post-termination window has closed
3. Grant is terminated AND all vested options at termination have been exercised

#### Functions -- Wallet Recovery

| Function | Access | Description |
|---|---|---|
| `approveTransfer(tokenId, to)` | `ADMIN_ROLE` | Approves a transfer of the soulbound NFT to a new wallet address. |
| `revokeTransferApproval(tokenId)` | `ADMIN_ROLE` | Revokes a previously set transfer approval. |
| `executeApprovedTransfer(tokenId)` | Holder or `ADMIN_ROLE` | Executes the approved transfer. Grant data is preserved. |

#### Functions -- View

| Function | Returns | Description |
|---|---|---|
| `getGrant(tokenId)` | `OptionGrant` | Full grant struct |
| `getVestedOptions(tokenId)` | `uint128` | Currently vested options (capped at termination time if terminated) |
| `getExercisableOptions(tokenId)` | `uint128` | Vested minus exercised (0 if expired) |
| `getExerciseCost(tokenId, amount)` | `uint256` | USDC cost to exercise `amount` options |
| `isGrantExpired(tokenId)` | `bool` | True if terminated and post-termination window has closed |
| `isGrantFullyExercised(tokenId)` | `bool` | True if `exercisedOptions == totalOptions` |

#### Functions -- Admin

| Function | Access | Description |
|---|---|---|
| `setUSDCTreasury(newTreasury)` | `ADMIN_ROLE` | Updates the USDC payment destination |
| `pause()` | `ADMIN_ROLE` | Pauses exercise operations |
| `unpause()` | `ADMIN_ROLE` | Unpauses exercise operations |

---

### 5.3 VestingMath Library

**File:** `src/libraries/VestingMath.sol`

A stateless library with pure functions for vesting arithmetic. Extracted to keep the main contract focused and to enable independent unit and fuzz testing.

#### `calculateVested`

```
calculateVested(totalOptions, vestingStart, cliffDuration, vestingDuration, timestamp) -> vested
```

| Condition | Result |
|---|---|
| `timestamp < vestingStart` | 0 |
| `elapsed < cliffDuration` | 0 |
| `elapsed >= vestingDuration` | `totalOptions` |
| Otherwise | `totalOptions * elapsed / vestingDuration` (linear) |

Intermediate arithmetic uses `uint256` to prevent overflow on the multiplication.

#### `calculateExercisable`

```
calculateExercisable(vested, exercised) -> exercisable
```

Returns `vested - exercised`, or 0 if `vested <= exercised`.

#### `calculateExerciseCost`

```
calculateExerciseCost(optionsToExercise, strikePrice) -> cost
```

Returns `optionsToExercise * strikePrice` as a `uint256`. The result is in USDC's smallest unit (6 decimals). For example, exercising 100 options at a $1.00 strike price: `100 * 1_000_000 = 100_000_000` (100 USDC).

---

## 6. Grant Lifecycle

A grant progresses through the following states:

```
  [Created]
      |
      | Time passes, options vest linearly after cliff
      v
  [Vesting]
      |
      +------- employee exercises -------> [Partially Exercised]
      |                                          |
      |                                          | all options exercised
      |                                          v
      |                                    [Fully Exercised] --> burnGrant()
      |
      +------- admin terminates ---------> [Terminated]
                                               |
                                  +------------+------------+
                                  |                         |
                           exercises within           window closes
                           post-term window
                                  |                         |
                                  v                         v
                          [Terminated +              [Expired] --> burnGrant()
                           Partially Exercised]
                                  |
                                  | all vested exercised
                                  v
                            [Terminal] --> burnGrant()
```

### State Definitions

| State | Conditions |
|---|---|
| **Created** | NFT minted, `terminated == false`, `exercisedOptions == 0` |
| **Vesting** | Active grant, cliff has passed, options are vesting linearly |
| **Partially Exercised** | `exercisedOptions > 0` but `< totalOptions` |
| **Fully Exercised** | `exercisedOptions == totalOptions` |
| **Terminated** | `terminated == true`, post-termination window is open |
| **Expired** | `terminated == true`, `block.timestamp > terminationTimestamp + postTerminationWindow` |
| **Burnable** | Fully exercised, OR expired, OR terminated with all vested exercised |

---

## 7. Vesting Model

### Linear Vesting with Cliff

The system implements a standard linear vesting schedule with a cliff:

```
Options
Vested
  ^
  |                                    _______________
  |                                   /
  |                                  /
  |                                 /
  |                                /
  |                               /
  |         cliff               /
  |   (nothing vests)          /
  |___________________________|
  |
  +----+---+---+---+---+---+---+---+---> Time
       0   1   2   3   4   5   6   7
           ^                       ^
         cliff                  full
         ends                  vesting
```

**Parameters:**
- `vestingStart` -- Unix timestamp when the vesting clock begins (typically the hire date or grant date).
- `cliffDuration` -- Period (in seconds) after `vestingStart` during which zero options are vested. Common value: 365 days (1 year).
- `vestingDuration` -- Total period (in seconds) for all options to vest. Common value: 1460 days (4 years). Must be >= `cliffDuration`.

**Formula:**

```
elapsed = timestamp - vestingStart

if elapsed < cliffDuration:
    vested = 0
elif elapsed >= vestingDuration:
    vested = totalOptions
else:
    vested = totalOptions * elapsed / vestingDuration
```

**Numerical Example:**

- Grant: 10,000 options
- Cliff: 1 year (365 days)
- Vesting: 4 years (1,460 days)
- Strike price: $1.00 USDC

| Time | Elapsed | Vested | Exercisable |
|---|---|---|---|
| Month 6 | 182 days | 0 (before cliff) | 0 |
| Year 1 | 365 days | 2,500 | 2,500 |
| Year 2 | 730 days | 5,000 | 5,000 |
| Year 3 | 1,095 days | 7,500 | 7,500 |
| Year 4 | 1,460 days | 10,000 | 10,000 |

If the employee exercises 1,000 at Year 2, the exercisable at Year 3 would be 7,500 - 1,000 = 6,500.

---

## 8. Exercise Mechanics

### Flow

```
Employee                     ESOPOptionNFT                ESOPToken     USDC       Treasury
   |                              |                          |           |            |
   |-- exercise(tokenId, amt) --> |                          |           |            |
   |                              |-- verify ownership       |           |            |
   |                              |-- check not expired      |           |            |
   |                              |-- calc vested & avail    |           |            |
   |                              |-- calc cost              |           |            |
   |                              |-- update state (CEI)     |           |            |
   |                              |                          |           |            |
   |                              |-- safeTransferFrom() ------------>  |            |
   |                              |                          |       transfer -----> |
   |                              |                          |           |            |
   |                              |-- mint() --------------> |           |            |
   |  <------- ESOP tokens ------------------------------- --|           |            |
   |                              |                          |           |            |
   |                              |-- emit OptionsExercised  |           |            |
```

### Token Conversion

- **1 option = 1 ESOP token** (1e18 wei)
- Exercising 500 options mints `500 * 1e18` ESOP tokens

### Cost Calculation

```
cost_in_usdc = amount * strikePrice
```

Where `strikePrice` is denominated in USDC's smallest unit (6 decimals). A $1.00 strike price is stored as `1_000_000`.

| Options | Strike Price | USDC Cost |
|---|---|---|
| 100 | $1.00 (1_000_000) | 100 USDC (100_000_000) |
| 500 | $0.50 (500_000) | 250 USDC (250_000_000) |
| 1,000 | $2.00 (2_000_000) | 2,000 USDC (2_000_000_000) |

### Prerequisites

Before calling `exercise()`, the employee must:

1. Hold USDC in their wallet sufficient to cover the cost
2. Approve the ESOPOptionNFT contract to spend that USDC (`usdc.approve(optionNFTAddress, cost)`)

---

## 9. Termination and Forfeiture

When an employee's employment ends, an admin terminates the grant:

```solidity
optionNFT.terminateGrant(tokenId);
```

### Effects of Termination

1. **Vesting freezes** -- The `terminationTimestamp` is set to `block.timestamp`. No further options will vest.
2. **Unvested options are forfeited** -- The difference between `totalOptions` and vested-at-termination is permanently lost.
3. **Post-termination window opens** -- The employee has `postTerminationWindow` seconds (default: 90 days) to exercise any vested options.
4. **After the window closes** -- The grant becomes expired. No further exercise is possible.

### Timeline

```
Grant      Cliff      Termination      Window Closes
  |----------|------------|------90 days------|
  |  nothing |   vesting  |  exercise only    | expired
  |  vests   |   accrues  |  (no new vesting) | (no exercise)
```

### Numerical Example

- 10,000 options, 1-year cliff, 4-year vesting, 90-day post-termination window
- Employee is terminated at Year 2 (730 days elapsed)
- Vested at termination: `10,000 * 730 / 1,460 = 5,000`
- Forfeited: 5,000 (unvested)
- Exercise window: 90 days from termination

---

## 10. Soulbound Transfer and Wallet Recovery

Option grant NFTs are **soulbound**: they cannot be freely transferred between wallets. This prevents employees from selling or trading their unvested options.

However, wallet recovery is a practical necessity (lost keys, compromised wallets). The system supports a two-step admin-approved transfer:

### Step 1: Admin Approves

```solidity
// Admin (e.g., HR multi-sig) approves transfer to employee's new wallet
optionNFT.approveTransfer(tokenId, newWalletAddress);
```

### Step 2: Transfer Executes

```solidity
// Employee (from old wallet) or admin executes the transfer
optionNFT.executeApprovedTransfer(tokenId);
```

### Properties

- Only the specific approved destination can receive the NFT
- The approval can be revoked before execution via `revokeTransferApproval()`
- All grant data (vesting schedule, exercised count, termination state) is preserved across the transfer
- The approval is single-use -- it is cleared after execution

### Soulbound Enforcement

The `_update()` hook in ERC-721 is overridden to block all transfers except:

1. **Minting** (`from == address(0)`) -- Creating a new grant
2. **Burning** (`to == address(0)`) -- Destroying a completed/expired grant
3. **Admin-approved transfer** -- The `_adminTransferApprovals[tokenId]` mapping matches the destination

Any other transfer attempt reverts with `TransferNotApprovedByAdmin`.

---

## 11. Access Control Model

The system uses OpenZeppelin's `AccessControl` with the following role hierarchy:

```
DEFAULT_ADMIN_ROLE (can grant/revoke all roles)
    |
    +-- ADMIN_ROLE
    |     |- terminateGrant()
    |     |- approveTransfer() / revokeTransferApproval()
    |     |- executeApprovedTransfer()
    |     |- burnGrant() (alongside holder)
    |     |- setUSDCTreasury()
    |     |- pause() / unpause()
    |
    +-- GRANTOR_ROLE
    |     |- grantOptions()
    |
    +-- MINTER_ROLE (on ESOPToken)
          |- mint()
```

### Recommended Role Assignments

| Role | Recommended Holder | Rationale |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Company multi-sig (e.g., Gnosis Safe) | Highest privilege; should require multiple signers |
| `ADMIN_ROLE` | Same multi-sig | Operational admin functions |
| `GRANTOR_ROLE` | HR operator or dedicated multi-sig | Can be a separate address to reduce multi-sig overhead for routine grants |
| `MINTER_ROLE` | ESOPOptionNFT contract (only) | Should never be held by an EOA |

---

## 12. Security Model

### OpenZeppelin Primitives

| Primitive | Usage |
|---|---|
| `AccessControl` | Role-based permissioning for all privileged operations |
| `ReentrancyGuard` | Protects `exercise()` from reentrancy via the `nonReentrant` modifier |
| `Pausable` | Emergency stop for exercise operations |
| `SafeERC20` | Handles non-standard ERC-20 return values (relevant for USDC) |
| `ERC20Capped` | Enforces supply cap at the token level, preventing over-minting |

### CEI Pattern

The `exercise()` function follows the Checks-Effects-Interactions pattern:

1. **Checks** -- Ownership, expiry, vested amount, exercise amount validation
2. **Effects** -- `grant.exercisedOptions += amount` (state update before external calls)
3. **Interactions** -- `safeTransferFrom()` for USDC, `mint()` for ESOP tokens

### Soulbound Enforcement

The `_update()` override ensures that even if a standard ERC-721 `transferFrom` or `safeTransferFrom` is called, the transfer will revert unless it matches an active admin approval.

### Input Validation

Every external function validates its inputs:
- Zero-address checks on all address parameters
- Zero-amount checks on exercise amounts
- Grant parameter validation (non-zero values, `vestingDuration >= cliffDuration`)
- Ownership verification before any state-modifying operation

### Immutable References

`esopToken` and `usdc` are stored as `immutable`, preventing them from being changed after deployment. This guarantees that the exercise flow always interacts with the correct token contracts.

---

## 13. Storage Layout and Gas Optimization

### OptionGrant Packing

The `OptionGrant` struct is carefully packed to minimize storage slots:

```
Slot 0 [256 bits]: totalOptions (128) + exercisedOptions (128)
Slot 1 [256 bits]: strikePrice (128) + vestingStart (64) + cliffDuration (64)
Slot 2 [200 bits]: vestingDuration (64) + terminationTimestamp (64) + postTerminationWindow (64) + terminated (8)
```

This packing means a complete grant occupies **3 storage slots** (96 bytes), reducing gas costs for both writes and reads.

### Type Choices

| Type | Field | Range | Rationale |
|---|---|---|---|
| `uint128` | totalOptions | Up to ~3.4 x 10^38 | Far exceeds any realistic option count |
| `uint128` | strikePrice | Up to ~3.4 x 10^38 | USDC 6-decimal encoding fits easily |
| `uint64` | timestamps/durations | Up to year 584,942,417,355 | Sufficient for any vesting schedule |
| `bool` | terminated | true/false | 8 bits, packs into slot 2 |

### Other Optimizations

- **Immutable state** -- `esopToken` and `usdc` are stored in contract bytecode, not storage (zero SLOAD cost).
- **Library functions are pure** -- VestingMath functions are inlined by the compiler and require no storage access.
- **Optimizer enabled** -- 200 runs, balancing deployment cost and runtime gas.
- **Auto-incrementing token IDs** -- Simple counter (`_nextTokenId`) avoids hash-based ID generation overhead.

---

## 14. Events and Indexing

All state transitions emit events with indexed parameters for efficient off-chain filtering:

| Event | Indexed Fields | Data Fields |
|---|---|---|
| `GrantCreated` | `tokenId`, `employee` | `totalOptions`, `strikePrice`, `vestingStart`, `cliffDuration`, `vestingDuration`, `postTerminationWindow` |
| `OptionsExercised` | `tokenId`, `employee` | `optionsExercised`, `usdcPaid`, `tokensMinted` |
| `GrantTerminated` | `tokenId`, `employee` | `terminationTimestamp`, `vestedAtTermination`, `unvestedLost` |
| `GrantBurned` | `tokenId`, `employee` | -- |
| `AdminTransferApproved` | `tokenId`, `from`, `to` | -- |
| `AdminTransferRevoked` | `tokenId` | -- |
| `USDCTreasuryUpdated` | `oldTreasury`, `newTreasury` | -- |

These events enable building a complete off-chain index (subgraph, event listener) for dashboards and reporting.

---

## 15. Error Handling

The system uses custom errors (Solidity 0.8.4+) for gas-efficient reverts with descriptive context:

| Error | When |
|---|---|
| `ZeroAddress()` | Any function receives `address(0)` where a valid address is required |
| `ZeroAmount()` | `exercise()` called with `amount == 0` |
| `InvalidGrantParameters()` | `grantOptions()` called with invalid parameters (zero values, duration mismatch) |
| `GrantNotFound(tokenId)` | Caller is not the owner of the specified grant |
| `GrantAlreadyTerminated(tokenId)` | `terminateGrant()` called on an already-terminated grant |
| `GrantExpired(tokenId)` | `exercise()` called after the post-termination window has closed |
| `NothingToExercise(tokenId)` | No options are currently exercisable (before cliff, fully exercised) |
| `ExerciseAmountExceedsAvailable(tokenId, requested, available)` | Requested exercise amount exceeds exercisable options |
| `ExerciseWindowClosed(tokenId)` | Post-termination exercise window has passed |
| `TransferNotApprovedByAdmin(tokenId, from, to)` | Attempted transfer without admin approval |
| `GrantNotBurnable(tokenId)` | `burnGrant()` called when the grant is not in a terminal state |

---

## 16. Testing Strategy

The test suite is structured in layers of increasing scope:

### Unit Tests

- **`ESOPToken.t.sol`** -- Constructor, minting, cap enforcement, role management, event emission.
- **`ESOPOptionNFT.t.sol`** -- Grant creation, exercise, termination, burn conditions, wallet recovery, permission checks, edge cases.
- **`VestingMath.t.sol`** -- Vesting calculations at each boundary (before cliff, at cliff, mid-vesting, full vesting, post-vesting).

### Integration Tests

- **`Integration.t.sol`** -- Full lifecycle scenarios:
  - Grant -> vest -> exercise -> burn
  - Grant -> terminate -> exercise within window -> burn
  - Grant -> wallet recovery -> exercise from new wallet

### Fuzz Tests

- **`VestingMath.t.sol`** -- Property-based tests with random inputs:
  - Vested amount is monotonically non-decreasing over time
  - Vested amount never exceeds total options
  - Exercise cost is deterministic for given inputs

### Invariant Tests

- **`invariant/Invariant.t.sol`** + **`Handler.t.sol`** -- Stateful fuzzing that randomly calls contract functions and verifies global invariants after every sequence:

| Invariant | Property |
|---|---|
| Supply cap | `esopToken.totalSupply() <= esopToken.cap()` |
| Exercise ceiling | `grant.exercisedOptions <= grant.totalOptions` for all grants |
| Vesting ceiling | `vestedOptions <= grant.totalOptions` for all grants |
| Exercise-vesting consistency | `grant.exercisedOptions <= vestedOptions` for all grants |

### Test Configuration

| Parameter | Default | CI |
|---|---|---|
| Fuzz runs | 1,000 | 10,000 |
| Invariant runs | 256 | 512 |
| Invariant depth | 128 | 256 |

### CI/CD

GitHub Actions runs on every push and pull request:
1. `forge fmt --check` -- Formatting verification
2. `forge build --sizes` -- Compilation and contract size reporting
3. `forge test -vvv` -- Full test suite with verbose output

---

## 17. Deployment

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `ADMIN_ADDRESS` | Yes | Multi-sig address receiving all admin roles |
| `USDC_ADDRESS` | Yes | USDC token contract address on the target chain |
| `TREASURY_ADDRESS` | Yes | Address where USDC exercise payments are sent |
| `MAX_SUPPLY` | No | Maximum ESOP token supply in wei (default: 10,000,000 * 1e18) |

### Deployment Sequence

```
1. Deploy ESOPToken(name, symbol, maxSupply, admin)
2. Deploy ESOPOptionNFT(name, symbol, esopTokenAddress, usdcAddress, treasury, admin)
3. esopToken.grantRole(MINTER_ROLE, optionNFTAddress)
```

### Command

```shell
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url <rpc_url> \
  --private-key <deployer_key> \
  --broadcast \
  --verify
```

### Post-Deployment Checklist

1. Verify both contracts on Etherscan
2. Grant `GRANTOR_ROLE` to the HR operator address via the admin multi-sig
3. Confirm `MINTER_ROLE` is assigned only to the ESOPOptionNFT contract
4. Test a small grant on a testnet before mainnet deployment
5. Transfer deployer's `DEFAULT_ADMIN_ROLE` to the multi-sig if deployer was used as initial admin

---

## 18. Risks and Considerations

### Smart Contract Risk

As with any smart contract system, bugs could lead to loss of funds or incorrect state. Mitigations:
- Extensive test coverage (unit, integration, fuzz, invariant)
- Use of battle-tested OpenZeppelin libraries
- Solidity 0.8.28 with built-in overflow protection
- CEI pattern and reentrancy guard

### USDC Dependency

The system depends on USDC for exercise payments. If USDC is paused or blacklists the treasury address, exercise operations would be blocked. This is an inherent risk of using a centralized stablecoin.

### Admin Key Security

The admin multi-sig has significant power: terminating grants, approving transfers, pausing the system. Compromise of the multi-sig could lead to unauthorized terminations or transfers. A high-threshold multi-sig (e.g., 3-of-5) is recommended.

### Immutable Grant Terms

Once a grant is created, its core parameters (strike price, vesting schedule, total options) cannot be modified. If a correction is needed, the grant must be terminated and a new one issued. This is a deliberate design choice favoring employee trust over administrative flexibility.

### Gas Costs

On Ethereum mainnet, gas costs for granting and exercising may be significant. For high-volume usage, deployment on an L2 (Arbitrum, Base, Optimism) with mainnet USDC bridging is recommended.

### Token Liquidity

ESOP tokens minted through exercise have no inherent liquidity. Their value depends on secondary market availability or a company-facilitated buyback program. This is typical for private company equity.
