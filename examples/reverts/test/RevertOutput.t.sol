// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function envOr(string calldata name, string calldata defaultValue) external returns (string memory);
    function expectRevert(bytes calldata revertData) external;
}

interface IRevertOutput {
    function checkedOverflow() external;
    function failedAssert() external;
    function failedAssertMsg() external;
}

contract RevertOutputTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    bytes4 private constant PANIC_SELECTOR = 0x4e487b71;
    bytes4 private constant ERROR_SELECTOR = 0x08c379a0;

    IRevertOutput private fe;

    function setUp() public {
        string[] memory buildCmd = new string[](3);
        buildCmd[0] = "bash";
        buildCmd[1] = "-lc";
        buildCmd[2] = string.concat(
            "fe_bin=${FE_BIN:-}; ",
            "if { [ -z \"$fe_bin\" ] || [ \"$fe_bin\" = fe ]; } ",
            "&& [ -x \"$HOME/code/fe/master/target/release/fe\" ]; then ",
            "fe_bin=\"$HOME/code/fe/master/target/release/fe\"; ",
            "fi; ",
            "\"${fe_bin:-fe}\" build fe"
        );
        vm.ffi(buildCmd);

        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash";
        readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < fe/out/RevertOutput.bin";
        bytes memory initcode = vm.ffi(readCmd);

        address deployed;
        assembly {
            deployed := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(deployed != address(0), "Fe deploy failed");
        fe = IRevertOutput(deployed);
    }

    function test_fe_checked_overflow_reverts_with_solidity_panic() public {
        vm.expectRevert(abi.encodeWithSelector(PANIC_SELECTOR, uint256(0x11)));
        fe.checkedOverflow();
    }

    function test_fe_assert_reverts_with_solidity_panic() public {
        vm.expectRevert(abi.encodeWithSelector(PANIC_SELECTOR, uint256(0x01)));
        fe.failedAssert();
    }

    function test_fe_assert_msg_reverts_with_solidity_error_string() public {
        vm.expectRevert(abi.encodeWithSelector(ERROR_SELECTOR, "boom"));
        fe.failedAssertMsg();
    }

    function test_display_fe_checked_overflow() public {
        fe.checkedOverflow();
    }

    function test_display_fe_assert() public {
        fe.failedAssert();
    }

    function test_display_fe_assert_msg() public {
        fe.failedAssertMsg();
    }
}
