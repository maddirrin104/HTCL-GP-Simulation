// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MP_HTLC.sol";

contract MPHTLCTest is Test {
    MPHTLC ethContract; // giả lập hợp đồng trên Ethereum
    MPHTLC polyContract; // giả lập hợp đồng trên Polygon

    address payable alice; // Alice sẽ nhận trên Polygon và gửi trên Ethereum
    address payable bob; // Bob sẽ nhận trên Ethereum và gửi trên Polygon

    uint256 thresholdPrivKey; // private key giả lập của nhóm chữ ký ngưỡng
    address thresholdAddr; // địa chỉ công khai tương ứng (thresholdSigner)

    bytes32 secret; // preimage
    bytes32 hashlock; // sha256(preimage)
    uint256 timelockEth; // T_Eth
    uint256 timelockPoly; // T_Poly (> T_Eth)

    function setUp() public {
        console.log("=== SETUP ===");
        alice = payable(vm.addr(1));
        bob = payable(vm.addr(2));

        // Khởi tạo key của 'nhóm ngưỡng' (demo)
        thresholdPrivKey = 0xABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789;
        thresholdAddr = vm.addr(thresholdPrivKey);

        // Triển khai 2 hợp đồng với cùng thresholdSigner
        ethContract = new MPHTLC(thresholdAddr);
        polyContract = new MPHTLC(thresholdAddr);

        // Cấp tiền ban đầu cho 2 ví
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        // Tạo preimage & hashlock
        secret = bytes32("my secret preimage");
        hashlock = sha256(abi.encodePacked(secret));

        console.log("Preimage (secret):");
        console.logBytes32(secret);
        console.log("Hashlock = sha256(secret):");
        console.logBytes32(hashlock);

        // Thiết lập timelock: Polygon dài hơn Ethereum
        timelockEth = block.timestamp + 100;
        timelockPoly = block.timestamp + 200;

        console.log("Current block.timestamp:");
        console.logUint(block.timestamp);
        console.log("timelockEth:");
        console.logUint(timelockEth);
        console.log("timelockPoly:");
        console.logUint(timelockPoly);
        console.log("====================\n");
    }

    // Helper: in trạng thái 1 hợp đồng theo contractId
    function _logContractState(MPHTLC c, bytes32 id, string memory label) internal view {
        (address s, address r, uint256 amt, bytes32 h, uint256 t, bool withdrawn, bool refunded, bytes32 pre) =
            c.contracts(id);

        console.log(string(abi.encodePacked("== STATE: ", label, " ==")));
        console.log("sender:");
        console.logAddress(s);
        console.log("receiver:");
        console.logAddress(r);
        console.log("amount (wei):");
        console.logUint(amt);
        console.log("hashlock:");
        console.logBytes32(h);
        console.log("timelock:");
        console.logUint(t);
        console.log("withdrawn:");
        console.logBool(withdrawn);
        console.log("refunded:");
        console.logBool(refunded);
        console.log("stored preimage:");
        console.logBytes32(pre);
        console.log("==========================\n");
    }

    // --------- TEST 1: Hoán đổi thành công (redeem cả 2 phía) ----------
    function testAtomicSwapSuccess_withLogs() public {
        console.log("=== TEST: Atomic swap success ===\n");

        // 1) Alice khóa 0.5 ETH trên Ethereum cho Bob
        console.log("LOCK on Ethereum by Alice");
        console.log("caller (alice):");
        console.logAddress(alice);
        console.log("amount (wei):");
        console.logUint(0.5 ether);
        console.log("hashlock:");
        console.logBytes32(hashlock);
        console.log("timelockEth:");
        console.logUint(timelockEth);

        vm.prank(alice);
        bytes32 idEth = ethContract.newContract{value: 0.5 ether}(bob, hashlock, timelockEth);
        console.log("-> lock() sent. block.timestamp:");
        console.logUint(block.timestamp);
        _logContractState(ethContract, idEth, "ETH AFTER LOCK");

        // 2) Bob khóa 0.5 ETH (giả: MATIC) trên Polygon cho Alice
        console.log("LOCK on Polygon by Bob");
        console.log("caller (bob):");
        console.logAddress(bob);
        console.log("amount (wei):");
        console.logUint(0.5 ether);
        console.log("hashlock:");
        console.logBytes32(hashlock);
        console.log("timelockPoly:");
        console.logUint(timelockPoly);

        vm.prank(bob);
        bytes32 idPoly = polyContract.newContract{value: 0.5 ether}(alice, hashlock, timelockPoly);
        console.log("-> lock() sent. block.timestamp:");
        console.logUint(block.timestamp);
        _logContractState(polyContract, idPoly, "POLY AFTER LOCK");

        // Assertions sau lock
        {
            (address s, address r, uint256 amt,, uint256 t, bool w, bool f,) = ethContract.contracts(idEth);
            console.log(
                "ASSERT (ETH): sender==alice, receiver==bob, amount==0.5e, timelock==timelockEth, !withdrawn, !refunded"
            );
            console.log("sender:");
            console.logAddress(s);
            console.log("receiver:");
            console.logAddress(r);
            console.log("amount (wei):");
            console.logUint(amt);
            console.log("timelock:");
            console.logUint(t);
            console.log("withdrawn:");
            console.logBool(w);
            console.log("refunded:");
            console.logBool(f);

            assertEq(s, alice, "ETH: sender mismatch");
            assertEq(r, bob, "ETH: receiver mismatch");
            assertEq(amt, 0.5 ether, "ETH: amount mismatch");
            assertEq(t, timelockEth, "ETH: timelock mismatch");
            assertFalse(w, "ETH: should not be withdrawn");
            assertFalse(f, "ETH: should not be refunded");
            console.log("-> PASS: ETH lock state OK\n");
        }

        // 3) Alice redeem trên Polygon (cung cấp preimage + chữ ký ngưỡng)
        console.log("REDEEM on Polygon by Alice");
        console.log("preimage:");
        console.logBytes32(secret);
        (uint8 vPoly, bytes32 rPoly, bytes32 sPoly) = vm.sign(thresholdPrivKey, idPoly);
        console.log("threshold signer:");
        console.logAddress(thresholdAddr);
        console.log("idPoly to sign:");
        console.logBytes32(idPoly);

        vm.prank(alice);
        bool okPoly = polyContract.withdraw(idPoly, secret, vPoly, rPoly, sPoly);
        console.log("-> withdraw() poly result:");
        console.logBool(okPoly);
        _logContractState(polyContract, idPoly, "POLY AFTER REDEEM");

        assertTrue(okPoly, "Polygon withdraw failed");
        console.log("-> PASS: Polygon redeem OK\n");

        // 4) Bob thấy preimage và redeem trên Ethereum
        console.log("REDEEM on Ethereum by Bob");
        (uint8 vEth, bytes32 rEth, bytes32 sEth) = vm.sign(thresholdPrivKey, idEth);
        console.log("threshold signer:");
        console.logAddress(thresholdAddr);
        console.log("idEth to sign:");
        console.logBytes32(idEth);

        vm.prank(bob);
        bool okEth = ethContract.withdraw(idEth, secret, vEth, rEth, sEth);
        console.log("-> withdraw() eth result:");
        console.logBool(okEth);
        _logContractState(ethContract, idEth, "ETH AFTER REDEEM");

        assertTrue(okEth, "Ethereum withdraw failed");
        console.log("-> PASS: Ethereum redeem OK\n");

        // Kiểm tra preimage đã lưu và cờ trạng thái
        {
            (,,,,, bool wEth, bool fEth, bytes32 preEth) = ethContract.contracts(idEth);
            (,,,,, bool wPoly, bool fPoly, bytes32 prePoly) = polyContract.contracts(idPoly);

            console.log("ASSERT post-redeem flags & stored preimage");
            console.log("ETH withdrawn/refunded:");
            console.logBool(wEth);
            console.logBool(fEth);
            console.log("POLY withdrawn/refunded:");
            console.logBool(wPoly);
            console.logBool(fPoly);
            console.log("stored preimage (ETH):");
            console.logBytes32(preEth);
            console.log("stored preimage (POLY):");
            console.logBytes32(prePoly);

            assertTrue(wEth, "ETH: should be withdrawn");
            assertFalse(fEth, "ETH: should not be refunded");
            assertTrue(wPoly, "POLY: should be withdrawn");
            assertFalse(fPoly, "POLY: should not be refunded");
            assertEq(preEth, secret, "ETH: stored preimage mismatch");
            assertEq(prePoly, secret, "POLY: stored preimage mismatch");
            console.log("-> PASS: flags & preimage OK\n");
        }

        // Kiểm tra số dư cuối cùng
        console.log("Balances after swap");
        console.log("alice.balance:");
        console.logUint(alice.balance);
        console.log("bob.balance:");
        console.logUint(bob.balance);

        assertEq(alice.balance, 1 ether, "Alice final balance incorrect");
        assertEq(bob.balance, 1 ether, "Bob final balance incorrect");
        console.log("-> PASS: final balances OK\n");
    }

    // --------- TEST 2: Hết hạn -> refund cả 2 phía ----------
    function testRefundScenario_withLogs() public {
        console.log("=== TEST: Refund scenario ===\n");

        // 1) Cả hai lock (0.3 ETH mỗi bên)
        console.log("LOCK on Ethereum by Alice (0.3 ETH)");
        vm.prank(alice);
        bytes32 idEth = ethContract.newContract{value: 0.3 ether}(bob, hashlock, timelockEth);
        _logContractState(ethContract, idEth, "ETH AFTER LOCK");

        console.log("LOCK on Polygon by Bob (0.3 ETH)");
        vm.prank(bob);
        bytes32 idPoly = polyContract.newContract{value: 0.3 ether}(alice, hashlock, timelockPoly);
        _logContractState(polyContract, idPoly, "POLY AFTER LOCK");

        // 2) Không ai redeem -> warp thời gian đi qua cả 2 timelock
        console.log("Time travel (warp) beyond both timelocks");
        console.log("current block.timestamp:");
        console.logUint(block.timestamp);
        vm.warp(timelockPoly + 1);
        console.log("after warp block.timestamp:");
        console.logUint(block.timestamp);
        console.log("timelockEth / timelockPoly:");
        console.logUint(timelockEth);
        console.logUint(timelockPoly);

        // 3) Refund: Bob trên Polygon
        console.log("REFUND on Polygon by Bob");
        vm.prank(bob);
        bool refundedPoly = polyContract.refund(idPoly);
        console.log("-> refund() poly result:");
        console.logBool(refundedPoly);
        _logContractState(polyContract, idPoly, "POLY AFTER REFUND");
        assertTrue(refundedPoly, "Bob failed to refund on Polygon");
        console.log("-> PASS: Polygon refund OK\n");

        // 4) Refund: Alice trên Ethereum
        console.log("REFUND on Ethereum by Alice");
        vm.prank(alice);
        bool refundedEth = ethContract.refund(idEth);
        console.log("-> refund() eth result:");
        console.logBool(refundedEth);
        _logContractState(ethContract, idEth, "ETH AFTER REFUND");
        assertTrue(refundedEth, "Alice failed to refund on Ethereum");
        console.log("-> PASS: Ethereum refund OK\n");

        // 5) Kiểm tra cờ và số dư
        {
            (,,,,, bool wEth, bool fEth,) = ethContract.contracts(idEth);
            (,,,,, bool wPoly, bool fPoly,) = polyContract.contracts(idPoly);

            console.log("ASSERT post-refund flags");
            console.log("ETH withdrawn/refunded:");
            console.logBool(wEth);
            console.logBool(fEth);
            console.log("POLY withdrawn/refunded:");
            console.logBool(wPoly);
            console.logBool(fPoly);

            assertFalse(wEth, "ETH: should not be withdrawn");
            assertTrue(fEth, "ETH: should be refunded");
            assertFalse(wPoly, "POLY: should not be withdrawn");
            assertTrue(fPoly, "POLY: should be refunded");
            console.log("-> PASS: refund flags OK\n");
        }

        console.log("Balances after refunds");
        console.log("alice.balance:");
        console.logUint(alice.balance);
        console.log("bob.balance:");
        console.logUint(bob.balance);

        assertEq(alice.balance, 1 ether, "Alice should have original balance back");
        assertEq(bob.balance, 1 ether, "Bob should have original balance back");
        console.log("-> PASS: final balances after refund OK\n");
    }
}
