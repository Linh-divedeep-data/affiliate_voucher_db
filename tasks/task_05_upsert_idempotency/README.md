# 📝 Bài 5 — Design for Retry: Idempotency với Database Upserts

## 🎯 Nội dung học tập & Bài học rút ra (Key Learnings)

Trong Data Engineering, **pipeline ETL/ELT chắc chắn sẽ thất bại** tại một thời điểm nào đó — do mạng timeout, disk đầy, API upstream trả lỗi, hay container bị kill giữa chừng.

Khi pipeline sập giữa chừng, chiến lược phục hồi phổ biến nhất là **chạy lại (retry)**. Tuy nhiên, nếu script SQL dùng `INSERT` thông thường, chạy lại sẽ gặp lỗi `UNIQUE Constraint Violation` → pipeline crash lần 2!

Trong bài thực hành này, bạn sẽ học cách:
1. Nhận diện vấn đề của pipeline "giòn" (fragile) khi dùng `INSERT` thông thường.
2. Thiết kế câu truy vấn **Idempotent** bằng cú pháp `ON CONFLICT` của PostgreSQL.
3. Phân biệt khi nào dùng `DO NOTHING` (Event Log) và khi nào dùng `DO UPDATE` (Dimension Table).

> **Idempotency** = "Chạy 1 lần hay 10.000 lần → trạng thái cuối cùng của database giống hệt nhau, không lỗi, không trùng dữ liệu."

---

## 🗂️ Các bảng Cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Thao tác thực thi (Operation) | Mục tiêu chính (Target Goal) |
|---|---|---|
| `linh_lab.partner_click` | `INSERT` + `ON CONFLICT DO NOTHING` | Nạp click stream an toàn — bỏ qua dòng trùng |
| `linh_lab.partner` | `INSERT` + `ON CONFLICT DO UPDATE` | Cập nhật Dimension table khi có dữ liệu mới |

---

## 🔑 Ngữ cảnh (Context)

Hãy tưởng tượng một **job ETL hàng ngày** kéo 100.000 affiliate clicks từ API bên thứ 3 và INSERT vào bảng `linh_lab.partner_click`.

**Ngày hôm qua:** Job chạy thành công 50.000 dòng đầu tiên, rồi **mạng sập**. 50.000 dòng còn lại chưa được nạp.

**Ngày hôm nay:** Chúng ta chạy lại toàn bộ job (retry). Job sẽ cố INSERT lại 50.000 dòng đầu tiên (đã tồn tại trong database) + 50.000 dòng còn lại (chưa có).

❓ **Câu hỏi:** Nếu dùng `INSERT` thông thường, điều gì sẽ xảy ra với 50.000 dòng đầu tiên đã tồn tại?

💥 **Đáp án:** Lỗi `duplicate key value violates unique constraint "partner_click_pkey"` → Pipeline crash lần 2!

Chúng ta cần một cách thanh lịch để nói: *"Nếu `click_id` đã tồn tại → bỏ qua. Nếu chưa có → INSERT bình thường."*

---

## ✅ BƯỚC 0 — Chuẩn bị (Prerequisites)

🎯 **Mục đích:** Làm quen với cấu trúc bảng `partner_click` và hiểu rằng `click_id` là **Primary Key** — mỗi click là một sự kiện duy nhất, không được trùng.

Kiểm tra dữ liệu hiện có trong bảng `partner_click`:

```sql
SELECT click_id, partner_code, partner_id, ip_address, clicked_at
FROM   linh_lab.partner_click
ORDER BY clicked_at DESC
LIMIT 5;
```

> Ghi nhận cấu trúc dữ liệu: `click_id` là **Primary Key** (VARCHAR), mỗi click là một sự kiện duy nhất.

---

## 🔬 Chi tiết các Kịch bản Thực hành (Scenarios)

### Kịch bản A — Pipeline Giòn (Fragile Pipeline — Standard INSERT)

**Bối cảnh:** Đây là cách viết INSERT "bình thường" mà hầu hết developer mới đều dùng. Chúng ta sẽ chứng minh nó KHÔNG AN TOÀN khi chạy lại.

---

**Bước 1 — Lần nạp đầu tiên (Thành công)**

🎯 **Mục đích:** Mô phỏng lần chạy đầu tiên của pipeline ETL — INSERT dữ liệu mới vào bảng. Bước này luôn thành công vì `click_id` chưa tồn tại.

```sql
INSERT INTO linh_lab.partner_click
    (click_id, partner_code, partner_id, ip_address, clicked_at, created_at, created_by)
VALUES
    ('RETRY_TEST_001', 'KOL001', 1, '192.168.1.1', NOW(), NOW(), 'ETL_USER');
```

> **Kết quả:** `INSERT 0 1` ✅ — Dòng mới được tạo thành công.

---

**Bước 2 — Pipeline Retry (CRASH!)**

🎯 **Mục đích:** Chứng minh rằng khi pipeline sập giữa chừng rồi chạy lại, `INSERT` thông thường sẽ **crash ngay lập tức** vì `click_id` đã tồn tại từ Bước 1 → vi phạm Primary Key.

Giả lập tình huống pipeline sập giữa chừng rồi chạy lại. Chúng ta chạy **chính xác câu INSERT ở Bước 1** lần thứ 2:

```sql
-- ⚠️ Chạy LẠI chính xác câu INSERT trên
INSERT INTO linh_lab.partner_click
    (click_id, partner_code, partner_id, ip_address, clicked_at, created_at, created_by)
VALUES
    ('RETRY_TEST_001', 'KOL001', 1, '192.168.1.1', NOW(), NOW(), 'ETL_USER');
```

> **Kết quả:** ❌ `ERROR: duplicate key value violates unique constraint "partner_click_pkey"`
>
> Pipeline crash lần 2! `click_id = 'RETRY_TEST_001'` đã tồn tại từ Bước 1 → PostgreSQL từ chối INSERT.

---

**Bài học rút ra:**

| Vấn đề | Giải thích |
|---|---|
| **Pipeline giòn** | Không thể chạy lại an toàn nếu có bất kỳ dòng nào đã tồn tại |
| **Yêu cầu logic phức tạp** | Developer phải tự viết code kiểm tra "dòng nào đã insert rồi, dòng nào chưa" → dễ sai, khó bảo trì |
| **Không phù hợp production** | Orchestration tool (Airflow, Dagster) không thể tự động retry |

---

### Kịch bản B — Pipeline Bất Tử (Bulletproof — Idempotent UPSERT với DO NOTHING)

**Bối cảnh:** Click stream là **Event Log bất biến (immutable)**. Một click đã xảy ra = một sự kiện lịch sử → không bao giờ thay đổi. Nếu pipeline retry và gửi lại click đã tồn tại, ta chỉ cần **bỏ qua** (skip) nó.

PostgreSQL cung cấp cú pháp `ON CONFLICT ... DO NOTHING` để xử lý chính xác tình huống này.

---

**Bước 1 — Refactor sang UPSERT (DO NOTHING)**

🎯 **Mục đích:** Viết lại câu INSERT với `ON CONFLICT DO NOTHING` — nếu `click_id` chưa tồn tại thì INSERT bình thường, nếu đã tồn tại thì **bỏ qua mà không báo lỗi**. Đây là nền tảng của Idempotency.

```sql
INSERT INTO linh_lab.partner_click
    (click_id, partner_code, partner_id, ip_address, clicked_at, created_at, created_by)
VALUES
    ('RETRY_TEST_002', 'KOL002', 2, '10.0.0.5', NOW(), NOW(), 'ETL_USER')
ON CONFLICT (click_id)     -- ← Nếu click_id đã tồn tại...
DO NOTHING;                 -- ← ...thì bỏ qua, không làm gì cả
```

> **Kết quả:** `INSERT 0 1` ✅ — `click_id = 'RETRY_TEST_002'` chưa tồn tại → INSERT bình thường.

**Giải thích cú pháp:**
| Phần | Ý nghĩa |
|---|---|
| `ON CONFLICT (click_id)` | Chỉ định cột nào kiểm tra xung đột (phải là PK hoặc UNIQUE) |
| `DO NOTHING` | Khi xung đột xảy ra → bỏ qua dòng đó, không lỗi, không INSERT |

---

**Bước 2 — Pipeline Retry (Bulletproof!)**

🎯 **Mục đích:** Chứng minh pipeline có thể **chạy lại an toàn** — cùng câu lệnh, cùng dữ liệu, nhưng không lỗi, không trùng. So sánh trực tiếp với Bước 2 của Scenario A (crash).

Chạy **chính xác câu UPSERT ở Bước 1** lần thứ 2:

```sql
-- ⚡ Chạy LẠI chính xác câu UPSERT trên
INSERT INTO linh_lab.partner_click
    (click_id, partner_code, partner_id, ip_address, clicked_at, created_at, created_by)
VALUES
    ('RETRY_TEST_002', 'KOL002', 2, '10.0.0.5', NOW(), NOW(), 'ETL_USER')
ON CONFLICT (click_id)
DO NOTHING;
```

> **Kết quả:** `INSERT 0 0` ✅ — Không lỗi! Không trùng dữ liệu! Số `0` nghĩa là "0 dòng được insert" vì click_id đã tồn tại → PostgreSQL âm thầm bỏ qua.

---

**Bước 3 — Xác minh tính Idempotent**

🎯 **Mục đích:** Kiểm chứng bằng SELECT rằng dù chạy INSERT 2 lần, database chỉ có **đúng 1 dòng** với dữ liệu **không thay đổi** — đây là bằng chứng của Idempotency.

```sql
SELECT click_id, partner_code, ip_address, created_at
FROM   linh_lab.partner_click
WHERE  click_id = 'RETRY_TEST_002';
```

> **Kết quả mong đợi:** Đúng **1 dòng duy nhất**, dữ liệu hoàn toàn không thay đổi dù đã chạy INSERT 2 lần.
>
> 🎯 **Đây chính là Idempotency** — pipeline sống sót qua retry mà không crash hay corrupt dữ liệu!

---

**So sánh Scenario A vs Scenario B:**

| Tiêu chí | Scenario A (INSERT) | Scenario B (UPSERT DO NOTHING) |
|---|---|---|
| Lần chạy đầu | ✅ Thành công | ✅ Thành công |
| Lần chạy lại (retry) | ❌ Crash — duplicate key | ✅ Bỏ qua — không lỗi |
| Dữ liệu cuối cùng | ❌ Không xác định | ✅ Chính xác 1 dòng |
| Có thể tự động retry? | ❌ Không | ✅ Có |
| Phù hợp production? | ❌ Không | ✅ Có |

---

### Kịch bản C — UPSERT cho Dimension Table (DO UPDATE)

**Bối cảnh:** Khác với Event Log (dữ liệu bất biến), **Dimension Table** chứa dữ liệu **có thể thay đổi** theo thời gian. Ví dụ: đối tác (partner) thay đổi tên, thay đổi commission rule, cập nhật thông tin liên hệ...

Khi pipeline retry, nếu partner đã tồn tại VÀ có dữ liệu mới hơn → ta muốn **CẬP NHẬT** dòng cũ, không phải bỏ qua.

PostgreSQL cung cấp `ON CONFLICT ... DO UPDATE SET ... = EXCLUDED...` cho tình huống này.

---

**Bước 1 — INSERT lần đầu (Tạo mới partner)**

🎯 **Mục đích:** Nạp dữ liệu partner mới vào bảng `partner`. Dùng `ON CONFLICT DO UPDATE` để câu lệnh hoạt động đúng cho cả trường hợp partner **chưa tồn tại** (tạo mới) và **đã tồn tại** (cập nhật).

```sql
INSERT INTO linh_lab.partner
    (partner_id, partner_code, partner_name, commission_rule_id, created_at, created_by)
VALUES
    (9999, 'PARTNER_UPSERT_TEST', 'Đối Tác Test Ban Đầu', 1, NOW(), 'ETL_USER')
ON CONFLICT (partner_code)
DO UPDATE SET
    partner_name       = EXCLUDED.partner_name,
    commission_rule_id = EXCLUDED.commission_rule_id,
    updated_at         = NOW(),
    updated_by         = 'ETL_USER';
```

> **Kết quả:** `INSERT 0 1` — Partner mới được tạo với `partner_name = 'Đối Tác Test Ban Đầu'` và `commission_rule_id = 1`.

**Giải thích cú pháp:**
| Phần | Ý nghĩa |
|---|---|
| `ON CONFLICT (partner_code)` | Kiểm tra xung đột trên cột UNIQUE `partner_code` |
| `DO UPDATE SET ...` | Khi xung đột → cập nhật dòng hiện tại thay vì bỏ qua |
| `EXCLUDED.partner_name` | `EXCLUDED` là bảng ảo chứa dòng dữ liệu **MỚI** đang cố INSERT |
| `updated_at = NOW()` | Ghi nhận thời điểm cập nhật (giữ nguyên `created_at` ban đầu) |

---

**Bước 2 — Pipeline chạy lại với dữ liệu mới hơn từ source**

🎯 **Mục đích:** Chứng minh `DO UPDATE` không chỉ idempotent mà còn **tự động cập nhật** dữ liệu khi source system gửi giá trị mới hơn. `created_at` giữ nguyên (lịch sử), `updated_at` thay đổi (thời điểm cập nhật).

Giả lập tình huống: source system gửi lại partner này nhưng tên đã đổi và commission rule đã thay đổi:

```sql
INSERT INTO linh_lab.partner
    (partner_id, partner_code, partner_name, commission_rule_id, created_at, created_by)
VALUES
    (9999, 'PARTNER_UPSERT_TEST', 'Đối Tác Test — Đã Cập Nhật', 2, NOW(), 'ETL_USER')
ON CONFLICT (partner_code)
DO UPDATE SET
    partner_name       = EXCLUDED.partner_name,
    commission_rule_id = EXCLUDED.commission_rule_id,
    updated_at         = NOW(),
    updated_by         = 'ETL_USER';
```

> **Kết quả:** `INSERT 0 1` — Dòng cũ được **CẬP NHẬT** (không tạo dòng mới):
> - `partner_name` đổi từ `'Đối Tác Test Ban Đầu'` → `'Đối Tác Test — Đã Cập Nhật'`
> - `commission_rule_id` đổi từ `1` → `2`
> - `created_at` **giữ nguyên** (thời điểm tạo ban đầu)
> - `updated_at` **cập nhật** = thời điểm hiện tại

---

**Bước 3 — Kiểm chứng kết quả**

🎯 **Mục đích:** Xác nhận rằng chỉ có **1 dòng** trong bảng (không trùng), với giá trị **đã được cập nhật** từ Bước 2. Đây là bằng chứng `DO UPDATE` hoạt động đúng cho Dimension table.

```sql
SELECT partner_code, partner_name, commission_rule_id, created_at, updated_at
FROM   linh_lab.partner
WHERE  partner_code = 'PARTNER_UPSERT_TEST';
```

> **Kết quả mong đợi:** Đúng **1 dòng**, với `partner_name = 'Đối Tác Test — Đã Cập Nhật'` và `commission_rule_id = 2`.

---

## 📊 Tổng Kết: Khi Nào Dùng Pattern Nào?

| Loại Bảng | Ví Dụ Trong Dự Án | Pattern | Lý Do |
|---|---|---|---|
| **Event / Fact** (bất biến) | `partner_click`, `budget_transaction` | `ON CONFLICT DO NOTHING` | Sự kiện đã xảy ra = không bao giờ thay đổi |
| **Dimension** (thay đổi theo thời gian) | `partner`, `customer`, `commission_rule` | `ON CONFLICT DO UPDATE` | Thuộc tính thay đổi → cần cập nhật giá trị mới nhất |

---

## 🧹 Dọn dẹp dữ liệu test

Sau khi hoàn thành bài thực hành, chạy lệnh dọn dẹp:

```sql
DELETE FROM linh_lab.partner_click WHERE click_id IN ('RETRY_TEST_001', 'RETRY_TEST_002');
DELETE FROM linh_lab.partner       WHERE partner_code = 'PARTNER_UPSERT_TEST';
```

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

### Câu hỏi 1:
> "Tại sao 'Idempotency' được coi là một trong những design pattern quan trọng nhất cho Data Engineer khi xây dựng pipeline ETL?"

**Trả lời:**

Trong thực tế, pipeline ETL **chắc chắn sẽ thất bại** tại một thời điểm nào đó — do mạng timeout, disk đầy, API upstream trả lỗi, hay container bị kill.

Khi thất bại, chiến lược phục hồi phổ biến nhất là **RETRY** (chạy lại). Nếu pipeline không idempotent:
- `INSERT` lại → `duplicate key error` → pipeline crash lần 2
- Hoặc tệ hơn: INSERT thành công nhưng **tạo bản ghi trùng** → dữ liệu sai

Idempotency đảm bảo:
1. Pipeline có thể chạy lại **bất kỳ lúc nào** mà không sợ lỗi
2. Kết quả cuối cùng **luôn đúng** bất kể chạy 1 hay N lần
3. Đơn giản hóa error handling — không cần logic phức tạp để track "đã insert đến đâu rồi"
4. Cho phép orchestration tool (Airflow, Dagster) **tự động retry** mà không cần can thiệp thủ công

> **Tóm lại:** Idempotency biến pipeline từ "giòn" (fragile) thành "bất tử" (bulletproof) — đây là yêu cầu bắt buộc cho production-grade data systems.

---

### Câu hỏi 2:
> "Trong Scenario B, ta dùng `DO NOTHING` vì click stream là event log bất biến. Nếu nạp Dimension table (ví dụ: `linh_lab.partner`), làm thế nào dùng `DO UPDATE SET ... = EXCLUDED...` để cập nhật khi xảy ra conflict?"

**Trả lời:**

Dimension table khác Event Log ở chỗ: dữ liệu **có thể thay đổi**. Ví dụ: đối tác thay đổi commission rule → cần UPDATE dòng cũ.

```sql
INSERT INTO linh_lab.partner (partner_code, partner_name, commission_rule_id, created_at, created_by)
VALUES ('KOL001', 'Partner Mới', 3, NOW(), 'ETL_USER')
ON CONFLICT (partner_code)
DO UPDATE SET
    partner_name       = EXCLUDED.partner_name,       -- Lấy giá trị MỚI
    commission_rule_id = EXCLUDED.commission_rule_id,  -- Lấy giá trị MỚI
    updated_at         = NOW(),                        -- Ghi thời điểm cập nhật
    updated_by         = 'ETL_USER';
```

| Từ khóa | Giải thích |
|---|---|
| `EXCLUDED` | Bảng ảo chứa dòng dữ liệu **mới** đang cố INSERT |
| `EXCLUDED.partner_name` | Giá trị `partner_name` từ câu VALUES (dữ liệu mới nhất) |
| `created_at` | **Không đưa vào** `DO UPDATE SET` → giữ nguyên thời điểm tạo ban đầu |
| `updated_at = NOW()` | Ghi nhận thời điểm thay đổi gần nhất |

> Pattern này gọi là **"Upsert"** — kết hợp INSERT + UPDATE trong 1 câu lệnh, đảm bảo idempotent cho cả Fact table (`DO NOTHING`) lẫn Dimension table (`DO UPDATE`). Xem demo đầy đủ tại Scenario C.

---

## 📦 File Deliverable

Sản phẩm của bài tập được lưu trữ tại:
```
tasks/task_05_upsert_idempotency/upsert_idempotency.sql
```
