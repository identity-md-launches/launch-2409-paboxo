# Vendored dependencies

These source files are delivered as ordinary files, with no Git submodules or installation step. They are unmodified upstream files. Each dependency directory includes the upstream license and a `SHA256SUMS` file listing the SHA-256 digest of every vendored upstream file, relative to that directory.

| Dependency | Release | Commit | Delivered content |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/69c8def5f222ff96f2b5beff05dfba996368aa79) | `v5.1.0` | `69c8def5f222ff96f2b5beff05dfba996368aa79` | ERC20 and its complete transitive import set, plus MIT license |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/3b20d60d14b343ee4f908cb8079495c07f5e8981) | `v1.9.6` | `3b20d60d14b343ee4f908cb8079495c07f5e8981` | Complete `src/` tree, plus MIT and Apache-2.0 licenses; used only by tests |

The source archives were downloaded from GitHub's codeload service using the exact commits above. Their SHA-256 digests were:

```text
b0d8bc73b249cee906d596cf8e63c6ea71a4311c4e2a45a0b253e060d6dd3ae8  openzeppelin-contracts archive
eb94c3bd026342ae6955ce08f76aad648c586c003acebf5ee5d9b419a417076c  forge-std archive
```

The archive files themselves are not build inputs. All required Solidity source is already present in `lib/`, with remappings in `foundry.toml`. Neither library adds linked external-library placeholders to the token's bytecode.
