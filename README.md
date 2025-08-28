# HASHED TIME-LOCK CONTRACTS - GRIEFING PENALTY
## HTCL - GP
**Tấn công Griefing** là một trong những thách thức thực tế và cấp bách nhất đối với các hệ thống dựa trên HTLC như **Lightning Network**. Như đã phân tích trong Chương 5, kẻ tấn công có thể khóa thanh khoản của các bên trung thực mà không phải chịu rủi ro hoặc chi phí đáng kể. Các nhà nghiên cứu đã đề xuất các giải pháp để chống lại cuộc tấn công này. Một trong những giải pháp đáng chú ý là **HTLC-GP (Hashed Timelock Contract with Griefing-Penalty)**.
Ý tưởng cốt lõi của **HTLC-GP** là yêu cầu các bên tham gia (người nhận hoặc các trung gian) phải đặt cọc một khoản tiền phạt. Nếu họ không hoàn thành giao dịch đúng hạn (tức là không cung cấp **preimage**), họ sẽ mất khoản tiền phạt này, và khoản tiền đó sẽ được dùng để bồi thường cho các nạn nhân có thanh khoản bị khóa.
## HTLC-GPζ
Tuy nhiên, các phân tích sâu hơn đã chỉ ra rằng **HTLC-GP** vẫn có thể bị qua mặt bởi các **"tác nhân hợp lý" (rational actors)**. Một kẻ tấn công hợp lý sẽ không hành động một cách mù quáng để bị phạt. Thay vào đó, họ sẽ thực hiện cuộc tấn công Griefing như bình thường, nhưng sẽ giải quyết giao dịch (tiết lộ preimage) ngay trước khi timelock của họ hết hạn. Bằng cách này, họ vẫn thành công trong việc khóa thanh khoản của các bên khác trong phần lớn thời gian, nhưng lại tránh được việc phải trả tiền phạt. Để giải quyết điểm yếu này, một cải tiến đã được đề xuất là **HTLC-GPζ**, bổ sung một **"khoản bồi thường tối thiểu được đảm bảo" (guaranteed minimum compensation, ζ)**. Cơ chế này nhằm đảm bảo rằng nạn nhân luôn nhận được một khoản bồi thường nhỏ, ngay cả khi kẻ tấn công hành động một cách hợp lý, từ đó làm tăng chi phí cho việc thực hiện tấn công.

---

# HTLC - Griefing Linear Penalty

Phương pháp này là một biến thể của **HTLC-GP (Hashed Timelock Contract with Griefing Penalty)**.  
Trong HTLC-GP truyền thống, phía người nhận (Bob) phải gửi một khoản **đặt cọc (deposit)** để ngăn chặn việc tham gia không nghiêm túc và gây tốn phí cho người gửi (Alice). Tuy nhiên, cơ chế này đôi khi tạo ra chi phí tấn công không cân đối.  

Với **Linear Griefing Penalty**, chúng tôi giới thiệu một cơ chế **phạt tuyến tính theo thời gian**:  

- Nếu Bob tham gia và claim token ngay lập tức (trước "penalty window"), Bob sẽ nhận lại gần như toàn bộ khoản đặt cọc.  
- Nếu Bob chậm trễ trong việc claim (tiến dần đến `unlockTime`), một phần tiền đặt cọc sẽ bị cắt giảm theo **tỷ lệ tuyến tính**, chuyển cho Alice như một hình thức **bồi thường**.  
- Nếu Bob hoàn toàn không claim đến khi `unlockTime` hết hạn, Alice có thể **refund** để lấy lại token và toàn bộ khoản đặt cọc của Bob.  

Cơ chế này làm tăng chi phí cho các hành vi tấn công kiểu "griefing" (kéo dài thời gian để làm Alice bị khoá vốn), nhưng vẫn công bằng vì Bob chỉ bị mất nhiều tiền cọc nếu hành xử không hợp lý.

## Cơ chế hoạt động

1. **Alice tạo lock**  
   - Alice lock một lượng token ERC20 vào contract.  
   - Định nghĩa các tham số:  
     - `hashlock`: khóa băm để mở khóa bằng preimage.  
     - `timelock`: thời điểm hết hạn.  
     - `timeBased`: khoảng thời gian áp dụng penalty.  
     - `penaltyInterval`: khoảng bước tính penalty.  
     - `depositRequired`: số ETH Bob phải đặt cọc.  
     - `depositWindow`: khoảng thời gian tối đa Bob phải xác nhận đặt cọc.  

2. **Bob xác nhận tham gia**  
   - Bob phải gửi đúng `depositRequired` ETH trong `depositWindow`.  
   - Nếu không, Alice có thể refund token khi cửa sổ đóng.  

3. **Bob claim token**  
   - Nếu Bob cung cấp đúng preimage trước `unlockTime`, token được gửi cho Bob.  
   - Bob nhận lại **phần deposit còn lại sau khi trừ penalty tuyến tính**.  
   - Alice nhận phần penalty.  

4. **Alice refund**  
   - Nếu Bob không xác nhận deposit trong `depositWindow`, Alice có thể lấy lại token ngay.  
   - Nếu Bob có deposit nhưng không claim trước `unlockTime`, Alice có thể refund token và toàn bộ deposit.  


## Công thức penalty

Penalty được tính theo thời gian Bob trì hoãn trong cửa sổ penalty: 
```shell
penalty = depositRequired * elapsed / timeBased
```
Trong đó:
- `elapsed` = thời gian Bob claim sau khi bước vào penalty window.  
- Nếu `elapsed >= timeBased`, Bob mất toàn bộ deposit.  
- Nếu claim trước khi penalty window bắt đầu, penalty = 0.
## Ưu điểm
- **Chống griefing hợp lý**: Bob không thể "kéo dài thời gian" miễn phí.  
- **Công bằng**: Bob vẫn có thể nhận lại phần lớn deposit nếu claim sớm.  
- **Tăng an toàn vốn cho Alice**: Alice luôn nhận được bồi thường nếu Bob chậm trễ. 


## Foundry Documentation

https://book.getfoundry.sh/

## Foundry Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
