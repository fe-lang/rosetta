// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Compute the 11-point linearized polynomial MSM in Solidity and Fe,
/// then compare the results. If they differ, the bug is in the MSM/memory.
/// If they match, the bug is in the KZG section after the MSM.
contract MSMDebugTest {
    // VK points (verified correct, on curve)
    uint256 constant QL_X = 2714773032566361735398260413518107570706289019141573602093747023461681138141;
    uint256 constant QL_Y = 10207220609888567477852282724812707756861966294950666667119692155077205992894;
    uint256 constant QR_X = 17919274808167168584263187859012763816365260341587621260815379357637476029962;
    uint256 constant QR_Y = 14558165337321799812085033100515533981610351056305142204990949940017867076397;
    uint256 constant QM_X = 1814703450159964740292891910795980721108620081843240976053374083376051887455;
    uint256 constant QM_Y = 11252528960397523304289223453506717847025678682133692300385063157160041127070;
    uint256 constant QO_X = 20843277058771674275997213106654908867381045039357421108797602213552545033079;
    uint256 constant QO_Y = 9646775541123942436366130063934415659078920798926708026864638413383214238671;
    uint256 constant QK_X = 5484717465597821820411103650564499774744032473047103693751158150047197753654;
    uint256 constant QK_Y = 5561799343038529497262757012400750786503050088440144551259537360162821571059;
    uint256 constant S3_X = 9316901462569250008665217603385561854185385862824092362271612343176126127375;
    uint256 constant S3_Y = 13799900238612879579721466063922041459340434537392216736920805107993374657577;

    // Proof points
    uint256 constant BSB22_X = 0x27086e886de4f31d65e997d9dd08e35dd6590101d9185db7c8c5dd7dd9348c9c;
    uint256 constant BSB22_Y = 0x1b711862d9757e744014177960751f5f5a84f14bbc1b019021db0666b8e55fc3;
    uint256 constant Z_X = 0x1657a289347c1973783849c4545c7ed8f0ea65f1eb40b31678d627e70b79bfd1;
    uint256 constant Z_Y = 0x1592517f8902c7364f90126fe04c28381fe12e165adcf82217876359a544e218;
    uint256 constant H0_X = 0x1aed4c55f27c9cb2021ddae086085388d250dc257cc61ece968e674b25ed18a3;
    uint256 constant H0_Y = 0x2e9fbdee2b76ceb2c26d73c760252070fab8d5c04dd4f5616ca352666bb18782;
    uint256 constant H1_X = 0x0bb1920bd0959e61569ec796bd832e78f92e20320fc9cc9ae6ae8470dab64371;
    uint256 constant H1_Y = 0x09fdd853d0db78b9ce5811df7c7bf6a7c0486cf433219034e1c43206b64a404a;
    uint256 constant H2_X = 0x19280febb426e548e99e6279adceffaa4ddae622ec50624afb4ea827467adc41;
    uint256 constant H2_Y = 0x099d164e7abfdc97d9b168461c2626e88239d30529974cb1b582d7362ed6d6d5;

    // Verified scalars
    uint256 constant QC_VAL = 0x28ecd97e273c00ce59504ccc15bfe8a2d8f87d1bbd7dc63df606b3c975080a6f;
    uint256 constant L_VAL = 0x2a2af70b568d007ce53077a078437c2acf6cad206354b0ffa823b4de87918a05;
    uint256 constant R_VAL = 0x03a674ce289759e10b9da150b523d55886b63dc8526f0e36132edb5239c0c238;
    uint256 constant RL_VAL = 0x154fef837c0badb35dcde6cc7d07b75f68e81c05b3b3a37f59a03764dfdf79e9; // l*r mod R
    uint256 constant O_VAL = 0x19d465a94658e64d3798897c8438352029a3d285a049af99ff195c36359c16d0;
    uint256 constant COEFF_S1 = 0x014e31ed4d81ae6dd405e472b9107d89e37137cb2f7e0fc5d32ac04e149f3989;
    uint256 constant COEFF_Z = 0x0d51bf1d4a66e52d8bb72ec963f83620301a16c69392558e1953b15c3fa555c4;
    uint256 constant COEFF_H0 = 0x2708f62ad73df8922601f3c8a66ee33858d4488264f5ada9885746cd1d181879;
    uint256 constant COEFF_H1 = 0x11a7fff44d705a9129a01901a0183754b4e256d6d5f790c3b12a04daad6d7260;
    uint256 constant COEFF_H2 = 0x0cd41c8f7b46057ad0ca5113f129ccb033f0db5f2bdd4b4742baf44cffd6f9cd;

    function _ecMul(uint256 px, uint256 py, uint256 s) internal view returns (uint256 rx, uint256 ry) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, px)
            mstore(add(ptr, 0x20), py)
            mstore(add(ptr, 0x40), s)
            if iszero(staticcall(gas(), 7, ptr, 0x60, ptr, 0x40)) { revert(0,0) }
            rx := mload(ptr)
            ry := mload(add(ptr, 0x20))
        }
    }

    function _ecAdd(uint256 ax, uint256 ay, uint256 bx, uint256 by) internal view returns (uint256 rx, uint256 ry) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, ax)
            mstore(add(ptr, 0x20), ay)
            mstore(add(ptr, 0x40), bx)
            mstore(add(ptr, 0x60), by)
            if iszero(staticcall(gas(), 6, ptr, 0x80, ptr, 0x40)) { revert(0,0) }
            rx := mload(ptr)
            ry := mload(add(ptr, 0x20))
        }
    }

    /// @notice Compute the 11-point MSM in Solidity
    function test_computeLinearizedDigest() public view {
        // MSM order: [bsb22, ql, qr, qm, qo, qk, s3, z, h0, h1, h2]
        // Scalars:   [qc_val, l, r, rl, o, 1, coeff_s1, coeff_z, coeff_h0, coeff_h1, coeff_h2]

        (uint256 ax, uint256 ay) = _ecMul(BSB22_X, BSB22_Y, QC_VAL);
        (uint256 tx, uint256 ty) = _ecMul(QL_X, QL_Y, L_VAL);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(QR_X, QR_Y, R_VAL);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(QM_X, QM_Y, RL_VAL);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(QO_X, QO_Y, O_VAL);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(QK_X, QK_Y, 1);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(S3_X, S3_Y, COEFF_S1);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(Z_X, Z_Y, COEFF_Z);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(H0_X, H0_Y, COEFF_H0);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(H1_X, H1_Y, COEFF_H1);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);
        (tx, ty) = _ecMul(H2_X, H2_Y, COEFF_H2);
        (ax, ay) = _ecAdd(ax, ay, tx, ty);

        // Log the linearized digest for comparison
        // If Fe produces the same point, the MSM is correct
        // and the bug is in the KZG section
        require(ax != 0 || ay != 0, "linearized digest is zero");

        // Verify rl is correct
        uint256 R_MOD = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
        require(mulmod(L_VAL, R_VAL, R_MOD) == RL_VAL, "rl wrong");
    }
}
