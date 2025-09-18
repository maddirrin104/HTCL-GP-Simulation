// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MPHTLC {
    struct LockContract {
        address payable sender;
        address payable receiver;
        uint256 amount;
        bytes32 hashlock;
        uint256 timelock; // UNIX timestamp - thời điểm hết hạn khóa
        bool withdrawn;
        bool refunded;
        bytes32 preimage;
    }

    // Địa chỉ công khai đại diện cho nhóm ký ngưỡng (để xác thực chữ ký)
    address public thresholdSigner;

    // Bảng ánh xạ ID hợp đồng -> thông tin LockContract
    mapping(bytes32 => LockContract) public contracts;

    // Sự kiện phát ra khi tạo mới một hợp đồng HTLC
    event HTLCNew(bytes32 indexed contractId, address indexed sender, address indexed receiver,
                 uint256 amount, bytes32 hashlock, uint256 timelock);
    // Sự kiện khi rút tiền thành công (tiết lộ preimage)
    event HTLCWithdraw(bytes32 indexed contractId, bytes32 preimage);
    // Sự kiện khi hoàn tiền thành công
    event HTLCRefund(bytes32 indexed contractId);

    constructor(address _thresholdSigner) {
        thresholdSigner = _thresholdSigner;
    }

    /**
     * @dev Tạo một hợp đồng HTLC mới và khóa một khoản tiền.
     * @param _receiver Địa chỉ người nhận (được phép rút tiền nếu có preimage).
     * @param _hashlock Giá trị băm khóa (hashlock) đã thỏa thuận.
     * @param _timelock Thời điểm UNIX (giây) mà sau đó sender có thể refund.
     * @return contractId Mã ID duy nhất của hợp đồng HTLC mới.
     */
    function newContract(address payable _receiver, bytes32 _hashlock, uint256 _timelock)
        external payable returns (bytes32 contractId)
    {
        require(msg.value > 0, "No funds sent");  
        require(_timelock > block.timestamp, "timelock must be in the future");
        // Tạo ID duy nhất cho hợp đồng khóa này
        contractId = sha256(abi.encodePacked(msg.sender, _receiver, msg.value, _hashlock, _timelock));
        require(contracts[contractId].sender == address(0), "Contract already exists");

        // Lưu thông tin hợp đồng khóa vào mapping
        contracts[contractId] = LockContract({
            sender: payable(msg.sender),
            receiver: _receiver,
            amount: msg.value,
            hashlock: _hashlock,
            timelock: _timelock,
            withdrawn: false,
            refunded: false,
            preimage: 0x0
        });
        emit HTLCNew(contractId, msg.sender, _receiver, msg.value, _hashlock, _timelock);
    }

    /**
     * @dev Rút tiền bằng cách cung cấp bí mật preimage, yêu cầu kèm chữ ký ngưỡng hợp lệ.
     * @param _contractId ID của hợp đồng HTLC muốn rút.
     * @param _preimage Bí mật ban đầu mà hash sẽ phải khớp với hashlock.
     * @param _v, _r, _s Các tham số chữ ký ECDSA (chuẩn) từ nhóm ký ngưỡng trên thông điệp _contractId.
     * @return success Trả về true nếu rút tiền thành công.
     */
    function withdraw(bytes32 _contractId, bytes32 _preimage, uint8 _v, bytes32 _r, bytes32 _s)
        external returns (bool success)
    {
        LockContract storage c = contracts[_contractId];
        require(c.sender != address(0), "Contract not found");              // Hợp đồng phải tồn tại
        require(msg.sender == c.receiver, "Only receiver can withdraw");    // Chỉ cho phép đúng người nhận rút
        require(!c.withdrawn, "Already withdrawn");                        // Chưa từng được rút trước đó
        require(!c.refunded, "Already refunded");                          // Chưa hoàn tiền trước đó
        require(block.timestamp < c.timelock, "Timelock expired");         // Còn trong thời hạn cho phép
        // Kiểm tra preimage có khớp hashlock không
        require(c.hashlock == sha256(abi.encodePacked(_preimage)), "Invalid preimage");
        // Xác thực chữ ký ngưỡng: phải khớp với địa chỉ thresholdSigner đã lưu
        address signer = ecrecover(_contractId, _v, _r, _s);
        require(signer == thresholdSigner, "Invalid threshold signature");

        // Cập nhật trạng thái đã rút và lưu lại preimage
        c.withdrawn = true;
        c.preimage = _preimage;
        // Chuyển tiền cho receiver
        c.receiver.transfer(c.amount);
        emit HTLCWithdraw(_contractId, _preimage);
        return true;
    }

    /**
     * @dev Hoàn tiền cho sender sau khi hết thời gian khóa (nếu chưa rút).
     * @param _contractId ID của HTLC muốn refund.
     * @return success Trả về true nếu hoàn tiền thành công.
     */
    function refund(bytes32 _contractId) external returns (bool success) {
        LockContract storage c = contracts[_contractId];
        require(c.sender != address(0), "Contract not found");
        require(msg.sender == c.sender, "Only sender can refund");
        require(!c.withdrawn, "Already withdrawn");
        require(!c.refunded, "Already refunded");
        require(block.timestamp >= c.timelock, "Timelock not yet passed");

        // Đánh dấu đã refund
        c.refunded = true;
        // Chuyển tiền lại cho sender
        c.sender.transfer(c.amount);
        emit HTLCRefund(_contractId);
        return true;
    }
}
