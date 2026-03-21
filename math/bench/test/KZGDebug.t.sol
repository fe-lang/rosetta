// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Full KZG batch verify computation in Solidity to compare against Fe.
/// Uses the SAME algorithm as plonk.fe verify(), same inputs.
/// If this pairing passes, the Fe bug is in the MSM/memory layer.
contract KZGDebugTest {
    uint256 constant R_MOD = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    uint256 constant P_MOD = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;

    function _mul(uint256 px, uint256 py, uint256 s) internal view returns (uint256 rx, uint256 ry) {
        assembly {
            let p := mload(0x40)
            mstore(p, px) mstore(add(p,0x20), py) mstore(add(p,0x40), s)
            if iszero(staticcall(gas(), 7, p, 0x60, p, 0x40)) { revert(0,0) }
            rx := mload(p) ry := mload(add(p,0x20))
        }
    }
    function _add(uint256 ax, uint256 ay, uint256 bx, uint256 by) internal view returns (uint256 rx, uint256 ry) {
        assembly {
            let p := mload(0x40)
            mstore(p, ax) mstore(add(p,0x20), ay) mstore(add(p,0x40), bx) mstore(add(p,0x60), by)
            if iszero(staticcall(gas(), 6, p, 0x80, p, 0x40)) { revert(0,0) }
            rx := mload(p) ry := mload(add(p,0x20))
        }
    }
    function _neg(uint256 px, uint256 py) internal pure returns (uint256, uint256) {
        return (px, P_MOD - py);
    }

    function test_fullKZGBatchVerify() public view {
        // Linearized digest from 11-point MSM (computed in MSMDebug test)
        uint256 linX = 1575458055017171105408711331291204699216370663912059612473357649780793422698;
        uint256 linY = 10173197263037694052157142274479355590956317525637997381532513980986942474182;

        // Known values
        uint256 zeta = 0x0227111bcd5ae9b5ccc86db9db22c0bc52093a3224afcce75d7891aa2e0fed86;
        uint256 const_lin = 0x22eb75080a77724bc8dc8c0548f18bef1975fa6c302909af13c960db6c585954;
        uint256 l = 0x2a2af70b568d007ce53077a078437c2acf6cad206354b0ffa823b4de87918a05;
        uint256 r = 0x03a674ce289759e10b9da150b523d55886b63dc8526f0e36132edb5239c0c238;
        uint256 o = 0x19d465a94658e64d3798897c8438352029a3d285a049af99ff195c36359c16d0;
        uint256 s1 = 0x086e2bbb1679e24af18ee4aac62fded55640735e7c6aeda82abe2c01a3f307c9;
        uint256 s2 = 0x0dad3ef6870691a71276c4f6f185fb14cfe8c7a418c26b3620ce09eff0d21a42;
        uint256 qcval = 0x28ecd97e273c00ce59504ccc15bfe8a2d8f87d1bbd7dc63df606b3c975080a6f;
        uint256 zu = 0x2c1660be901029bf87b9796eedddc65aef146a4419ae4a123ee18aacfa9c41d1;
        uint256 omega = 5709868443893258075976348696661355716898495876243883251619397131511003808859;

        // Proof points
        uint256[2] memory proofL = [uint256(0x2dac3ba24f360a6deda246f6d3e9d8080ed09f97126ef9af18c5de05ca340416), uint256(0x054a4430da47cc1a780b8c91f2c4a3347b1523d220bee21f7b10016e0df7e708)];
        uint256[2] memory proofR = [uint256(0x235ff58eb8e9feb8cf75355f3daec83dd4dde0ebe08ca90ea98510aba1585f4f), uint256(0x0d1716e7f3a01ac0ac6f3a1f6130256444c0b25a114f9300abaeb0d0838d29b2)];
        uint256[2] memory proofO = [uint256(0x2c1dbdf8e4d0f950e7d062751c52a03ad451685e0d23b45563aa87a7d74ec1cf), uint256(0x2cff1161e6d5c9272c3892a76adeb9a5aada5d7065c8e41121ebf4bd9d0fb2cc)];
        uint256[2] memory vkS1_ = [uint256(16111562061301112215931665617877464360548491176332584512747295033804502769274), uint256(15035232142063390140879951391784254536324051421746307325879221184372296043705)];
        uint256[2] memory vkS2_ = [uint256(899944321381010541211546037826620464002745326050515852312919625047231523882), uint256(61717668739330555376092528203839789132705738484346798874082062974863965392)];
        uint256[2] memory vkQCP = [uint256(21578473557091588309361521643625606794648013014197133181947992670819103775934), uint256(18236588362476326695195531997097392315059481348147701548685746610417604595065)];
        uint256[2] memory proofZ = [uint256(0x1657a289347c1973783849c4545c7ed8f0ea65f1eb40b31678d627e70b79bfd1), uint256(0x1592517f8902c7364f90126fe04c28381fe12e165adcf82217876359a544e218)];
        uint256[2] memory Wzeta = [uint256(0x24577aded4d6983f59f123e52821f39141c397fcc957b4f7a2a4ede57b55ef10), uint256(0x05e37b2c4f98ccba063aef65967db4e19547a1e18bea96ab8ec861b7a3e085db)];
        uint256[2] memory Wzo = [uint256(0x2a5ab0dadfc301d004d4863346963baebbd7ea536022a8b90cd9b52d865d5c9c), uint256(0x1e6437eaa886f121c46132f1bcd890827f7860cc63e5b27d8319f9b0cab8d27e)];
        uint256[2] memory g1srs = [uint256(14312776538779914388377568895031746459131577658076416373430523308756343304251), uint256(11763105256161367503191792604679297387056316997144156930871823008787082098465)];

        // Compute gamma_kzg (SHA256 of fold transcript)
        uint256 gamma_kzg;
        {
            bytes memory gdata = abi.encodePacked("gamma", bytes32(zeta));
            gdata = abi.encodePacked(gdata, bytes32(linX), bytes32(linY));
            gdata = abi.encodePacked(gdata, bytes32(proofL[0]), bytes32(proofL[1]));
            gdata = abi.encodePacked(gdata, bytes32(proofR[0]), bytes32(proofR[1]));
            gdata = abi.encodePacked(gdata, bytes32(proofO[0]), bytes32(proofO[1]));
            gdata = abi.encodePacked(gdata, bytes32(vkS1_[0]), bytes32(vkS1_[1]));
            gdata = abi.encodePacked(gdata, bytes32(vkS2_[0]), bytes32(vkS2_[1]));
            gdata = abi.encodePacked(gdata, bytes32(vkQCP[0]), bytes32(vkQCP[1]));
            gdata = abi.encodePacked(gdata, bytes32(const_lin), bytes32(l), bytes32(r), bytes32(o), bytes32(s1), bytes32(s2), bytes32(qcval));
            gdata = abi.encodePacked(gdata, bytes32(zu));
            gamma_kzg = uint256(sha256(gdata)) % R_MOD;
        }
        require(gamma_kzg == 0x1c1d9c1c583152477bfc1318a8ea05cbf85e8d309e113c3a8c3b61ce173d10f3, "gamma_kzg wrong");

        // 7-point fold MSM: folded_digest = 1*lin + g*L + g^2*R + g^3*O + g^4*S1 + g^5*S2 + g^6*QCP
        uint256[7] memory gpow;
        gpow[0] = 1;
        for (uint i = 1; i < 7; i++) gpow[i] = mulmod(gpow[i-1], gamma_kzg, R_MOD);

        (uint256 fdx, uint256 fdy) = _mul(linX, linY, gpow[0]);
        (uint256 tx, uint256 ty) = _mul(proofL[0], proofL[1], gpow[1]);
        (fdx, fdy) = _add(fdx, fdy, tx, ty);
        (tx, ty) = _mul(proofR[0], proofR[1], gpow[2]);
        (fdx, fdy) = _add(fdx, fdy, tx, ty);
        (tx, ty) = _mul(proofO[0], proofO[1], gpow[3]);
        (fdx, fdy) = _add(fdx, fdy, tx, ty);
        (tx, ty) = _mul(vkS1_[0], vkS1_[1], gpow[4]);
        (fdx, fdy) = _add(fdx, fdy, tx, ty);
        (tx, ty) = _mul(vkS2_[0], vkS2_[1], gpow[5]);
        (fdx, fdy) = _add(fdx, fdy, tx, ty);
        (tx, ty) = _mul(vkQCP[0], vkQCP[1], gpow[6]);
        (fdx, fdy) = _add(fdx, fdy, tx, ty);
        // fdx, fdy = folded_digest

        // Folded eval
        uint256 feval = 0;
        uint256[7] memory claimed = [const_lin, l, r, o, s1, s2, qcval];
        for (uint i = 0; i < 7; i++) feval = addmod(feval, mulmod(claimed[i], gpow[i], R_MOD), R_MOD);

        // Derive U — gnark Solidity uses a DIFFERENT format than the Rust reference!
        // Solidity: SHA256(folded_digests || W_zeta || Z || W_zo || zeta || gamma_kzg)
        // NO label, NO raw hash chaining, different point order.
        uint256 u_challenge;
        {
            bytes memory udata = abi.encodePacked(
                bytes32(fdx), bytes32(fdy),         // folded_digests
                bytes32(Wzeta[0]), bytes32(Wzeta[1]), // W_zeta
                bytes32(proofZ[0]), bytes32(proofZ[1]), // Z
                bytes32(Wzo[0]), bytes32(Wzo[1]),     // W_zo
                bytes32(zeta),                         // zeta (reduced)
                bytes32(gamma_kzg)                     // gamma_kzg (reduced)
            );
            u_challenge = uint256(sha256(udata)) % R_MOD;
        }

        uint256 shifted_zeta = mulmod(zeta, omega, R_MOD);

        // KZG batch verify
        // folded_quotients = Wzeta + u * Wzo
        (uint256 fqx, uint256 fqy) = _mul(Wzo[0], Wzo[1], u_challenge);
        (fqx, fqy) = _add(Wzeta[0], Wzeta[1], fqx, fqy);

        // folded_evals_commit = G1_SRS * (feval + u * zu)
        uint256 eval_sum = addmod(feval, mulmod(u_challenge, zu, R_MOD), R_MOD);
        (uint256 ecx, uint256 ecy) = _mul(g1srs[0], g1srs[1], eval_sum);

        // point_term = zeta * Wzeta + u*shifted_zeta * Wzo
        (uint256 ptx, uint256 pty) = _mul(Wzeta[0], Wzeta[1], zeta);
        (tx, ty) = _mul(Wzo[0], Wzo[1], mulmod(u_challenge, shifted_zeta, R_MOD));
        (ptx, pty) = _add(ptx, pty, tx, ty);

        // lhs = folded_digest + u*Z - folded_evals_commit + point_term
        (uint256 lhsx, uint256 lhsy) = _mul(proofZ[0], proofZ[1], u_challenge);
        (lhsx, lhsy) = _add(fdx, fdy, lhsx, lhsy);
        (uint256 necx, uint256 necy) = _neg(ecx, ecy);
        (lhsx, lhsy) = _add(lhsx, lhsy, necx, necy);
        (lhsx, lhsy) = _add(lhsx, lhsy, ptx, pty);

        // neg_quotients = -(Wzeta + u*Wzo)
        (uint256 nqx, uint256 nqy) = _neg(fqx, fqy);

        // Pairing check
        // G2[0] = G2 generator, G2[1] = [alpha]G2 (SRS)
        bool ok;
        assembly {
            let p := mload(0x40)
            mstore(p, lhsx) mstore(add(p,0x20), lhsy)
            mstore(add(p,0x40), 11559732032986387107991004021392285783925812861821192530917403151452391805634)
            mstore(add(p,0x60), 10857046999023057135944570762232829481370756359578518086990519993285655852781)
            mstore(add(p,0x80), 4082367875863433681332203403145435568316851327593401208105741076214120093531)
            mstore(add(p,0xa0), 8495653923123431417604973247489272438418190587263600148770280649306958101930)
            mstore(add(p,0xc0), nqx) mstore(add(p,0xe0), nqy)
            mstore(add(p,0x100), 15805639136721018565402881920352193254830339253282065586954346329754995870280)
            mstore(add(p,0x120), 19089565590083334368588890253123139704298730990782503769911324779715431555531)
            mstore(add(p,0x140), 9779648407879205346559610309258181044130619080926897934572699915909528404984)
            mstore(add(p,0x160), 6779728121489434657638426458390319301070371227460768374343986326751507916979)
            let success := staticcall(gas(), 8, p, 0x180, p, 0x20)
            ok := and(success, mload(p))
        }
        require(ok, "PAIRING FAILED");
    }
}
