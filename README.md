> **🔬 Experimental** — For illustration and benchmarking only. Not audited.

# rosetta-fe

Side-by-side implementations of Ethereum contract patterns. Each example has `fe/` and `sol/` (or `js/`) subdirectories.

## Examples

- **poseidon** — Poseidon hash (T=3, BN254)
- **verifier** — Groth16 and Plonk (SP1 v6) proof verification
- **ec** — BN254 elliptic curve operations
- **merkle** — Merkle proof verification
- **amm** — Constant-product AMM
- **erc20** — ERC-20 token
- **math** — 512-bit mulDiv
- **diamond** — Multi-facet contract (token + governance)
- **escrow** — Cross-contract calls with typed capabilities

## Running

```bash
fe test

cd examples/poseidon
forge test --match-test testGas -vv
```

Requires [Fe](https://github.com/ethereum/fe) and [Foundry](https://book.getfoundry.sh/).
