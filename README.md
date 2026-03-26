# rosetta-fe

Side-by-side Solidity and Fe implementations of common Ethereum contract patterns, with gas benchmarks.

## Modules

- **rosetta_math** — Uniswap V3 FullMath, Aave WadRayMath, Morpho MathLib
- **rosetta_ec** — BN254 elliptic curve operations (precompiles)
- **rosetta_merkle** — Merkle proof verification
- **rosetta_amm** — Constant-product AMM
- **rosetta_verifier** — Groth16 and Plonk (gnark/SP1) ZK proof verifiers
- **rosetta_poseidon** — Poseidon hash (T=3, BN254)

## Running

```bash
# Fe tests
fe test

# Foundry gas benchmarks
cd math/bench
FE_SONA_OPT_LEVEL=2 forge test --match-test testGas -vv
```

Requires [Fe](https://github.com/ethereum/fe) and [Foundry](https://book.getfoundry.sh/).
