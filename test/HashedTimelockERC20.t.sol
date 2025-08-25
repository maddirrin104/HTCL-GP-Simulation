// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {HashedTimelockERC20} from "../src/HashedTimelockERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";
import "../src/TestToken.sol";

contract HashedTimelockERC20Test is Test {
    HashedTimelockERC20 htlc;
    TestToken token;
    address sender = address(0x1);
    address receiver = address(0x2);
    bytes32 hashlock;
    bytes preimage;
    uint256 amount = 100 ether;
    uint256 timelock = 1 days;

    function setUp() public {
        htlc = new HashedTimelockERC20();
        token = new TestToken();

        // cấp token cho sender
        token.transfer(sender, amount);

        // preimage và hashlock
        preimage = abi.encodePacked("my-secret");
        hashlock = sha256(preimage);
    }

    function testLockSuccess() public {
        vm.startPrank(sender);
        token.approve(address(htlc), amount);

        bytes32 lockId = htlc.lock(receiver, address(token), amount, hashlock, timelock);

        assertEq(lockId, hashlock);
        (address _sender, address _receiver,, uint256 _amount,, bool claimed, bool refunded) = htlc.locks(lockId);
        assertEq(_sender, sender);
        assertEq(_receiver, receiver);
        assertEq(_amount, amount);
        assertFalse(claimed);
        assertFalse(refunded);

        vm.stopPrank();
    }

    function testClaimSuccess() public {
        vm.startPrank(sender);
        token.approve(address(htlc), amount);
        htlc.lock(receiver, address(token), amount, hashlock, timelock);
        vm.stopPrank();

        // claim
        vm.startPrank(receiver);
        htlc.claim(hashlock, preimage);
        assertEq(token.balanceOf(receiver), amount);
        (,,,,, bool claimed,) = htlc.locks(hashlock);
        assertTrue(claimed);
        vm.stopPrank();
    }

    function testRefundSuccess() public {
        vm.startPrank(sender);
        token.approve(address(htlc), amount);
        htlc.lock(receiver, address(token), amount, hashlock, timelock);
        vm.stopPrank();

        // fast forward thời gian
        vm.warp(block.timestamp + timelock + 1);

        vm.startPrank(sender);
        htlc.refund(hashlock);
        assertEq(token.balanceOf(sender), amount);
        (,,,,,, bool refunded) = htlc.locks(hashlock);
        assertTrue(refunded);
        vm.stopPrank();
    }

    function testRevertWhenClaimWithWrongPreimage() public {
        vm.startPrank(sender);
        token.approve(address(htlc), amount);
        htlc.lock(receiver, address(token), amount, hashlock, timelock);
        vm.stopPrank();

        // claim với sai preimage
        vm.startPrank(receiver);
        bytes memory wrongPreimage = abi.encodePacked("wrong-secret");

        vm.expectRevert("Invalid preimage");
        htlc.claim(hashlock, wrongPreimage);
        vm.stopPrank();
    }

    function testRevertWhenRefundBeforeUnlock() public {
        vm.startPrank(sender);
        token.approve(address(htlc), amount);
        htlc.lock(receiver, address(token), amount, hashlock, timelock);
        vm.stopPrank();

        // chưa đến unlockTime
        vm.startPrank(sender);

        vm.expectRevert(); // revert generic vì require(block.timestamp >= locked.unlockTime)
        htlc.refund(hashlock);

        vm.stopPrank();
    }

    // kịch bản Alice lock token và Bob không claim
    function testGriefingAttack() public {
        // Khởi tạo nhân vật
        address alice = address(0xA11CE);
        address bob = address(0xB0B);

        uint256 amount = 50 ether;
        uint256 timelock = 3 days;

        // Cấp token cho Alice
        token.transfer(alice, amount);

        // Alice lock token với Bob là receiver
        vm.startPrank(alice);
        token.approve(address(htlc), amount);

        bytes memory preimage = abi.encodePacked("attack-secret");
        bytes32 hashlock = sha256(preimage);

        uint256 startTime = block.timestamp;
        htlc.lock(bob, address(token), amount, hashlock, timelock);
        vm.stopPrank();

        // Bob KHÔNG gọi claim => Alice bị kẹt token

        // Fast forward: thử refund sớm sẽ bị revert
        vm.startPrank(alice);
        vm.expectRevert();
        htlc.refund(hashlock);
        vm.stopPrank();

        // Tiến tới đúng thời điểm unlock
        vm.warp(startTime + timelock);

        // Alice refund thành công
        vm.startPrank(alice);
        htlc.refund(hashlock);
        vm.stopPrank();

        // Đo thời gian Alice bị khóa token
        uint256 elapsed = block.timestamp - startTime;
        console.log("Alice's tokens were locked for", elapsed, "seconds");

        // Đảm bảo token được trả lại
        assertEq(token.balanceOf(alice), amount);
    }

    // thử lại attack với các timelock khác nhau
    function testGriefingAttackWithDifferentTimelocks() public {
        address alice = address(0xA11CE);
        address bob   = address(0xB0B);

        uint256 amount = 100 ether;
        uint256[] memory timelocks = new uint256[](3);

        timelocks[0] = 1 hours;
        timelocks[1] = 12 hours;
        timelocks[2] = 24 hours;

        // Cấp token cho Alice
        token.transfer(alice, amount * timelocks.length);

        for (uint i = 0; i < timelocks.length; i++) {
            uint256 tl = timelocks[i];

            // Reset lại preimage/hashlock cho mỗi vòng
            bytes memory preimage = abi.encodePacked("attack-secret", i);
            bytes32 hashlock = sha256(preimage);

            // Alice lock token cho Bob
            vm.startPrank(alice);
            token.approve(address(htlc), amount);
            uint256 startTime = block.timestamp;
            htlc.lock(bob, address(token), amount, hashlock, tl);
            vm.stopPrank();

            // Bob KHÔNG claim

            // Alice thử refund sớm -> revert
            vm.startPrank(alice);
            vm.expectRevert();
            htlc.refund(hashlock);
            vm.stopPrank();

            // Tiến tới thời điểm unlock
            vm.warp(startTime + tl);

            // Alice refund thành công
            vm.startPrank(alice);
            htlc.refund(hashlock);
            vm.stopPrank();

            uint256 elapsed = block.timestamp - startTime;

            console.log("Timelock = %s seconds", tl);
            console.log("Alice's tokens were locked for %s seconds", elapsed);

            // Xác minh Alice nhận lại đủ token
            assertEq(token.balanceOf(alice), amount * (timelocks.length));
        }
    }
}
