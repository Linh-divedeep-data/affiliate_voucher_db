# 📝 Task: DID12_Enforce Data Consistency (ACID) via Database Constraints

Tài liệu này ghi lại chi tiết các bước thực hiện, phân tích kỹ thuật và bài học kinh nghiệm về việc áp dụng các ràng buộc (Constraints) ở tầng Cơ sở dữ liệu để thực thi tính Nhất quán (Consistency) trong mô hình giao dịch ACID.

---

## 🎯 Nội dung học tập & Bài học rút ra (Key Learnings)

| # | Khái niệm (Concept) | Tóm tắt một dòng (One-line summary) | Bài học thực tế (Key Takeaways) |
| :--- | :--- | :--- | :--- |
| **1** | **Ràng buộc UNIQUE** | Ngăn chặn việc ghi trùng lặp các trường định danh duy nhất (ví dụ: số điện thoại, email) trên bảng dữ liệu. | Ngăn chặn việc tạo tài khoản rác hoặc đăng ký trùng lặp do lỗi từ phía Client hoặc Backend gửi API liên tục. |
| **2** | **Ràng buộc CHECK đơn** | Đảm bảo tính hợp lệ về mặt giá trị của một cột (ví dụ: số tiền giao dịch không được phép nhỏ hơn hoặc bằng 0). | Đơn giản hóa việc quản lý dữ liệu, ngăn ngừa lỗi tràn hoặc nhập liệu sai số học trực tiếp ở mức vật lý. |
| **3** | **Ràng buộc CHECK đa cột** | So sánh giá trị giữa hai hoặc nhiều cột với nhau (ví dụ: `total_issued` không vượt quá `issuance_limit`). | Đưa trực tiếp các quy tắc nghiệp vụ (Business Rules) vào cấu trúc bảng, tạo ra một rào chắn bất khả xâm phạm. |
| **4** | **Database Triggers** | Tự động thực thi các hành động bảo trì dữ liệu khi có thay đổi (ví dụ: tự cập nhật `updated_at = NOW()`). | Giảm thiểu sai sót của lập trình viên, đảm bảo tất cả các cập nhật hệ thống (qua code hoặc thủ công) luôn được ghi nhận timestamp đầy đủ. |

---

## 🗂️ Các bảng Cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Thao tác thực thi (Operation) | Ràng buộc / Trigger kiểm tra (Constraint / Trigger) |
| :--- | :--- | :--- |
| **`customer`** | `INSERT` bản ghi trùng lặp SĐT | `customer_phone_number_key` (UNIQUE) |
| **`voucher`** | `UPDATE` số lượng vượt quá hạn mức | `chk_total_issued` (CHECK: `total_issued <= issuance_limit`) |
| **`promotion_program`** | `UPDATE` chương trình để kiểm tra trigger | `trg_promotion_program_updated_at` (Trigger) |

---

## 🔬 Chi tiết 3 Kịch bản Thực hành (Scenarios)

### Kịch bản A — The UNIQUE Guard (Ngăn chặn bản ghi trùng lặp)
* **Ý nghĩa:** Chống trùng lặp dữ liệu khách hàng khi backend gửi nhiều request đăng ký đồng thời.
* **Hoạt động:**
  1. Thêm khách hàng A thành công với SĐT `0999888777`.
  2. Thử thêm khách hàng B cũng với SĐT `0999888777`.
* **Kết quả:** PostgreSQL báo lỗi ngay lập tức:
  ```
  ERROR: duplicate key value violates unique constraint "customer_phone_number_key"
  ```
  Lượt insert thứ hai bị chặn và rollback hoàn toàn.

### Kịch bản B — The Logic Guard (Ràng buộc logic đa cột)
* **Ý nghĩa:** Bảo vệ ngân sách voucher khỏi việc phát hành quá hạn mức do lỗi ứng dụng.
* **Hoạt động:**
  * Cập nhật `total_issued` lớn hơn `issuance_limit` trên bảng `voucher` (`SET total_issued = :issuance_limit + 10`).
* **Kết quả:** Lệnh update thất bại và trả về lỗi:
  ```
  ERROR: new row for relation "voucher" violates check constraint "chk_total_issued"
  ```
  Database bảo vệ thành công quy tắc giới hạn số lượng phát hành.

### Kịch bản C — The Automation Guard (Database Triggers)
* **Ý nghĩa:** Tự động hóa việc ghi nhận mốc thời gian cập nhật dữ liệu.
* **Hoạt động:**
  1. Lấy mốc thời gian `updated_at` hiện tại của chương trình khuyến mãi.
  2. Cập nhật `program_name` nhưng **không** truyền giá trị cập nhật cho cột `updated_at`.
  3. Kiểm tra lại mốc thời gian của dòng vừa sửa.
* **Kết quả:** Giá trị `updated_at` tự động tiến tới mốc thời gian thực hiện cập nhật nhờ trigger `trg_promotion_program_updated_at` chạy ngầm.

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

### Câu hỏi 1 — Phòng thủ đa lớp (Defense in Depth):
> Nếu ứng dụng backend (ví dụ: NodeJS hoặc Python) đã kiểm tra logic `if (total_issued >= issuance_limit) return error;` trước khi chạy lệnh UPDATE, tại sao chúng ta vẫn cần ràng buộc `chk_total_issued` trong cơ sở dữ liệu?

* **Trả lời:**
  * **Tranh chấp đồng thời (Concurrency):** Khi hàng ngàn người dùng bấm nút claim cùng 1 mili-giây, nhiều thread của ứng dụng cùng đọc `total_issued = 999` (với limit = 1000). Cả hai đều thấy hợp lệ và đồng thời gửi lệnh update lên, khiến số lượng thực tế vọt lên `1001`. Cơ sở dữ liệu với isolation level và lock cơ chế sẽ chặn được race condition này nhờ ràng buộc CHECK ở mức vật lý.
  * **Đa kênh truy cập dữ liệu:** Trong thực tế, dữ liệu có thể được thay đổi từ các script bảo trì thủ công của DBA, các luồng đồng bộ dữ liệu (ETL/data pipeline), hoặc các công cụ GUI (DBeaver, pgAdmin) mà không thông qua code của ứng dụng. Ràng buộc ở database là tấm khiên cuối cùng đảm bảo dữ liệu luôn sạch.
  * **Phòng ngừa lỗi mã nguồn (Code Bugs):** Ứng dụng thay đổi phiên bản liên tục, một lập trình viên khác có thể viết nhầm hoặc quên kiểm tra logic này ở một API mới. Khai báo ràng buộc ở DB là vĩnh viễn và không phụ thuộc vào ứng dụng.

### Câu hỏi 2 — Rủi ro của việc thiếu tự động hóa (Automation Risks):
> Trong Kịch bản C, DB trigger tự động cập nhật `updated_at`. Điều gì sẽ xảy ra với việc kiểm toán dữ liệu (data auditing) nếu chúng ta không có trigger này, và một Lập trình viên Junior chạy lệnh `UPDATE` thủ công trong DBeaver để sửa lỗi chính tả?

* **Trả lời:**
  * **Sai lệch thông tin kiểm toán:** Junior Developer chạy UPDATE sửa chữa lỗi chính tả nhưng không truyền cột `updated_at` trong câu lệnh. Dữ liệu đã bị thay đổi nhưng timestamp `updated_at` vẫn trỏ về mốc cũ của ứng dụng.
  * **Không thể truy vết sự cố:** Khi hệ thống xảy ra sự cố và cần kiểm toán xem ai đã làm thay đổi dữ liệu vào lúc nào, đội ngũ vận hành sẽ bị đánh lạc hướng bởi cột `updated_at` hiển thị thông tin sai lệch, gây khó khăn cho việc khắc phục hậu quả.
  * **Sự nhất quán:** Trigger tự động hóa ở tầng database đảm bảo tính đồng bộ tuyệt đối. Bất kể hành vi cập nhật đến từ đâu (ứng dụng, API, hay câu lệnh SQL gõ tay của dev), mốc thời gian sửa đổi và tài khoản sửa đổi luôn được ghi nhận chính xác 100%.
