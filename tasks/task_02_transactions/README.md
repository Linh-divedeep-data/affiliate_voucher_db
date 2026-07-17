# 📝 Write Multi-Step Transactions with COMMIT, ROLLBACK, and SAVEPOINT

## Kiến thức đạt được

> Đây là những gì cần **ghi nhớ và mang theo áp dụng cho các dự án sau** — không phải bản tóm tắt việc đã làm trong task này.

| Nội dung chính | Ghi nhớ & áp dụng cho dự án sau |
|---|---|
| **SAVEPOINT khoanh vùng lỗi cục bộ** | Khi một luồng nghiệp vụ có **1 bước chính bắt buộc thành công** và **1 hoặc nhiều bước phụ được phép thất bại độc lập**, đừng để lỗi của bước phụ hủy luôn bước chính — dùng `SAVEPOINT` để khoanh vùng đúng phạm vi có thể rollback. |
| **"Core action + side effect optional"** | Bất kỳ luồng nào có dạng đó — đăng ký user + gửi email chào mừng, tạo đơn hàng + áp mã giảm giá, ghi log + gọi webhook bên thứ ba — đều là ứng viên cho pattern `SAVEPOINT`, vì side effect thất bại không nên làm hỏng core action. |
| **RETURNING chaining tái sử dụng** | Output bước trước làm input bước sau, không cần `SELECT` phụ — áp dụng được cho mọi chuỗi ghi có phụ thuộc dữ liệu, không riêng gì dự án này. |
| **Câu hỏi quyết định có cần SAVEPOINT** | Tự hỏi "nếu bước X lỗi, các bước còn lại của luồng có nên tiếp tục không?" — nếu có → đặt `SAVEPOINT` trước bước X; nếu không (lỗi X phải hủy tất cả) → không cần savepoint, để lỗi tự propagate lên `ROLLBACK` toàn bộ. |
| **Luôn ROLLBACK TO SAVEPOINT sau khi bắt lỗi** | Ngay trong cùng khối bắt lỗi (try/catch) — quên bước này khiến cả transaction rơi vào trạng thái *aborted*, mọi câu lệnh sau đó bị từ chối dù chưa hề lỗi. |
| **Đặt câu hỏi savepoint ngay từ thiết kế** | Ngay khi thiết kế bất kỳ luồng ghi dữ liệu nào có bước phụ "có thể chấp nhận thất bại" — không phải sau khi gặp bug hủy nhầm luồng chính. |

---

Tài liệu này hướng dẫn chi tiết về cách thiết lập giao dịch đa bước (multi-step transactions) trong PostgreSQL, sử dụng `BEGIN`, `COMMIT`, `ROLLBACK`, xâu chuỗi ID qua `RETURNING` và phục hồi từng phần bằng `SAVEPOINT`.

---

## 🎯 Nội dung học tập (What You Will Learn)

| # | Khái niệm (Concept) | Tóm tắt một dòng (One-line summary) |
| :--- | :--- | :--- |
| **1** | **BEGIN / COMMIT** | Gom nhóm nhiều câu lệnh SQL thành một thao tác nguyên tử (atomic operation). |
| **2** | **RETURNING chaining** | Sử dụng kết quả của `INSERT` trước làm đầu vào cho lệnh `INSERT` sau — không cần chạy thêm truy vấn `SELECT`. |
| **3** | **Mid-transaction ROLLBACK** | Một bước đơn lẻ trong khối giao dịch bị lỗi sẽ hủy toàn bộ các bước trước đó trong khối. |
| **4** | **SAVEPOINT** | Điểm khôi phục cục bộ — chỉ hủy bước bị lỗi bên trong khối giao dịch và tiếp tục thực hiện các bước khác. |

---

## 🗂️ Các bảng cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Thao tác thực thi (Operation) | Vai trò nghiệp vụ (Why) |
| :--- | :--- | :--- |
| **`customer`** | `INSERT` thông tin khách hàng mới | Điểm xuất phát của luồng đăng ký người dùng mới. |
| **`customer_voucher`** | `INSERT` liên kết gán mã voucher | Liên kết khóa ngoại giữa khách hàng và voucher nhận được. |
| **`budget_transaction`** | `INSERT` chi tiêu ngân sách | Ghi nhận chi phí phát hành voucher và giảm trừ ngân sách khuyến mãi. |

### Bảng hỗ trợ (Lookup Table):
* **`status_master`**: Lưu trữ toàn bộ các ID trạng thái (`status_id`) tương ứng với mã code (`status_code`). Tất cả các truy vấn lọc hoặc lấy ID trạng thái phải thông qua việc tham chiếu tới bảng này thay vì ghi cứng ID.

---

## 🔑 Các tham số và Placeholder cần thiết

Trước khi chạy các kịch bản giao dịch, bạn cần thực hiện truy vấn khám phá dữ liệu (Simple Data Discovery) để thu thập các giá trị thực tế của cơ sở dữ liệu:

### Bước 0-A: Tìm Status ID
```sql
SELECT status_id, entity_type, status_code
FROM status_master
WHERE status_code IN ('ACTIVE', 'SAVED');
```
* Lưu lại `status_id` của Customer (`ACTIVE`) và Customer Voucher (`SAVED`).

### Bước 0-B: Tìm Program và Voucher khả dụng
```sql
SELECT voucher_id, program_id
FROM voucher
LIMIT 5;
```
* Chọn bất kỳ dòng nào và lưu lại `program_id` cùng `voucher_id`.

> [!NOTE]
> **Giá trị tham chiếu mặc định sau khi seed:**
> * `:program_id` = `1`
> * `:voucher_id` = `1`
> * `:cust_active_status_id` = `1` (Trạng thái `ACTIVE` của CUSTOMER)
> * `:cv_saved_status_id` = `6` (Trạng thái `SAVED` của CUSTOMER_VOUCHER)

---

## 🔬 Chi tiết 3 Kịch bản Thực hành (Scenarios)

### Kịch bản A — Happy Path với RETURNING Chaining
* **Mục tiêu:** Thực hiện chuỗi ghi dữ liệu liên kết nguyên tử hoàn toàn thành công.
* **Hoạt động:**
  1. Bắt đầu giao dịch bằng `BEGIN;`.
  2. Tạo khách hàng mới và lấy ID trả về bằng `RETURNING customer_id`.
  3. Dùng `customer_id` thu được để lập tức gán voucher trong bảng `customer_voucher`.
  4. Tạo giao dịch trừ ngân sách trong bảng `budget_transaction`.
  5. Xác nhận giao dịch thành công bằng `COMMIT;`.
* **Kiểm tra trạng thái:** Chạy các lệnh kiểm tra sau giao dịch để xác nhận cả 3 dòng dữ liệu mới đều tồn tại đồng bộ.

### Kịch bản B — Hủy giao dịch giữa chừng (Mid-transaction Rollback)
* **Mục tiêu:** Kiểm chứng tính nguyên tử (Atomicity) — "Tất cả hoặc không có gì".
* **Ràng buộc kiểm tra bổ sung:**
  ```sql
  ALTER TABLE budget_transaction ADD CONSTRAINT chk_bt_amount_positive CHECK (amount >= 0);
  ```
* **Hoạt động:**
  1. Bắt đầu giao dịch.
  2. Tạo khách hàng mới và gán voucher (thực thi thành công).
  3. Ghi nhận giao dịch ngân sách với số tiền âm (ví dụ: `-9,999,999`) ➡️ Vi phạm check constraint của database và gây lỗi crash.
  4. Thực hiện `ROLLBACK;` để hoàn trả toàn bộ thay đổi.
* **Kiểm tra trạng thái:** So sánh số dòng dữ liệu trước và sau rollback để đảm bảo không có bất kỳ dòng rác nào từ giao dịch bị ghi nhận vào hệ thống.

### Kịch bản C — Phục hồi từng phần bằng SAVEPOINT
* **Mục tiêu:** Xử lý lỗi cục bộ mà không cần hủy toàn bộ giao dịch.
* **Hoạt động:**
  1. Bắt đầu giao dịch và tạo khách hàng thành công.
  2. Đánh dấu điểm lưu trữ: `SAVEPOINT after_customer;`.
  3. Thử gán một `voucher_id` không tồn tại (`99999999`) ➡️ Vi phạm khóa ngoại (`fk_cv_voucher`).
  4. Thu hồi lỗi bằng lệnh `ROLLBACK TO SAVEPOINT after_customer;` ➡️ Chỉ bước lỗi bị hủy, dòng khách hàng vẫn được giữ trong transaction.
  5. Thử lại với `voucher_id` chính xác.
  6. Xác nhận giao dịch `COMMIT;`.
* **Kiểm tra trạng thái:** Khách hàng mới được tạo thành công cùng với voucher hợp lệ. Bản ghi voucher sai sót được dọn dẹp sạch sẽ khỏi database.

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

### Câu hỏi 1 — RETURNING chaining:
* **Câu hỏi:** Trong Kịch bản A, bạn sử dụng `RETURNING` để chuyển trực tiếp `customer_id` sang câu lệnh `INSERT` kế tiếp mà không cần dùng câu lệnh `SELECT` riêng lẻ. Điều gì sẽ xảy ra nếu có 2 người dùng chạy Kịch bản A đồng thời mà không có `RETURNING` (cả hai đều `SELECT` ID bằng số điện thoại ngay sau khi `INSERT`)?
* **Trả lời:**
  * **Tranh chấp dữ liệu (Race Condition):** Nếu số điện thoại không được định nghĩa là duy nhất hoặc có độ trễ giữa hai phiên, việc `SELECT` sau khi `INSERT` có thể trả về sai ID hoặc bị hoán đổi ID giữa hai người dùng, dẫn đến gán nhầm voucher cho tài khoản khác.
  * **Suy giảm hiệu năng:** Tách biệt `INSERT` và `SELECT` tăng gấp đôi số lượng kết nối mạng (round-trip) tới database, tạo gánh nặng lớn lên tài nguyên hệ thống khi có lượng truy cập cao.
  * **Độ tin cậy thấp:** `RETURNING` thực thi hoàn toàn trong một câu lệnh đơn lẻ ở mức engine, đảm bảo dữ liệu trả về thuộc chính xác phiên (session) đang xử lý.

### Câu hỏi 2 — SAVEPOINT:
* **Câu hỏi:** Trong Kịch bản C, `SAVEPOINT` giúp bạn khôi phục từ một dòng bị lỗi mà không cần hủy toàn bộ giao dịch. Hãy nêu một tình huống thực tế trong hệ thống Marketing/Voucher này mà `SAVEPOINT` sẽ cực kỳ có giá trị trên môi trường Production.
* **Trả lời:**
  * **Tình huống thực tế: "Gói quà chào mừng khi đăng ký tài khoản (Welcome Bundle Claim Flow)".**
  * **Nghiệp vụ:** Khi người dùng đăng ký mới, hệ thống tự động gán một gói voucher bao gồm: 1 voucher vận chuyển, 1 voucher giảm giá, và 1 voucher đối tác liên kết.
  * **Vấn đề:** Nếu voucher đối tác đột ngột hết lượt phát hành và vi phạm constraint về số lượng tối đa, transaction sẽ lỗi.
  * **Giải pháp với SAVEPOINT:**
    Thiết lập một `SAVEPOINT` trước khi gán từng voucher. Khi gán voucher đối tác bị lỗi, ứng dụng có thể rollback về savepoint trước đó, bỏ qua voucher lỗi và tiếp tục gán thành công 2 voucher còn lại. Giao dịch vẫn hoàn thành, khách hàng đăng ký thành công và nhận được các voucher khả dụng thay vì toàn bộ luồng đăng ký tài khoản bị lỗi chỉ vì một voucher khuyến mãi phụ hết hàng.
