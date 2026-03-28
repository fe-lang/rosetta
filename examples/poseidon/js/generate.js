// Generates PoseidonT3 EVM bytecode using iden3/circomlibjs.
// circomlibjs is licensed under GPL-3.0 (https://github.com/iden3/circomlibjs)
//
// Run: npm install circomlibjs && node generate.js > ../PoseidonT3.hex
const { poseidonContract } = require("circomlibjs");
const code = poseidonContract.createCode(2); // 2-input Poseidon (T=3)
process.stdout.write(code.slice(2)); // strip 0x prefix
