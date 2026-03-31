> **Experimental** — For illustration and benchmarking only. Not audited.

# rosetta

Side-by-side Fe and Solidity implementations of Ethereum contract patterns. Each example has `fe/` and `sol/` subdirectories with equivalent logic, verified by Foundry fuzz tests.

## Examples

| Example | Description | Fuzz-tested |
|---------|-------------|:-----------:|
| [erc20](examples/erc20) | ERC-20 token (transfer, approve, mint) | yes |
| [math](examples/math) | 512-bit mulDiv (Uniswap V3 FullMath) | yes |
| [merkle](examples/merkle) | Sorted-pair Merkle proof verification | yes |
| [amm](examples/amm) | Constant-product AMM (swap, add liquidity) | yes |
| [escrow](examples/escrow) | Escrow with typed state machine | |
| [diamond](examples/diamond) | Multi-facet contract (token + governance) | |
| [verifier](examples/verifier) | Plonk and Halo2 proof verification | |
| [poseidon](examples/poseidon) | Poseidon hash (T=3, BN254) | excluded ([sonatina#232](https://github.com/fe-lang/sonatina/issues/232)) |

Shared libraries in `shared/`:
- [ec](shared/ec) — BN254 elliptic curve operations via typed `std::evm::crypto` wrappers
- [fixed_point](shared/fixed_point) — Fixed-point arithmetic type

## Running

```bash
# Build all Fe contracts
fe build .

# Run Foundry equivalence + gas tests
cd examples/erc20 && forge test -vv
cd examples/math  && forge test -vv
cd examples/merkle && forge test -vv
cd examples/amm   && forge test -vv
```

Requires [Fe](https://github.com/ethereum/fe) and [Foundry](https://book.getfoundry.sh/).

## Capability model

Fe code uses typed precompile wrappers (`std::evm::crypto`) for cryptographic operations and the effects system (`uses (evm: mut Evm)`) for raw memory and calldata access. No direct imports from `std::evm::ops`.
