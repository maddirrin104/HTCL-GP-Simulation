// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HashedTimelockERC20_GPz is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Lock {
        address sender; // Alice
        address receiver; // Bob
        address tokenContract; // Token bị khóa
        uint256 amount; // Số token
        uint256 unlockTime; // Thời điểm Alice có thể refund
        bool claimed;
        bool refunded;
        // GPζ params
        uint256 depositRequired; // Deposit Bob phải đặt
        uint256 guaranteedCompensation; // ζ
        uint256 depositWindowEnd; // Deadline để Bob deposit
        bool depositConfirmed;
    }

    mapping(bytes32 => Lock) public locks;

    event LockCreated(
        bytes32 indexed lockId,
        address indexed sender,
        address indexed receiver,
        address tokenContract,
        uint256 amount,
        uint256 unlockTime,
        uint256 depositRequired,
        uint256 guaranteedCompensation,
        uint256 depositWindowEnd
    );
    event LockClaimed(bytes32 indexed lockId);
    event LockRefunded(bytes32 indexed lockId, bool dueToNoDeposit);
    event DepositMade(bytes32 indexed lockId, uint256 amount);

    /// Alice tạo lock
    function createLock(
        address _receiver,
        address _tokenContract,
        uint256 _amount,
        bytes32 _hashlock,
        uint256 _timelock,
        uint256 _depositRequired,
        uint256 _guaranteedCompensation,
        uint256 _depositWindow
    ) external returns (bytes32 lockId) {
        require(locks[_hashlock].sender == address(0), "Lock already exists");
        require(_amount > 0, "Amount must be > 0");
        require(_guaranteedCompensation <= _depositRequired, "Guaranteed Minimum Compensation must <= deposit");

        uint256 _unlockTime = block.timestamp + _timelock;

        locks[_hashlock] = Lock({
            sender: msg.sender,
            receiver: _receiver,
            tokenContract: _tokenContract,
            amount: _amount,
            unlockTime: _unlockTime,
            claimed: false,
            refunded: false,
            depositRequired: _depositRequired,
            guaranteedCompensation: _guaranteedCompensation,
            depositWindowEnd: block.timestamp + _depositWindow,
            depositConfirmed: false
        });

        IERC20(_tokenContract).safeTransferFrom(msg.sender, address(this), _amount);

        emit LockCreated(
            _hashlock,
            msg.sender,
            _receiver,
            _tokenContract,
            _amount,
            _unlockTime,
            _depositRequired,
            _guaranteedCompensation,
            block.timestamp + _depositWindow
        );

        return _hashlock;
    }

    /// Bob đặt cọc
    function confirmParticipation(bytes32 _lockId) external payable nonReentrant {
        Lock storage locked = locks[_lockId];
        require(msg.sender == locked.receiver, "Only receiver");
        require(!locked.depositConfirmed, "Already deposited");
        require(block.timestamp <= locked.depositWindowEnd, "Deposit window passed");
        require(msg.value == locked.depositRequired, "Incorrect ETH amount");

        locked.depositConfirmed = true;

        // Ngay lập tức gửi guaranteed compensation ζ cho Alice
        payable(locked.sender).transfer(locked.guaranteedCompensation);

        emit DepositMade(_lockId, msg.value);
    }

    /// Bob claim token
    function claim(bytes32 _lockId, bytes calldata _preimage) external nonReentrant {
        require(sha256(_preimage) == _lockId, "Invalid preimage");

        Lock storage locked = locks[_lockId];
        require(msg.sender == locked.receiver, "Only receiver");
        require(!locked.claimed && !locked.refunded, "Already closed");
        require(block.timestamp < locked.unlockTime, "Expired");
        require(locked.depositConfirmed, "No deposit");

        locked.claimed = true;

        // Transfer token cho Bob
        IERC20(locked.tokenContract).safeTransfer(locked.receiver, locked.amount);

        // Refund phần deposit còn lại (deposit – ζ)
        uint256 refundAmount = locked.depositRequired - locked.guaranteedCompensation;
        if (refundAmount > 0) {
            payable(locked.receiver).transfer(refundAmount);
        }

        emit LockClaimed(_lockId);
    }

    /// Alice refund nếu Bob không claim
    function refund(bytes32 _lockId) external nonReentrant {
        Lock storage locked = locks[_lockId];
        require(msg.sender == locked.sender, "Only sender");
        require(!locked.claimed && !locked.refunded, "Already closed");

        if (!locked.depositConfirmed && block.timestamp > locked.depositWindowEnd) {
            // Bob chưa deposit → refund token ngay
            locked.refunded = true;
            IERC20(locked.tokenContract).safeTransfer(locked.sender, locked.amount);
            emit LockRefunded(_lockId, true);
        } else {
            require(block.timestamp >= locked.unlockTime, "Too early");
            locked.refunded = true;
            IERC20(locked.tokenContract).safeTransfer(locked.sender, locked.amount);

            // Nếu Bob có deposit mà không claim → Alice nhận toàn bộ phần deposit còn lại
            if (locked.depositConfirmed) {
                uint256 penalty = locked.depositRequired - locked.guaranteedCompensation;
                if (penalty > 0) {
                    payable(locked.sender).transfer(penalty);
                }
            }

            emit LockRefunded(_lockId, false);
        }
    }
}
