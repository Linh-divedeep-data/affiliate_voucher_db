# 📝 Task: DDID-12 · Enforce Data Consistency (ACID) via Database Constraints

## 🎯 Nội dung học tập & Bài học rút ra (Key Learnings)

Trong mô hình ACID, chữ **C** viết tắt của **Consistency (Nhất quán)**. Một giao dịch (transaction) phải chuyển cơ sở dữ liệu từ một trạng thái hợp lệ (valid state) sang một trạng thái hợp lệ khác. Nhưng làm thế nào database biết trạng thái nào là "hợp lệ"? Câu trả lời chính là: **Ràng buộc (Constraints)**.

| # | Khái niệm (Concept) | Tóm tắt một dòng (One-line summary) |
| --- | --- | --- |
| 1 | **Ràng buộc UNIQUE** | Ngăn chặn các bản ghi trùng lặp (ví dụ: một số điện thoại = một tài khoản) |
| 2 | **Ràng buộc CHECK đơn** | Đảm bảo tính hợp lệ về mặt giá trị số học/văn bản (ví dụ: ngân sách không được phép âm) |
| 3 | **Ràng buộc CHECK đa cột** | So sánh giá trị giữa hai cột (ví dụ: `total_issued` không vượt quá `issuance_limit`) |
| 4 | **Database Triggers** | Tự động hóa việc bảo trì dữ liệu (ví dụ: tự động cập nhật `updated_at` mỗi khi có thay đổi) |

---

## 🗂️ Các bảng cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Thao tác thực thi (Operation) | Ràng buộc / Trigger kiểm tra (Target Constraint / Trigger) |
| --- | --- | --- |
| `customer` | `INSERT` bản ghi trùng lặp SĐT | `customer_phone_number_key` |
| `voucher` | `UPDATE` số lượng vượt quá hạn mức | `chk_total_issued` |
| `promotion_program` | `UPDATE` để kiểm tra trigger tự động | `trg_promotion_program_updated_at` |

---

## 🔑 Ngữ cảnh (Context)

Nhiều nhà phát triển ứng dụng (backend developers) lầm tưởng rằng việc kiểm tra tính toàn vẹn của dữ liệu *chỉ cần* được thực hiện ở tầng ứng dụng (NodeJS, Java, Python). Đây là một phản khuôn mẫu (anti-pattern) rất nguy hiểm. Các máy chủ ứng dụng có thể bị sập, gặp lỗi logic hoặc đối mặt với tranh chấp luồng (race conditions). **Ràng buộc cơ sở dữ liệu (Database constraints) là chốt chặn phòng thủ cuối cùng và tuyệt đối.** Nếu ứng dụng gặp sự cố và hoạt động sai logic, database sẽ từ chối lưu các dữ liệu lỗi ở mức vật lý.

---

## ✅ BƯỚC 0 — Chuẩn bị (Simple Data Discovery)

**Bước 0-A: Lấy thông tin chương trình khuyến mãi và voucher**

```sql
SELECT v.voucher_id, v.program_id, v.issuance_limit, v.total_issued
FROM linh_lab.voucher v
LIMIT 5;
```

> Chọn một dòng bất kỳ. Lưu lại giá trị `program_id` và `voucher_id`. Ghi nhận giá trị `issuance_limit` hiện tại.

**Bước 0-B: Kiểm tra các ràng buộc hiện tại và cập nhật Trigger**

Lược đồ cơ sở dữ liệu (`linh_lab`) đã có sẵn các ràng buộc UNIQUE và CHECK cho bảng `customer` và `voucher`. Chúng ta hãy truy vấn tìm tên chính xác của các ràng buộc đó, đồng thời kích hoạt trigger tự động cho bảng `promotion_program`.

```sql
-- 1. Kiểm tra ràng buộc UNIQUE của bảng Customer
SELECT conname AS constraint_name
FROM pg_constraint
WHERE conrelid = 'linh_lab.customer'::regclass AND contype = 'u';

-- 2. Kiểm tra ràng buộc CHECK của bảng Voucher
SELECT conname AS constraint_name
FROM pg_constraint
WHERE conrelid = 'linh_lab.voucher'::regclass AND contype = 'c';

-- 3. Tạo Trigger tự động cập nhật thời gian cho Promotion Program (Chạy lệnh này để cập nhật!)
CREATE OR REPLACE FUNCTION linh_lab.fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_promotion_program_updated_at
BEFORE UPDATE ON linh_lab.promotion_program
FOR EACH ROW
EXECUTE FUNCTION linh_lab.fn_set_updated_at();
```

---

> 📋 **Các giá trị ghi nhận trước khi tiếp tục:**
> 
> ```
> :program_id              = ___
> :voucher_id              = ___
> :issuance_limit          = ___
> ```

---

## 🔬 Chi tiết các Kịch bản Thực hành (Action Items)

---

### Kịch bản A — The UNIQUE Guard (Ngăn chặn bản ghi trùng lặp)

**Khái niệm:** Đội ngũ Marketing vừa chạy một chiến dịch gửi SMS. Do lỗi hệ thống backend, nó vô tình cố gắng đăng ký cùng một khách hàng hai lần trong cùng một mili-giây. Hãy xem cách database tự bảo vệ chính nó.

* **Hoạt động:**
  * **Bước 1 — Thêm khách hàng thứ nhất (Hợp lệ):**
    ```sql
    INSERT INTO linh_lab.customer (first_name, last_name, phone_number, email, status_id, created_by)
    VALUES (
        'Duplicate',
        'Tester',
        '0999888777',           -- Ghi nhớ số điện thoại này
        'dup.test@demo.com',
        (SELECT status_id FROM linh_lab.status_master WHERE status_code = 'ACTIVE' AND entity_type = 'CUSTOMER'),
        'TEST_USER'
    );
    ```
    *Giải thích:* Câu lệnh chèn một bản ghi khách hàng mới với số điện thoại `0999888777` vào bảng `customer`. Bản ghi này hợp lệ vì chưa có số điện thoại này trong hệ thống.
    *Kết quả kỳ vọng:* `INSERT 0 1` (Thao tác thành công).

  * **Bước 2 — Cố gắng thêm lại khách hàng với cùng số điện thoại:**
    ```sql
    INSERT INTO linh_lab.customer (first_name, last_name, phone_number, email, status_id, created_by)
    VALUES (
        'Hacker',
        'Man',
        '0999888777',           -- Trùng số điện thoại trên
        'hacker.man@demo.com',
        (SELECT status_id FROM linh_lab.status_master WHERE status_code = 'ACTIVE' AND entity_type = 'CUSTOMER'),
        'TEST_USER'
    );
    ```
    *Giải thích:* Lệnh này cố gắng thêm một khách hàng khác nhưng sử dụng lại đúng số điện thoại `0999888777` đã có ở Bước 1. Do cột `phone_number` được thiết lập ràng buộc `UNIQUE`, PostgreSQL sẽ lập tức quét chỉ mục (index) và phát hiện sự trùng lặp.
    *Lỗi hệ thống trả về (Expected ERROR):*
    ```text
    ERROR: duplicate key value violates unique constraint "customer_phone_number_key"
    DETAIL: Key (phone_number)=(0999888777) already exists.
    ```

* **Ý nghĩa & Bài học:** Ngay cả khi code ứng dụng thất bại trong việc chặn bản ghi trùng lặp do tải cao, database vẫn sẽ kiên quyết từ chối lưu bản ghi lỗi đó ở mức vật lý, giữ cho dữ liệu khách hàng luôn sạch và không bị lỗi đồng bộ.

---

### Kịch bản B — The Logic Guard (Ràng buộc logic đa cột)

**Khái niệm:** Một voucher đang có mức độ lan tỏa cực kỳ lớn (viral). Hàng ngàn người đang nhấn nút nhận nó. Chúng ta có quy tắc: `total_issued` không bao giờ được phép vượt quá `issuance_limit`. Trong DDL, chúng ta đã viết: `CONSTRAINT chk_total_issued CHECK (total_issued <= issuance_limit)`.

* **Hoạt động:**
  * **Bước 1 — Cố gắng cập nhật voucher vượt giới hạn một cách không hợp lệ:**
    ```sql
    -- Giả lập lỗi backend cố tình đẩy total_issued vượt quá hạn mức cho phép
    UPDATE linh_lab.voucher
    SET total_issued = :issuance_limit + 10    -- ← Cố ý cộng thêm 10 vượt giới hạn
    WHERE voucher_id = :voucher_id;
    ```
    *Giải thích:* Câu lệnh cố gắng đặt giá trị của cột `total_issued` (ví dụ: `1010`) lớn hơn giá trị của cột `issuance_limit` (ví dụ: `1000`). Database ngay khi nhận câu lệnh sẽ kiểm tra biểu thức logic của ràng buộc `CHECK (total_issued <= issuance_limit)`. Vì biểu thức này trả về `FALSE`, database sẽ chặn đứng thao tác cập nhật này.
    *Lỗi hệ thống trả về (Expected ERROR):*
    ```text
    ERROR: new row for relation "voucher" violates check constraint "chk_total_issued"
    DETAIL: Failing row contains (1, 1, 3, TET50K, AMOUNT, 50000.00, 1000, 1010, ...).
    ```

* **Ý nghĩa & Bài học:** Quy tắc nghiệp vụ (Business Rules) được định nghĩa trực tiếp vào cấu trúc bảng cơ sở dữ liệu là bất khả xâm phạm. Nó đảm bảo ngân sách marketing của chúng ta sẽ không bao giờ bị vượt chi bởi các lỗi logic của code ứng dụng hoặc lỗi làm tròn số học.

---

### Kịch bản C — The Automation Guard (Database Triggers)

**Khái niệm:** Mỗi khi một dòng dữ liệu bị sửa đổi, trường thời gian cập nhật `updated_at` phải tự động thay đổi. Nếu chúng ta phụ thuộc vào việc các nhà phát triển ứng dụng luôn phải nhớ viết `updated_at = NOW()` trong mọi câu lệnh `UPDATE`, chắc chắn sẽ có lúc họ quên. Trong database, chúng ta thiết lập Trigger `fn_set_updated_at()` để làm việc này hoàn toàn tự động.

* **Hoạt động:**
  * **Bước 1 — Kiểm tra mốc thời gian hiện tại:**
    ```sql
    SELECT program_name, updated_at
    FROM linh_lab.promotion_program
    WHERE program_id = :program_id;
    ```
    *Giải thích:* Ghi nhận giá trị thời gian `updated_at` hiện có của chương trình khuyến mãi (ví dụ: `2026-06-22 15:34:11`). Sau đó chờ khoảng 5 giây để thấy sự thay đổi rõ rệt.

  * **Bước 2 — Cập nhật chương trình (Không can thiệp đến updated_at trong câu lệnh):**
    ```sql
    UPDATE linh_lab.promotion_program
    SET program_name = program_name || ' (Updated)'
    -- Chú ý: Chúng ta HOÀN TOÀN KHÔNG đặt updated_at = NOW() ở đây!
    WHERE program_id = :program_id;
    ```
    *Giải thích:* Chạy lệnh sửa đổi tên chương trình khuyến mãi nhưng tuyệt đối không truyền giá trị cho cột `updated_at`. Lệnh này sẽ kích hoạt trigger `trg_promotion_program_updated_at` chạy ngầm trước khi dữ liệu được ghi xuống đĩa.

  * **Bước 3 — Xác minh trigger đã hoạt động:**
    ```sql
    SELECT program_name, updated_at
    FROM linh_lab.promotion_program
    WHERE program_id = :program_id;
    ```
    *Giải thích:* Truy vấn lại thông tin chương trình khuyến mãi.
    *Kết quả kỳ vọng:* Tên chương trình đã được đổi, và cột `updated_at` đã tự động tăng lên mốc thời gian thực tế chạy Bước 2, mặc dù trong câu lệnh `UPDATE` ta không hề đề cập đến cột này.

* **Ý nghĩa & Bài học:** Trigger đảm bảo tính nhất quán tuyệt đối của dữ liệu kiểm toán (Audit metadata). Dù dữ liệu được thay đổi qua code ứng dụng, qua API hay do DBA sửa tay trực tiếp trong database, mốc thời gian cập nhật vẫn luôn được ghi nhận chính xác 100%.

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

### Câu hỏi 1 — Defense in Depth (Phòng thủ đa lớp):
> Nếu ứng dụng backend (ví dụ: NodeJS hoặc Python) đã kiểm tra logic bằng code `if (total_issued >= issuance_limit) return error;` trước khi chạy lệnh UPDATE, tại sao chúng ta vẫn cần ràng buộc CHECK `chk_total_issued` trong database?

* **Trả lời:**
  * **Tranh chấp đồng thời (Concurrency):** Khi hàng ngàn người dùng bấm nút claim cùng 1 mili-giây, nhiều luồng của ứng dụng cùng đọc `total_issued = 999` (với limit = 1000). Cả hai đều thấy hợp lệ và đồng thời gửi lệnh update lên, khiến số lượng thực tế vọt lên `1001`. Cơ sở dữ liệu với isolation level và lock cơ chế sẽ chặn được race condition này nhờ ràng buộc CHECK ở mức vật lý.
  * **Đa kênh truy cập dữ liệu:** Trong thực tế, dữ liệu có thể được thay đổi từ các script bảo trì thủ công của DBA, các luồng đồng bộ dữ liệu (ETL/data pipeline), hoặc các công cụ GUI (DBeaver, pgAdmin) mà không thông qua code của ứng dụng. Ràng buộc ở database là tấm khiên cuối cùng đảm bảo dữ liệu luôn sạch.
  * **Phòng ngừa lỗi mã nguồn (Code Bugs):** Ứng dụng thay đổi phiên bản liên tục, một lập trình viên khác có thể viết nhầm hoặc quên kiểm tra logic này ở một API mới. Khai báo ràng buộc ở DB là vĩnh viễn và không phụ thuộc vào ứng dụng.

### Câu hỏi 2 — Automation Risks (Rủi ro thiếu tự động hóa):
> Trong Kịch bản C, DB trigger tự động cập nhật `updated_at`. Điều gì sẽ xảy ra với việc kiểm toán dữ liệu (data auditing) nếu chúng ta không có trigger này, và một Lập trình viên Junior chạy lệnh `UPDATE` thủ công trong DBeaver để sửa lỗi chính tả?

* **Trả lời:**
  * **Sai lệch thông tin kiểm toán:** Junior Developer chạy UPDATE sửa chữa lỗi chính tả nhưng không truyền cột `updated_at` trong câu lệnh. Dữ liệu đã bị thay đổi nhưng timestamp `updated_at` vẫn trỏ về mốc cũ của ứng dụng.
  * **Không thể truy vết sự cố:** Khi hệ thống xảy ra sự cố và cần kiểm toán xem ai đã làm thay đổi dữ liệu vào lúc nào, đội ngũ vận hành sẽ bị đánh lạc hướng bởi cột `updated_at` hiển thị thông tin sai lệch, gây khó khăn cho việc khắc phục hậu quả.
  * **Sự nhất quán:** Trigger tự động hóa ở tầng database đảm bảo tính đồng bộ tuyệt đối. Bất kể hành vi cập nhật đến từ đâu (ứng dụng, API, hay câu lệnh SQL gõ tay của dev), mốc thời gian sửa đổi và tài khoản sửa đổi luôn được ghi nhận chính xác 100%.

---

## 📦 File Deliverable

Sản phẩm của bài tập được lưu trữ tại:
```
tasks/ddid12_constraints/DDID12_03_constraints_consistency.sql
```
*(Đồng thời sao lưu một bản tại: `sql/marketing/DDID12_03_constraints_consistency.sql`)*

---

## ✔️ Acceptance Criteria (Definition of Done)
