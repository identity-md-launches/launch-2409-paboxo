# PABOXO

PABOXO is an immutable ERC-20 token. Its constructor mints exactly **1,000,000,000 tokens with 18 decimals** to the immediate deployer in one mint. The implementation inherits the vendored OpenZeppelin Contracts v5.1.0 ERC20 without changing its transfer or allowance rules.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract / artifact | `src/PABOXO.sol:PABOXO` |
| Token name | `PABOXO` |
| Token symbol | `PABOXO` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Deployment ETH value | `0` (nonpayable constructor) |
| Initial recipient | Constructor `msg.sender` |
| Intended launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | `cancun` |
| Optimization | Enabled, `200` runs |
| Metadata bytecode hash | `none` |

Deployment uses the creation bytecode from `out/PABOXO.sol/PABOXO.json` with no appended constructor arguments. Both CREATE and CREATE2 work. A factory deployment credits **the factory**, not the transaction origin or the account calling the factory. A direct deployment credits the deploying account. The constructor makes no external calls and needs no prior contracts or configuration.

The token has no owner, roles, initialization function, proxy, upgrade mechanism, additional minting, public burning, pause, blacklist, seizure, or transfer tax. There are no application contracts to deploy. The launch service supplies its own manifest and executes distribution and liquidity operations; this project does not create a `launch.json` or broadcast transactions.

## Behavior and assumptions

- The requested token is a conventional ERC-20 with fixed metadata and fixed supply. Every successful transfer delivers the exact amount, with no fees, rebases, locks, or wallet limits.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert with OpenZeppelin's ERC-6093 custom errors on invalid operations. Transfers and approvals emit their standard ERC-20 events, including zero-amount operations.
- Zero-amount transfers between nonzero accounts and self-transfers are supported. Transfers to the zero address and approvals to the zero address revert. An insufficient balance or allowance reverts atomically.
- `approve` replaces the current allowance. Finite allowances decrease on `transferFrom`; `type(uint256).max` is treated as unlimited and remains unchanged. As in OpenZeppelin v5.1.0, allowance consumption does not emit an additional `Approval` event. Even a holder using `transferFrom` on its own balance needs an allowance; ordinary `transfer` does not.
- Transfers do not call recipient hooks. The token has no external contract dependencies at runtime, oracle, keeper, or signature mechanism. Ordinary ETH payments are rejected.

## After launch

No owner settings or initialization calls are required. The launch operator is responsible for deploying the exact artifact from this configuration, checking its metadata and initial factory balance, and distributing the supply using the launch's agreed economics. The supplied launch policy distributes 10% to the contributor distributor, 50% to liquidity, and 40% to the designated remainder recipient. Those allocations are factory operations; the token constructor leaves the entire supply with the factory.

The operator also handles the launch manifest, actual pool creation and settlement, and deployed-source verification. Holders control their balances and approvals. Applications should request only the allowance they need; when replacing a nonzero allowance, holders should first revoke it and confirm the revocation to limit the standard ERC-20 approval race. An unlimited approval gives the spender continuing authority until revoked.

There is no recovery or rescue function. Tokens sent to an address that cannot spend them, including this token contract itself, cannot be recovered by an administrator. The supply remains fixed even if holders lose access to their balances. These tests are local verification, not an independent security audit.

## Build and verification

Foundry and Solidity 0.8.26 must be available. All Solidity dependencies are ordinary files in `lib/`; no network fetch, package manager, submodule, environment configuration, FFI, or filesystem cheatcode permission is needed to build and test. Dependency versions and checksums are recorded in [DEPENDENCIES.md](DEPENDENCIES.md).

```sh
forge build
FOUNDRY_FUZZ_SEED=0x8c0e8e7946d3b77d93a2799146f5dd20811060fedcd196cc7c08d2416eaf0320 forge test
forge fmt --check
```

The seed is provided to the test runner; tests never read or modify environment variables. Default fuzzing uses 1,024 cases per fuzz test. Each stateful invariant uses 128 runs of 64 actions, with unexpected handler reverts treated as failures.

The delivered suite covers constructor metadata and its single mint event, exact transfers and approvals, rejection and rollback paths, allowance revocation and exhaustion, unlimited approvals, absent administrative endpoints, native-ETH rejection, CREATE2 factory deployment, and exact launch distribution and claim transfers. Stateful tests compare balances and allowances against an independent ledger after sequences of transfers, approvals, delegated spends, and rejected overspends.

The launch-flow test models token transfers only; it does not instantiate Uniswap v4 or test its pricing. The provided protected checks depend on the separate network launch harness (`OwnerChecks`, `LaunchLiquidity`, `PoolInitializationGuard`, `HookFlags`, v4-core, and launch environment values), which is not part of this repository. That complete protected suite is run by the launch verifier. Local validation uses the delivered tests, including Foundry fuzzing and stateful invariants; Slither and Mythril were not run.
