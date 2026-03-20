# Merkle Trees

LeanIMT and Sparse Merkle Tree implemented in Fe, matching the algorithms, ABI, and optimization strategies of the [zk-kit](https://github.com/privacy-scaling-explorations/zk-kit) Solidity reference.

Ported from [fe-zkkit](https://github.com/g-r-a-n-t/zk-kit/tree/fe-support/fe-zkkit) by Grant Wuerker and Ahmed (Turupawn).

## Gas Results

| Operation | Fe (Sonatina) | Solidity | Saved |
|-----------|-------:|-------:|------:|
| **LeanIMT** | | | |
| computeRoot (32 siblings) | 14,105 | 16,564 | **-14.8%** |
| computeRoot (typical) | 9,788 | 10,640 | **-8.0%** |
| verify (32 siblings) | 14,190 | 16,563 | **-14.3%** |
| verify (typical) | 9,869 | 10,639 | **-7.2%** |
| updateRoot (32 siblings) | 16,538 | 18,425 | **-10.2%** |
| updateRoot (typical) | 10,494 | 11,023 | **-4.8%** |
| **Sparse Merkle Tree** | | | |
| computeRoot (all enabled) | 14,241 | 16,558 | **-14.0%** |
| computeRoot (typical) | 17,264 | 18,981 | **-9.0%** |
| verify (all enabled) | 14,301 | 16,621 | **-14.0%** |
| verify (typical) | 17,369 | 19,069 | **-8.9%** |
| updateRoot (all enabled) | 17,042 | 18,546 | **-8.1%** |
| updateRoot (typical) | 20,339 | 20,954 | **-2.9%** |

Fe (Sonatina, OPT_LEVEL=2) vs Solidity (solc --optimize, 200 runs). 48 tests, 1024 fuzz runs each.

## What Fe does differently

### `Hasher` trait — swap hash functions at compile time
Solidity Merkle libraries hardcode their hash function. Switching from Keccak to Poseidon means forking the entire codebase or paying STATICCALL overhead (~100 gas/call warm). Fe's `Hasher` trait separates the hash from the tree — the compiler monomorphizes it, so there's zero runtime dispatch cost.

### Const generics — parameterize tree depth
Solidity uses either hardcoded depth (duplicated code per depth) or dynamic arrays (runtime bounds checks). Fe's const generics produce specialized bytecode for each depth used.

### Zero-cost library imports
Solidity shared libraries require DELEGATECALL (100 gas warm) or copy-paste. Fe's library files compile to inlined bytecode — the bench contract and the library produce identical output.

### Generic `hash_step`
The hash-step pattern (hash ordered pair based on index bit) appears 6 times in the Solidity reference. Fe replaces all of them with one generic helper.

## Equivalence

Verified via differential fuzzing against the Solidity reference:
- Identical outputs for all compute/verify/update functions
- Identical reverts for invalid inputs
- Invariance properties (unused siblings ignored, high bits ignored)
- Cross-implementation structural checks (SMT roots match LeanIMT roots under canonical expansion)

## Running

```bash
cd bench
FE_SONA_OPT_LEVEL=2 forge test --ffi --offline -vvv
```
