# Web3 ESOP

On-chain Employee Stock Option Plan (ESOP) built with Solidity. Option grants are represented as soulbound ERC-721 NFTs with linear vesting schedules, and employees exercise them by paying USDC to receive ERC-20 ESOP tokens.

## Architecture

| Contract | Standard | Purpose |
|---|---|---|
| **ESOPToken** | ERC-20 (capped) | Company equity token minted when employees exercise options |
| **ESOPOptionNFT** | ERC-721 (soulbound) | Represents individual option grants with vesting state |
| **VestingMath** | Library | Pure vesting calculation logic (cliff + linear) |

### How It Works

1. **Grant** -- An admin with `GRANTOR_ROLE` mints a soulbound NFT to an employee, encoding the strike price, cliff, vesting duration, and total options.
2. **Vest** -- Options vest linearly after the cliff period. Vesting math is calculated on-chain at read time.
3. **Exercise** -- The employee calls `exercise(tokenId, amount)`, pays `amount * strikePrice` in USDC (sent to the treasury), and receives ESOP tokens.
4. **Terminate** -- If employment ends, an admin calls `terminateGrant()`. Unvested options are forfeited; vested options remain exercisable for a configurable post-termination window (default 90 days).
5. **Burn** -- Once a grant is fully exercised or expired, the NFT can be burned to clean up state.

### Key Features

- **Soulbound NFTs** -- Option grants are non-transferable. Wallet recovery is supported through an admin-approved two-step transfer process.
- **USDC strike price** -- Exercise payments are made in USDC (6 decimals) and routed to a configurable treasury address.
- **Capped supply** -- `ESOPToken` enforces a hard cap on total minted tokens.
- **Access control** -- Role-based permissions (`ADMIN_ROLE`, `GRANTOR_ROLE`, `MINTER_ROLE`) via OpenZeppelin `AccessControl`.
- **Pausable** -- Exercise operations can be paused in emergencies.
- **Reentrancy guard** -- All state-changing external calls are protected.

## Project Structure

```
src/
  ESOPToken.sol              ERC-20 equity token
  ESOPOptionNFT.sol          Soulbound option grant NFT
  interfaces/
    IESOPToken.sol
    IESOPOptionNFT.sol
  libraries/
    VestingMath.sol           Vesting calculation library
test/
  Base.t.sol                  Shared test setup and helpers
  ESOPToken.t.sol             Token unit tests
  ESOPOptionNFT.t.sol         Option NFT unit tests
  VestingMath.t.sol           Vesting math unit + fuzz tests
  Integration.t.sol           End-to-end lifecycle tests
  invariant/
    Invariant.t.sol           Stateful invariant tests
    Handler.t.sol             Fuzzing handler
  mocks/
    MockERC20.sol             Mock USDC for testing
script/
  Deploy.s.sol                Deployment script
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Install

```shell
git clone --recurse-submodules <repo-url>
cd web3-esop
forge build
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

Run with verbose output:

```shell
forge test -vvv
```

### Format

```shell
forge fmt
```

## Deployment

Set environment variables and run the deploy script:

```shell
export ADMIN_ADDRESS=<multi-sig address>
export USDC_ADDRESS=<USDC token address>
export TREASURY_ADDRESS=<treasury address>
export MAX_SUPPLY=10000000000000000000000000  # 10M tokens (optional, default 10M)

forge script script/Deploy.s.sol:DeployScript \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key> \
  --broadcast
```

After deployment:
1. Verify contracts on Etherscan
2. Grant `GRANTOR_ROLE` to the HR operator address via the admin multi-sig

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) v5.5.0
- [forge-std](https://github.com/foundry-rs/forge-std) v1.14.0

## License

MIT
