// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../sol/ERC20.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function prank(address) external;
}

contract ERC20BenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    ERC20 private sol;
    address private feAddr;

    address constant OWNER = address(0x1);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    uint256 constant INITIAL = 1_000_000;

    function setUp() public {
        // Deploy Solidity ERC20
        sol = new ERC20(INITIAL, OWNER);

        // Deploy Fe ERC20
        string[] memory cmd = new string[](5);
        cmd[0] = "fe";
        cmd[1] = "build";
        cmd[2] = "--backend";
        cmd[3] = "sonatina";
        cmd[4] = "fe";
        vm.ffi(cmd);

        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash";
        readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < fe/out/Token.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address _fe;
        // Encode constructor args: (uint256 initialSupply, address owner)
        bytes memory initWithArgs = abi.encodePacked(feInitcode, abi.encode(INITIAL, OWNER));
        assembly { _fe := create(0, add(initWithArgs, 0x20), mload(initWithArgs)) }
        require(_fe != address(0), "Fe deploy failed");
        feAddr = _fe;
    }

    // --- Equivalence tests ---

    function test_equivalence_totalSupply() public view {
        uint256 solSupply = sol.totalSupply();
        (bool ok, bytes memory ret) = feAddr.staticcall(
            abi.encodeWithSelector(bytes4(keccak256("totalSupply()")))
        );
        require(ok, "fe call failed");
        uint256 feSupply = abi.decode(ret, (uint256));
        require(solSupply == feSupply, "supply mismatch");
    }

    function test_equivalence_balanceOf() public view {
        uint256 solBal = sol.balanceOf(OWNER);
        (bool ok, bytes memory ret) = feAddr.staticcall(
            abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), OWNER)
        );
        require(ok, "fe call failed");
        uint256 feBal = abi.decode(ret, (uint256));
        require(solBal == feBal, "balance mismatch");
    }

    // --- Gas benchmarks ---

    function testGas_sol_transfer() public {
        // Mint to this contract first
        sol.mint(address(this), 1000);
        sol.transfer(ALICE, 100);
    }

    function testGas_fe_transfer() public {
        // Mint to this contract
        (bool ok,) = feAddr.call(
            abi.encodeWithSelector(bytes4(keccak256("mint(address,uint256)")), address(this), 1000)
        );
        require(ok, "mint failed");

        (ok,) = feAddr.call(
            abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), ALICE, 100)
        );
        require(ok, "transfer failed");
    }

    function testGas_sol_approve() public {
        sol.approve(ALICE, 500);
    }

    function testGas_fe_approve() public {
        (bool ok,) = feAddr.call(
            abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), ALICE, 500)
        );
        require(ok, "approve failed");
    }

    // --- Fuzz tests ---

    function testFuzz_transfer_eq(uint256 mintAmount, uint256 transferAmount) public {
        // Bound to avoid overflow
        mintAmount = mintAmount % 1e30;
        transferAmount = transferAmount % (mintAmount + 1);

        // Sol
        sol.mint(address(this), mintAmount);
        bool solResult = sol.transfer(ALICE, transferAmount);
        uint256 solBal = sol.balanceOf(ALICE);

        // Fe
        feAddr.call(abi.encodeWithSelector(
            bytes4(keccak256("mint(address,uint256)")), address(this), mintAmount
        ));
        (bool ok, bytes memory ret) = feAddr.call(abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")), ALICE, transferAmount
        ));
        bool feResult = ok ? abi.decode(ret, (bool)) : false;

        (ok, ret) = feAddr.staticcall(abi.encodeWithSelector(
            bytes4(keccak256("balanceOf(address)")), ALICE
        ));
        uint256 feBal = abi.decode(ret, (uint256));

        require(solResult == feResult, "transfer result mismatch");
        require(solBal == feBal, "balance mismatch after transfer");
    }
}
