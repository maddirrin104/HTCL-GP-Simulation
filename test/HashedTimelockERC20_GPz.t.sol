// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/HashedTimelockERC20_GPz.sol";
import "../src/TestToken.sol";
import "forge-std/console.sol";

contract HashedTimelockERC20_GPz_Test is Test {
    HashedTimelockERC20_GPz htlc;
    TestToken token;

    address Alice = address(0xA1);
    address Bob = address(0xB0);

    uint256 amount = 100 ether;
    uint256 depositRequired = 1 ether;
    uint256 zeta = 0.1 ether;
    uint256 timelock = 1 days;
    uint256 depositWindow = 1 hours;

    bytes32 hashlock;
    bytes preimage = abi.encodePacked("secret");

    function setUp() public {
        htlc = new HashedTimelockERC20_GPz();
        token = new TestToken();

        token.transfer(Alice, 1000 ether);
        hashlock = sha256(preimage);

        console.log("Setup complete. Alice token:", token.balanceOf(Alice));
    }

    /// --- Test cases ---

    /// @dev Bob deposit đúng, claim thành công → mất ζ
    function testBobDepositsAndClaimsWithZeta() public {
        console.log("=== testBobDepositsAndClaimsWithZeta START ===");
        uint256 aliceTokenBefore = token.balanceOf(Alice);

        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();
        console.log("Lock created:", uint256(lockId));

        vm.deal(Bob, depositRequired);
        vm.prank(Bob);
        htlc.confirmParticipation{value: depositRequired}(lockId);
        console.log("Bob deposited:", depositRequired);

        uint256 bobBalanceBefore = Bob.balance;
        uint256 aliceBalanceBefore = Alice.balance;

        vm.prank(Bob);
        htlc.claim(lockId, preimage);
        console.log("Bob claimed with preimage");

        console.log("Bob balance:", Bob.balance, "Alice balance:", Alice.balance);
        console.log("Alice token:", token.balanceOf(Alice), "Bob token:", token.balanceOf(Bob));

        assertEq(Bob.balance, bobBalanceBefore + (depositRequired - zeta));
        assertEq(Alice.balance, aliceBalanceBefore);
        assertEq(token.balanceOf(Alice), aliceTokenBefore - amount);
        assertEq(token.balanceOf(Bob), amount);

        console.log("=== testBobDepositsAndClaimsWithZeta END ===");
    }

    /// @dev Bob không claim → Alice lấy lại token + deposit
    function testBobNoClaimAliceGetsCompensation() public {
        console.log("=== testBobNoClaimAliceGetsCompensation START ===");

        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();
        console.log("Lock created:", uint256(lockId));

        vm.deal(Bob, depositRequired);
        vm.prank(Bob);
        htlc.confirmParticipation{value: depositRequired}(lockId);
        console.log("Bob deposited:", depositRequired);

        vm.warp(block.timestamp + timelock + 1);
        console.log("Time advanced past timelock");

        uint256 aliceEthBefore = Alice.balance;
        uint256 aliceTokenBefore = token.balanceOf(Alice);

        vm.prank(Alice);
        htlc.refund(lockId);
        console.log("Alice refunded");

        console.log("Alice ETH:", Alice.balance - aliceEthBefore);
        console.log("Alice token:", token.balanceOf(Alice) - aliceTokenBefore);

        assertEq(token.balanceOf(Alice), aliceTokenBefore + amount);
        assertEq(Alice.balance, depositRequired);

        console.log("=== testBobNoClaimAliceGetsCompensation END ===");
    }

    /// @dev Claim mà chưa deposit → revert
    function testClaimWithoutDepositReverts() public {
        console.log("=== testClaimWithoutDepositReverts START ===");

        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();
        console.log("Lock created:", uint256(lockId));

        vm.prank(Bob);
        vm.expectRevert("No deposit");
        htlc.claim(lockId, preimage);

        console.log("Claim without deposit reverted as expected");
        console.log("=== testClaimWithoutDepositReverts END ===");
    }

    /// @dev Deposit sai số tiền → revert
    function testWrongDepositAmountReverts() public {
        console.log("=== testWrongDepositAmountReverts START ===");

        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();
        console.log("Lock created:", uint256(lockId));

        vm.deal(Bob, depositRequired + 1);
        vm.prank(Bob);
        vm.expectRevert("Incorrect ETH amount");
        htlc.confirmParticipation{value: depositRequired + 1}(lockId);

        console.log("Wrong deposit reverted as expected");
        console.log("=== testWrongDepositAmountReverts END ===");
    }

    /// @dev Chỉ Bob được claim, chỉ Alice được refund
    function testOnlyRolesCanAct() public {
        console.log("=== testOnlyRolesCanAct START ===");

        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();
        console.log("Lock created:", uint256(lockId));

        address Mallory = address(0x123);
        vm.deal(Mallory, 10 ether);

        vm.prank(Mallory);
        vm.expectRevert("Only receiver");
        htlc.claim(lockId, preimage);
        console.log("Unauthorized claim reverted as expected");

        vm.warp(block.timestamp + timelock + 1);
        vm.prank(Mallory);
        vm.expectRevert("Only sender");
        htlc.refund(lockId);
        console.log("Unauthorized refund reverted as expected");

        console.log("=== testOnlyRolesCanAct END ===");
    }
}
