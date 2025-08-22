// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {HashedTimelockERC20} from "../src/HashedTimelockERC20.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


/// @dev Mock ERC20 token để test
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract HashedTimelockERC20Test is Test {
    HashedTimelockERC20 htlc;
    MockToken token;
    address sender = address(0x1);
    address receiver = address(0x2);
    bytes32 hashlock;
    bytes preimage;
    uint256 amount = 100 ether;
    uint256 timelock = 1 days;

    function setUp() public {
        htlc = new HashedTimelockERC20();
        token = new MockToken();

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
        (, , , , , bool claimed,) = htlc.locks(hashlock);
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
        (, , , , , , bool refunded) = htlc.locks(hashlock);
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

}
