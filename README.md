> **🔬 Experimental** — These implementations are for illustration and benchmarking purposes only. They have not been audited and should not be used in production.

# rosetta-fe

Side-by-side Solidity and Fe implementations of common Ethereum contract patterns, with gas benchmarks.

## Modules

- **math** — Uniswap V3 FullMath, Aave WadRayMath, Morpho MathLib
- **ec** — BN254 elliptic curve operations (precompiles)
- **merkle** — Merkle proof verification
- **amm** — Constant-product AMM
- **verifier** — Groth16 and Plonk (gnark/SP1) ZK proof verifiers
- **poseidon** — Poseidon hash (T=3, BN254)

## Running

```bash
# Fe tests
fe test

# Foundry gas benchmarks
cd bench
FE_SONA_OPT_LEVEL=2 forge test --match-test testGas -vv
```

Requires [Fe](https://github.com/ethereum/fe) and [Foundry](https://book.getfoundry.sh/).
