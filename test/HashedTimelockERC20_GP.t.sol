// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/HashedTimelockERC20_GP.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TT") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract HashedTimelockERC20_GP_Test is Test {
    HashedTimelockERC20_GP htlc;
    TestToken token;
    address alice = address(0xA1);
    address bob   = address(0xB0);
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

        // Chuẩn bị preimage + hashlock
        preimage = keccak256("secret123");
        hashlock = sha256(abi.encodePacked(preimage));

        // Alice có token
        token.transfer(alice, 1000 ether);

        // Cho phép forge cheatcode
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
    }

    function createLock() internal returns (bytes32 lockId) {
        vm.startPrank(alice);
        token.approve(address(htlc), AMOUNT);
        lockId = htlc.createLock(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            TIMELOCK,
            DEPOSIT,
            DEPOSIT_WINDOW
        );
        vm.stopPrank();
    }

    /// --- Test cases ---

    function testRefundIfBobNoDeposit() public {
        bytes32 lockId = createLock();

        // Trước depositWindowEnd, Alice chưa refund được
        vm.startPrank(alice);
        vm.expectRevert();
        htlc.refund(lockId);
        vm.stopPrank();

        // Sau depositWindowEnd, Alice refund ngay
        vm.warp(block.timestamp + DEPOSIT_WINDOW + 1);
        vm.prank(alice);
        htlc.refund(lockId);

        assertEq(token.balanceOf(alice), 1000 ether); // token về lại
    }

    function testBobDepositsAndClaims() public {
        bytes32 lockId = createLock();

        // Bob deposit upfront
        vm.deal(bob, 10 ether); // cấp ETH cho Bob
        vm.prank(bob);
        htlc.confirmParticipation{value: DEPOSIT}(lockId);

        // Bob claim trước unlockTime
        vm.prank(bob);
        htlc.claim(lockId, abi.encodePacked(preimage));

        assertEq(token.balanceOf(bob), AMOUNT);
        assertEq(bob.balance, 10 ether); // deposit được refund
    }

    function testAliceGetsPenaltyIfBobNoClaim() public {
        bytes32 lockId = createLock();

        // Bob deposit
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        htlc.confirmParticipation{value: DEPOSIT}(lockId);

        // Hết unlockTime mà Bob không claim
        vm.warp(block.timestamp + TIMELOCK + 1);
        uint256 aliceBalBefore = alice.balance;

        vm.prank(alice);
        htlc.refund(lockId);

        assertEq(token.balanceOf(alice), 1000 ether); // token lại về Alice
        assertEq(alice.balance, aliceBalBefore + DEPOSIT); // nhận luôn deposit
    }

    function testClaimWithoutDepositReverts() public {
        bytes32 lockId = createLock();

        vm.prank(bob);
        vm.expectRevert();
        htlc.claim(lockId, abi.encodePacked(preimage));
    }

    function testOnlyReceiverCanClaim() public {
        bytes32 lockId = createLock();

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        htlc.confirmParticipation{value: DEPOSIT}(lockId);

        // Carol thử claim
        vm.prank(carol);
        vm.expectRevert("Only receiver can claim");
        htlc.claim(lockId, abi.encodePacked(preimage));
    }

    function testOnlySenderCanRefund() public {
        bytes32 lockId = createLock();

        // Bob cố refund
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.prank(bob);
        vm.expectRevert("Only sender can refund");
        htlc.refund(lockId);
    }

    function testWrongDepositAmountReverts() public {
        bytes32 lockId = createLock();

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert("Incorrect deposit amount");
        htlc.confirmParticipation{value: DEPOSIT + 1}(lockId);
    }
}
