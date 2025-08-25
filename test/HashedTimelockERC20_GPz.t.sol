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

        // cấp token cho Alice
        token.transfer(Alice, 1000 ether);

        // hashlock cho preimage
        hashlock = sha256(preimage);
    }

    /// @dev Bob deposit đúng, claim thành công → mất ζ
    function testBobDepositsAndClaimsWithZeta() public {
        // Lưu token balance của Alice trước khi tạo lock
        uint256 aliceTokenBefore = token.balanceOf(Alice);

        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();

        // Bob deposit đủ
        vm.deal(Bob, 1 ether);
        vm.prank(Bob);
        htlc.confirmParticipation{value: depositRequired}(lockId);

        // Bob claim
        uint256 bobBalanceBefore = Bob.balance;
        uint256 aliceBalanceBefore = Alice.balance;

        vm.prank(Bob);
        htlc.claim(lockId, preimage);

        // Kiểm tra: Bob chỉ nhận lại deposit - ζ
        assertEq(Bob.balance, bobBalanceBefore + (depositRequired - zeta));

        // Alice giữ lại ζ
        assertEq(Alice.balance, aliceBalanceBefore);

        // Alice bị giảm token
        assertEq(token.balanceOf(Alice), aliceTokenBefore - amount);

        // Bob nhận token
        assertEq(token.balanceOf(Bob), amount);
    }

    /// @dev Bob không claim → Alice lấy lại token + deposit
    function testBobNoClaimAliceGetsCompensation() public {
        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();

        vm.deal(Bob, depositRequired);
        vm.prank(Bob);
        htlc.confirmParticipation{value: depositRequired}(lockId);

        // Fast forward qua unlockTime
        vm.warp(block.timestamp + timelock + 1);

        // Alice refund
        uint256 aliceEthBefore = Alice.balance;
        uint256 aliceTokenBefore = token.balanceOf(Alice);

        vm.prank(Alice);
        htlc.refund(lockId);

        // Alice nhận lại token
        assertEq(token.balanceOf(Alice), aliceTokenBefore + amount);

        // Alice cũng nhận toàn bộ deposit (bao gồm ζ)
        assertEq(Alice.balance, depositRequired);
    }

    /// @dev Claim mà chưa deposit → revert
    function testClaimWithoutDepositReverts() public {
        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();

        vm.prank(Bob);
        vm.expectRevert("No deposit");
        htlc.claim(lockId, preimage);
    }

    /// @dev Deposit sai số tiền → revert
    function testWrongDepositAmountReverts() public {
        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();

        vm.deal(Bob, depositRequired + 1);
        vm.prank(Bob);
        vm.expectRevert("Incorrect ETH amount");
        htlc.confirmParticipation{value: depositRequired + 1}(lockId);
    }

    /// @dev Chỉ Bob được claim, chỉ Alice được refund
    function testOnlyRolesCanAct() public {
        vm.startPrank(Alice);
        token.approve(address(htlc), amount);
        bytes32 lockId =
            htlc.createLock(Bob, address(token), amount, hashlock, timelock, depositRequired, zeta, depositWindow);
        vm.stopPrank();

        // Một người khác cố claim
        address Mallory = address(0x123);
        vm.deal(Mallory, 10 ether);

        vm.prank(Mallory);
        vm.expectRevert("Only receiver");
        htlc.claim(lockId, preimage);

        // Một người khác cố refund
        vm.warp(block.timestamp + timelock + 1);
        vm.prank(Mallory);
        vm.expectRevert("Only sender");
        htlc.refund(lockId);
    }
}
