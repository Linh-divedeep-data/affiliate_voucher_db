# 📝 Task: Practice Targeted CRUD & Observe the Auto-Commit Trap

## Kiến thức đạt được

> Đây là những gì cần **ghi nhớ và mang theo áp dụng cho các dự án sau** — không phải bản tóm tắt việc đã làm trong task này.

| Nội dung chính | Ghi nhớ & áp dụng cho dự án sau |
|---|---|
| **Autocommit là bẫy mặc định** | Mọi kết nối DB (psql, driver, ORM) tự **autocommit** trừ khi chủ động mở transaction. Hễ thấy ≥ 2 câu `INSERT`/`UPDATE`/`DELETE` cùng phục vụ **một hành động nghiệp vụ duy nhất**, phải bọc chúng trong `BEGIN...COMMIT/ROLLBACK` ngay từ khi viết code đầu tiên — đừng đợi xảy ra sự cố dữ liệu mồ côi rồi mới vá. |
| **Ghi nối tiếp nhiều bảng phụ thuộc** | Bất kỳ đoạn code nào có dạng "ghi bảng A, rồi dùng kết quả đó ghi tiếp bảng B" (đăng ký user → tạo hồ sơ, tạo đơn hàng → trừ tồn kho, v.v.) đều tiềm ẩn đúng rủi ro autocommit-trap này, bất kể ngôn ngữ hay ORM nào. |
| **RETURNING thay vì SELECT lại** | Dùng `RETURNING` (Postgres) hoặc cơ chế tương đương của DB khác để lấy ID/giá trị sinh tự động ngay trong câu ghi, tránh phải `SELECT` lại — giảm 1 round-trip và loại bỏ khoảng hở race condition. |
| **RESTRICT vs CASCADE cho FK** | Mặc định chọn `RESTRICT` cho quan hệ cha-con quan trọng về nghiệp vụ; chỉ dùng `CASCADE` khi đã đánh giá rõ "blast radius" (xóa cha kéo theo tối đa bao nhiêu dòng con) và chấp nhận được rủi ro đó. |
| **Test "lỗi bước N thì sao?"** | Trước khi merge bất kỳ script/migration/job nào có nhiều bước ghi, tự hỏi "nếu bước thứ N lỗi, các bước 1..N-1 đã chạy có gây hại gì không?" — nếu có, bắt buộc phải có transaction bao ngoài. |
| **Áp dụng ngay từ dòng code đầu tiên** | Ngay từ dòng code đầu tiên của bất kỳ luồng ghi dữ liệu nhiều bước nào ở dự án tiếp theo — coi `BEGIN...COMMIT` là mặc định cần cân nhắc, không phải thứ "thêm vào sau nếu cần". |

---

Tài liệu này ghi lại chi tiết các bước thực hiện, khái niệm cốt lõi và các bài học kinh nghiệm rút ra từ việc thực hành các thao tác CRUD có mục tiêu, xử lý lỗi Foreign Key RESTRICT và hiểu rõ cơ chế Auto-commit/Transaction trong PostgreSQL.

---

## 🎯 Nội dung học tập & Bài học rút ra (What You Will Learn)

| # | Khái niệm (Concept) | Tóm tắt một dòng (One-line summary) |
| :--- | :--- | :--- |
| **1** | **Mệnh đề RETURNING** | Trả về dòng được cập nhật ngay trong cùng một câu lệnh — không cần chạy thêm `SELECT` phụ. |
| **2** | **Foreign Key RESTRICT** | Database từ chối xóa dòng cha khi vẫn còn dòng con đang tham chiếu (FK) đến dòng cha đó. |
| **3** | **Bẫy tự động Commit (Auto-commit trap)** | Nếu không có `BEGIN`, mọi câu lệnh đơn lẻ sẽ tự động commit ngay khi chạy xong — khi gặp lỗi ở giữa, dữ liệu trước đó vẫn bị lưu vĩnh viễn gây ra dữ liệu mồ côi (orphaned data). |
| **4** | **Giải pháp Transaction** | Gom nhóm các câu lệnh trong khối `BEGIN ... COMMIT/ROLLBACK` để database xử lý như một đơn vị nguyên tử (ACID). |

---

## 🗂️ Các bảng Cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Thao tác thực thi (Operation) | Vai trò nghiệp vụ (Why) |
| :--- | :--- | :--- |
| **`promotion_program`** | `UPDATE status_id` | Thay đổi trạng thái chương trình khuyến mãi (sử dụng trong demo khóa dữ liệu). |
| **`customer_voucher`** | `UPDATE status_id` | Quản lý trạng thái voucher của khách hàng (sử dụng trong kịch bản hủy voucher). |
| **`budget_transaction`** | `INSERT` với `entry_type='spend'` | Ghi nhận chi tiêu ngân sách (sử dụng trong kiểm thử ACID và ràng buộc kiểm tra). |
| **`status_master`** | Subquery / Join | Bảng lookup chứa danh mục trạng thái hệ thống. |

---

## ✅ STEP 0 — Prerequisites (Run First, Record the Results)

Trước khi thực hiện các Action Items, bạn cần tiến hành các câu lệnh khám phá dữ liệu (Simple Data Discovery) để thu thập các giá trị thực tế của cơ sở dữ liệu:

### 🔍 Sanity Check — Khám phá dữ liệu trước khi lọc

#### Check 1 — Tìm các trạng thái hiện có trong status_master:
```sql
SELECT status_id, entity_type, status_code, status_name, is_final
FROM status_master
WHERE is_deleted = FALSE
ORDER BY entity_type, status_id;
```
*Ghi chú lại status_id cho: `promotion_program` và `customer_voucher`.*

#### Check 2 — Đếm số lượng chương trình khuyến mãi theo từng trạng thái:
```sql
SELECT sm.status_code, COUNT(*) AS program_count
FROM promotion_program pp
JOIN status_master sm ON sm.status_id = pp.status_id
WHERE pp.is_deleted = FALSE
GROUP BY sm.status_code
ORDER BY sm.status_code;
```
*Chọn một status_code có dữ liệu và chưa ở trạng thái kết thúc (ví dụ: 'ACTIVE').*

#### Check 3 — Tìm xem có những trạng thái nào của customer_voucher trong DB:
```sql
SELECT sm.status_code, COUNT(*) AS cv_count
FROM customer_voucher cv
JOIN status_master sm ON sm.status_id = cv.status_id
WHERE cv.is_deleted = FALSE
GROUP BY sm.status_code
ORDER BY sm.status_code;
```
*(Đối với Action 2, bạn cần một customer_voucher có trạng thái là 'SAVED').*

---

### 🔑 Các câu lệnh lấy giá trị tham số (Placeholders)

#### Step 0-A · Tìm chương trình khuyến mãi (promotion_program) đang hoạt động:
```sql
SELECT pp.program_id, pp.program_name, sm.status_code, pp.budget_limit
FROM promotion_program pp
JOIN status_master sm ON sm.status_id = pp.status_id
WHERE sm.status_code = 'ACTIVE'
  AND pp.is_deleted = FALSE
ORDER BY pp.program_id
LIMIT 3;
```
*Lưu giá trị này thành: `:program_id` (Ví dụ: `1`).*

#### Step 0-B · Tìm một customer_voucher có trạng thái là 'SAVED':
```sql
SELECT cv.customer_voucher_id AS cv_id, sm.status_code, v.program_id
FROM customer_voucher cv
JOIN voucher v          ON v.voucher_id  = cv.voucher_id
JOIN status_master sm   ON sm.status_id  = cv.status_id
WHERE v.program_id      = :program_id
  AND sm.status_code    = 'SAVED'
  AND cv.is_deleted     = FALSE
ORDER BY cv.customer_voucher_id
LIMIT 5;
```
*Lưu giá trị này thành: `:cv_id` (Ví dụ: `6`).*

#### Step 0-C · Tính toán ngân sách còn lại của chương trình:
```sql
SELECT
    pp.program_id,
    pp.budget_limit,
    COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0)   AS total_spent,
    pp.budget_limit
      - COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0) AS remaining_budget
FROM promotion_program pp
LEFT JOIN budget_transaction bt ON bt.program_id = pp.program_id
WHERE pp.program_id = :program_id
GROUP BY pp.program_id, pp.budget_limit;
```
*Lưu giá trị này thành: `:remaining_budget` (Ví dụ: `50,000,000`đ).*
*Tính toán: `:balance_after_valid = remaining_budget - 500,000` (Ví dụ: `49,500,000`đ).*

#### Step 0-D · Thu thập toàn bộ ID trạng thái (status_id) cần thiết:
```sql
SELECT status_id, entity_type, status_code
FROM status_master
WHERE entity_type IN ('PROMOTION_PROGRAM', 'CUSTOMER_VOUCHER')
  AND status_code  IN ('ACTIVE', 'PAUSED', 'SAVED', 'CANCELLED')
  AND is_deleted   = FALSE
ORDER BY entity_type, status_code;
```
*Ghi lại các status_id từ kết quả truy vấn trên để điền vào các Action.*

---

### 📋 Giá trị tham chiếu trước khi tiếp tục:
* **`:program_id`** = `1` (Tết 2026)
* **`:active_status_id`** = `15` (PROMOTION_PROGRAM / ACTIVE)
* **`:paused_status_id`** = `16` (PROMOTION_PROGRAM / PAUSED)
* **`:cv_id`** = `6`
* **`:cv_saved_status_id`** = `6` (CUSTOMER_VOUCHER / SAVED)
* **`:cv_cancelled_status_id`** = `9` (CUSTOMER_VOUCHER / CANCELLED)
* **`:remaining_budget`** = `50,000,000`
* **`:balance_after_valid`** = `49,500,000`

---

## 🔬 Chi tiết Nhật ký Thực hiện các Action Items

### Action 1 — Sử dụng Mệnh đề RETURNING
* **Kịch bản:** Cập nhật trạng thái chương trình khuyến mãi từ `ACTIVE` (15) sang `PAUSED` (16).
* **Hoạt động:**
  ```sql
  UPDATE promotion_program
     SET status_id = :paused_status_id,
         updated_by = CURRENT_USER
   WHERE program_id = :program_id
     AND status_id  = :active_status_id
  RETURNING program_id, status_id, updated_at;
  ```
* **Kết quả:** Trả về trực tiếp dòng dữ liệu vừa được update (gồm `program_id`, `status_id`, và `updated_at` tự động sinh bởi trigger) ngay lập tức mà không cần câu lệnh `SELECT` phụ.

### Action 2 — Cơ chế bảo vệ của Foreign Key (RESTRICT)
* **Kịch bản:** Ngăn chặn việc xóa dữ liệu cha khi dữ liệu con đang tham chiếu.
* **Hoạt động:**
  1. Xác nhận `customer_voucher` (ID = 6) có trạng thái `SAVED`.
  2. Cập nhật `customer_voucher` sang `CANCELLED` bằng mệnh đề `RETURNING`.
  3. Cố gắng xóa `promotion_program` (ID = 1):
     ```sql
     DELETE FROM promotion_program WHERE program_id = 1;
     ```
* **Kết quả:** PostgreSQL chặn đứng hành vi xóa dòng cha và ném ra lỗi vi phạm khóa ngoại:
  ```text
  ERROR: update or delete on table "promotion_program" violates foreign key constraint "fk_voucher_program" on table "voucher"
  ```
* **Bài học:** Database hoạt động đúng chức năng bảo vệ toàn vẹn tham chiếu. Thứ tự xóa đúng phải là:
  `customer_voucher` ➡️ `voucher` ➡️ `promotion_program`.

### Action 3 — Sự nguy hiểm của Auto-Commit Trap ⚠️
* **Kịch bản:** Chạy hai câu lệnh `INSERT` liên tiếp mà không có khối `BEGIN` giao dịch:
  * **Lệnh 1:** Chèn giao dịch chi tiêu hợp lệ `500,000`đ.
  * **Lệnh 2:** Chèn giao dịch chi tiêu âm `-9,999,999`đ vi phạm check constraint `amount >= 0` (`chk_bt_amount_positive`).
* **Kết quả:** Lệnh 2 bị lỗi và bị từ chối, tuy nhiên Lệnh 1 **đã được lưu vĩnh viễn** vào database do cơ chế auto-commit.
* **Hậu quả:** Gây ra bản ghi mồ côi (giao dịch chi tiêu ảo), làm sai lệch ngân sách thực tế mà không thể tự động hoàn tác.

### Action 4 — Khắc phục bằng Khối Transaction rõ ràng
* **Kịch bản:** Gom hai câu lệnh trên vào trong một khối `BEGIN ... ROLLBACK`:
  ```sql
  BEGIN;
      -- Lệnh 1 (Valid spend)
      -- Lệnh 2 (Invalid negative spend)
  ROLLBACK;
  ```
* **Kết quả:** Mặc dù Lệnh 1 hợp lệ, lệnh `ROLLBACK` ở cuối (hoặc tự động rollback khi gặp lỗi ở Lệnh 2) đã hủy bỏ toàn bộ các thay đổi trong khối. Database trở về trạng thái sạch sẽ trước khi thực thi khối lệnh, không có bản ghi rác nào bị sót lại.

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

> [!IMPORTANT]
> **Câu hỏi:** Trong Action 3, Statement 1 committed a budget spend record while Statement 2 failed — but Statement 1 could not be undone automatically.
> Trong một hệ thống chạy thực tế, điều này gây ra hậu quả gì cho doanh nghiệp? Ai chịu trách nhiệm dọn dẹp bản ghi mồ côi này — database hay ứng dụng?

### 1. Hậu quả thực tế đối với Doanh nghiệp:
* **Sai lệch báo cáo tài chính:** Bộ phận Kế toán/Finance khi đối soát cuối ngày sẽ thấy ngân sách bị trừ mất `500.000đ` (do `remaining_budget = budget_limit - SUM(amount)` bị giảm), nhưng không hề có đơn hàng hay voucher nào tương ứng được ghi nhận.
* **Dừng chiến dịch sớm (Premature Campaign Pausing):** Hệ thống giám sát ngân sách thấy tổng chi tiêu chạm ngưỡng giới hạn (ảo) và tự động khóa chiến dịch, trong khi thực tế tiền chưa hề được chi tiêu. Doanh nghiệp mất cơ hội tiếp cận khách hàng.
* **Mất lòng tin dữ liệu:** Sự bất nhất giữa báo cáo của Marketing (số lượng Voucher dùng thực tế) và Finance (số tiền đã ghi nhận chi tiêu) gây tranh cãi và khó đưa ra quyết định.

### 2. Trách nhiệm Dọn dẹp bản ghi:
* **Không phải Database:** Database đã làm việc hoàn toàn đúng theo thiết kế. Nó nhận lệnh đơn lẻ, lưu trữ thành công và cam kết lưu vĩnh viễn (thuộc tính Durability trong ACID). Database không thể tự đoán biết được logic nghiệp vụ là hai câu lệnh đó phải đi liền với nhau.
* **Trách nhiệm thuộc về Ứng dụng (Application / Developer):**
  * **Người dọn dẹp:** Lập trình viên phải viết script thủ công để xóa bản ghi rác (như script `Cleanup` trong `crud_operations.sql`).
  * **Giải pháp phòng ngừa:** Lập trình viên bắt buộc phải thiết lập ứng dụng bọc các tác vụ đa bước trong các khối Transaction rõ ràng (`BEGIN ... COMMIT / ROLLBACK`), đảm bảo tính nguyên tử tuyệt đối cho luồng dữ liệu.
