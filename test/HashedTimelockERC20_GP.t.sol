// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/HashedTimelockERC20_GP.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/TestToken.sol";
import "forge-std/console.sol";

contract HashedTimelockERC20_GP_Test is Test {
    HashedTimelockERC20_GP htlc;
    TestToken token;
    address alice = address(0xA1);
    address bob = address(0xB0);
    address carol = address(0xC0);

    uint256 constant AMOUNT = 100 ether;
    uint256 constant DEPOSIT = 1 ether;
    uint256 constant TIMELOCK = 1 days;
    uint256 constant DEPOSIT_WINDOW = 1 hours;

    bytes32 preimage;
    bytes32 hashlock;

    function setUp() public {
        token = new TestToken();
        htlc = new HashedTimelockERC20_GP();

        preimage = keccak256("secret123");
        hashlock = sha256(abi.encodePacked(preimage));

        token.transfer(alice, 1000 ether);

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        console.log("Setup done. Alice token:", token.balanceOf(alice));
    }

    function createLock() internal returns (bytes32 lockId) {
        vm.startPrank(alice);
        token.approve(address(htlc), AMOUNT);
        lockId = htlc.createLock(bob, address(token), AMOUNT, hashlock, TIMELOCK, DEPOSIT, DEPOSIT_WINDOW);
        vm.stopPrank();
        console.log("Lock created:", uint256(lockId));
    }

    /// --- Test cases ---

    function testRefundIfBobNoDeposit() public {
        console.log("=== testRefundIfBobNoDeposit START ===");
        bytes32 lockId = createLock();

        vm.startPrank(alice);
        vm.expectRevert();
        htlc.refund(lockId);
        vm.stopPrank();
        console.log("Refund before depositWindowEnd reverted as expected");

        vm.warp(block.timestamp + DEPOSIT_WINDOW + 1);
        vm.prank(alice);
        htlc.refund(lockId);
        console.log("Refund after depositWindowEnd executed");

        assertEq(token.balanceOf(alice), 1000 ether);
        console.log("Alice token refunded:", token.balanceOf(alice));
        console.log("=== testRefundIfBobNoDeposit END ===");
    }

    function testBobDepositsAndClaims() public {
        console.log("=== testBobDepositsAndClaims START ===");
        bytes32 lockId = createLock();

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        htlc.confirmParticipation{value: DEPOSIT}(lockId);
        console.log("Bob deposited:", DEPOSIT);

        vm.prank(bob);
        htlc.claim(lockId, abi.encodePacked(preimage));
        console.log("Bob claimed with preimage");

        assertEq(token.balanceOf(bob), AMOUNT);
        assertEq(bob.balance, 10 ether);
        console.log("Bob token:", token.balanceOf(bob), "Bob ETH:", bob.balance);
        console.log("=== testBobDepositsAndClaims END ===");
    }

    function testAliceGetsPenaltyIfBobNoClaim() public {
        console.log("=== testAliceGetsPenaltyIfBobNoClaim START ===");
        bytes32 lockId = createLock();

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        htlc.confirmParticipation{value: DEPOSIT}(lockId);
        console.log("Bob deposited");

        vm.warp(block.timestamp + TIMELOCK + 1);
        uint256 aliceBalBefore = alice.balance;

        vm.prank(alice);
        htlc.refund(lockId);
        console.log("Alice refunded after timelock");

        assertEq(token.balanceOf(alice), 1000 ether);
        assertEq(alice.balance, aliceBalBefore + DEPOSIT);
        console.log("Alice token:", token.balanceOf(alice), "Alice ETH:", alice.balance);
        console.log("=== testAliceGetsPenaltyIfBobNoClaim END ===");
    }

    function testClaimWithoutDepositReverts() public {
        console.log("=== testClaimWithoutDepositReverts START ===");
        bytes32 lockId = createLock();

        vm.prank(bob);
        vm.expectRevert();
        htlc.claim(lockId, abi.encodePacked(preimage));
        console.log("Claim without deposit reverted as expected");
        console.log("=== testClaimWithoutDepositReverts END ===");
    }

    function testOnlyReceiverCanClaim() public {
        console.log("=== testOnlyReceiverCanClaim START ===");
        bytes32 lockId = createLock();

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        htlc.confirmParticipation{value: DEPOSIT}(lockId);

        vm.prank(carol);
        vm.expectRevert("Only receiver can claim");
        htlc.claim(lockId, abi.encodePacked(preimage));
        console.log("Unauthorized claim reverted as expected");
        console.log("=== testOnlyReceiverCanClaim END ===");
    }

    function testOnlySenderCanRefund() public {
        console.log("=== testOnlySenderCanRefund START ===");
        bytes32 lockId = createLock();

        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.prank(bob);
        vm.expectRevert("Only sender can refund");
        htlc.refund(lockId);
        console.log("Unauthorized refund reverted as expected");
        console.log("=== testOnlySenderCanRefund END ===");
    }

    function testWrongDepositAmountReverts() public {
        console.log("=== testWrongDepositAmountReverts START ===");
        bytes32 lockId = createLock();

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert("Incorrect deposit amount");
        htlc.confirmParticipation{value: DEPOSIT + 1}(lockId);
        console.log("Wrong deposit amount reverted as expected");
        console.log("=== testWrongDepositAmountReverts END ===");
    }
}
