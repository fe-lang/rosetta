// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SolidityFullMath} from "../src/SolidityFullMath.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
    function readFile(string calldata path) external view returns (string memory);
    function parseBytes(string calldata s) external pure returns (bytes memory);
}

interface IFeFullMath {
    function mulDiv(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256);
    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256);
}

contract FullMathBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    IFeFullMath private feSona;
    SolidityFullMath private sol;

    function _skipIfOverflow(uint256 a, uint256 b, uint256 denominator) internal pure returns (bool) {
        if (denominator == 0) return true;
        unchecked {
            uint256 prod1;
            assembly {
                let mm := mulmod(a, b, not(0))
                let prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (denominator <= prod1) return true;
        }
        return false;
    }

    function setUp() public {
        vm.pauseGasMetering();

        // Build Fe (Sonatina backend) via FFI
        uint256 optLevel = vm.envOr("FE_SONA_OPT_LEVEL", uint256(2));
        require(optLevel <= 2, "BAD_FE_SONA_OPT_LEVEL");

        string[] memory cmd = new string[](7);
        cmd[0] = "fe";
        cmd[1] = "build";
        cmd[2] = "--backend";
        cmd[3] = "sonatina";
        cmd[4] = "-O";
        cmd[5] = optLevel == 0 ? "0" : optLevel == 1 ? "1" : "2";
        cmd[6] = "..";  // workspace root
        vm.ffi(cmd);

        // Deploy Fe contract from compiled bytecode
        // Read hex-encoded initcode produced by `fe build`
        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash";
        readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../out/FullMathBench.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address feAddr;
        assembly {
            feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode))
        }
        require(feAddr != address(0), "Fe deploy failed");
        feSona = IFeFullMath(feAddr);

        // Deploy Solidity reference
        sol = new SolidityFullMath();

        vm.resumeGasMetering();
    }

    // -----------------------------------------------------------------------
    // Semantic equivalence: differential fuzz tests
    // -----------------------------------------------------------------------

    function testFuzz_mulDiv_equivalence(uint256 a, uint256 b, uint256 denominator) public view {
        if (_skipIfOverflow(a, b, denominator)) return;
        uint256 solResult = sol.mulDiv(a, b, denominator);
        uint256 feResult = feSona.mulDiv(a, b, denominator);
        require(feResult == solResult, "mulDiv: Fe != Solidity");
    }

    function testFuzz_mulDivRoundingUp_equivalence(uint256 a, uint256 b, uint256 denominator) public view {
        if (_skipIfOverflow(a, b, denominator)) return;
        uint256 solResult = sol.mulDivRoundingUp(a, b, denominator);
        uint256 feResult = feSona.mulDivRoundingUp(a, b, denominator);
        require(feResult == solResult, "mulDivRoundingUp: Fe != Solidity");
    }

    // -----------------------------------------------------------------------
    // Gas benchmarks: Solidity
    // -----------------------------------------------------------------------

    function testGas_sol_mulDiv_simple() public view {
        sol.mulDiv(500, 10, 50);
    }

    function testGas_sol_mulDiv_512bit() public view {
        sol.mulDiv(type(uint256).max / 2, type(uint256).max / 3, type(uint256).max / 5);
    }

    function testGas_sol_mulDivRoundingUp() public view {
        sol.mulDivRoundingUp(type(uint256).max / 2, type(uint256).max / 3, type(uint256).max / 5);
    }

    // -----------------------------------------------------------------------
    // Gas benchmarks: Fe
    // -----------------------------------------------------------------------

    function testGas_fe_mulDiv_simple() public view {
        feSona.mulDiv(500, 10, 50);
    }

    function testGas_fe_mulDiv_512bit() public view {
        feSona.mulDiv(type(uint256).max / 2, type(uint256).max / 3, type(uint256).max / 5);
    }

    function testGas_fe_mulDivRoundingUp() public view {
        feSona.mulDivRoundingUp(type(uint256).max / 2, type(uint256).max / 3, type(uint256).max / 5);
    }

    // -----------------------------------------------------------------------
    // Deterministic correctness
    // -----------------------------------------------------------------------

    function test_mulDiv_basic() public view {
        require(sol.mulDiv(500, 10, 50) == 100, "sol basic");
        require(feSona.mulDiv(500, 10, 50) == 100, "fe basic");
        require(feSona.mulDiv(0, 10, 50) == 0, "fe zero a");
        require(feSona.mulDiv(500, 0, 50) == 0, "fe zero b");
        require(feSona.mulDiv(1, 1, 1) == 1, "fe ones");
    }

    function test_mulDiv_512bit() public view {
        uint256 solResult = sol.mulDiv(1 << 255, 2, 1 << 255);
        uint256 feResult = feSona.mulDiv(1 << 255, 2, 1 << 255);
        require(solResult == 2, "sol 512-bit");
        require(feResult == 2, "fe 512-bit");
    }

    function test_mulDivRoundingUp_rounds() public view {
        require(sol.mulDivRoundingUp(10, 10, 3) == 34, "sol rounds up");
        require(feSona.mulDivRoundingUp(10, 10, 3) == 34, "fe rounds up");
        require(feSona.mulDivRoundingUp(10, 10, 5) == 20, "fe exact");
    }
}
