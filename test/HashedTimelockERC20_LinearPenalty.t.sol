// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/HashedTimelockERC20_LinearPenalty.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/TestToken.sol";
import "forge-std/console.sol";

contract HashedTimelockERC20_LinearPenaltyTest is Test {
    HashedTimelockERC20_LinearPenalty lockContract;
    TestToken token;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant AMOUNT = 1000 ether;
    uint256 constant DEPOSIT = 1 ether;
    uint256 constant TIMELOCK = 1 days;
    uint256 constant TIMEBASED = 12 hours;
    uint256 constant DEPOSIT_WINDOW = 1 hours;

    bytes32 hashlock;
    bytes preimage;

    function setUp() public {
        lockContract = new HashedTimelockERC20_LinearPenalty();
        token = new TestToken();

        // fund Alice and Bob
        token.transfer(alice, AMOUNT);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);

        // preimage & hashlock
        preimage = abi.encodePacked("secret");
        hashlock = sha256(preimage);

        token.transfer(alice, AMOUNT);
        // Alice approve token transfer
        vm.startPrank(alice);
        token.approve(address(lockContract), AMOUNT);

        // create lock
        lockContract.createLock(bob, address(token), AMOUNT, hashlock, TIMELOCK, TIMEBASED, DEPOSIT, DEPOSIT_WINDOW);
        vm.stopPrank();
    }

    // 1. Claim before penalty window => penalty = 0
    function testClaimBeforePenaltyWindow() public {
        vm.startPrank(bob);
        lockContract.confirmParticipation{value: DEPOSIT}(hashlock);

        // claim immediately (before unlockTime - timeBased)
        lockContract.claim(hashlock, preimage);

        console.log("Bob token balance:", token.balanceOf(bob));
        console.log("Bob ETH balance:", bob.balance);

        // Bob should receive all tokens
        assertEq(token.balanceOf(bob), AMOUNT);
        // Deposit refunded fully (since penalty=0)
        assertEq(bob.balance, 10 ether);
        vm.stopPrank();
    }

    // 2. Claim exactly at penalty window start
    function testClaimAtPenaltyWindowStart() public {
        vm.startPrank(bob);
        lockContract.confirmParticipation{value: DEPOSIT}(hashlock);

        // warp to unlockTime - timeBased
        vm.warp(block.timestamp + TIMELOCK - TIMEBASED);

        lockContract.claim(hashlock, preimage);

        console.log("Bob token balance:", token.balanceOf(bob));
        console.log("Bob ETH balance:", bob.balance);

        // Penalty likely = 0 (rounding down)
        assertEq(token.balanceOf(bob), AMOUNT);
        assertEq(bob.balance, 10 ether);
        vm.stopPrank();
    }

    // 3. Claim midway in penalty window
    function testClaimMidPenaltyWindow() public {
        vm.startPrank(bob);
        lockContract.confirmParticipation{value: DEPOSIT}(hashlock);

        // warp halfway through timeBased
        vm.warp(block.timestamp + TIMELOCK - (TIMEBASED / 2));

        uint256 balAliceBefore = alice.balance;
        uint256 balBobBefore = bob.balance;

        lockContract.claim(hashlock, preimage);

        // Penalty should be >0 and < deposit
        uint256 balAliceAfter = alice.balance;
        uint256 balBobAfter = bob.balance;

        console.log("Penalty paid to Alice:", balAliceAfter - balAliceBefore);
        console.log("Bob deposit refunded:", balBobAfter - balBobBefore);

        assertGt(balAliceAfter, balAliceBefore);
        assertLt(balAliceAfter - balAliceBefore, DEPOSIT);
        assertEq(balBobAfter + balAliceAfter, balAliceBefore + balBobBefore + DEPOSIT);
    }

    // 4. Claim right before unlockTime => penalty ~ deposit
    function testClaimAtUnlockTimeMinus1() public {
        vm.startPrank(bob);
        lockContract.confirmParticipation{value: DEPOSIT}(hashlock);

        vm.warp(block.timestamp + TIMELOCK - 1);

        uint256 balAliceBefore = alice.balance;

        lockContract.claim(hashlock, preimage);

        uint256 balAliceAfter = alice.balance;

        console.log("Penalty ~ deposit:", balAliceAfter - balAliceBefore);

        // Penalty almost = deposit
        assertApproxEqAbs(balAliceAfter - balAliceBefore, DEPOSIT, 1e14);
        vm.stopPrank();
    }

    // 5. No deposit => Alice refunds after depositWindow
    function testRefundIfNoDeposit() public {
        // new lock without Bob confirming
        preimage = abi.encodePacked("secret2");
        hashlock = sha256(preimage);

        vm.startPrank(alice);
        token.approve(address(lockContract), AMOUNT);
        lockContract.createLock(bob, address(token), AMOUNT, hashlock, TIMELOCK, TIMEBASED, DEPOSIT, DEPOSIT_WINDOW);
        vm.stopPrank();

        // warp past deposit window
        vm.warp(block.timestamp + DEPOSIT_WINDOW + 1);

        vm.startPrank(alice);

        uint256 balAliceBefore = token.balanceOf(alice);
        vm.startPrank(alice);
        lockContract.refund(hashlock);
        uint256 balAliceAfter = token.balanceOf(alice);

        console.log("Alice refunded tokens:", balAliceAfter - balAliceBefore);
        assertEq(token.balanceOf(alice), AMOUNT); // Alice got tokens back
        vm.stopPrank();
    }

    // 6. Wrong deposit amount revert
    function testConfirmWithWrongDepositReverts() public {
        vm.startPrank(bob);
        vm.expectRevert("Incorrect deposit amount");
        lockContract.confirmParticipation{value: DEPOSIT - 1}(hashlock);
        console.log("Revert triggered as expected when Bob sends wrong deposit");
        vm.stopPrank();
    }
}
