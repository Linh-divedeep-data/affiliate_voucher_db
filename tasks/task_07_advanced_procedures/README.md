# 📝 Bài 7 — Advanced Data Orchestration & Dynamic Reporting

## Kiến thức đạt được

> Đây là những gì cần **ghi nhớ và mang theo áp dụng cho các dự án sau** — không phải bản tóm tắt việc đã làm trong task này.

| Nội dung chính | Ghi nhớ & áp dụng cho dự án sau |
|---|---|
| **Quy trình nhiều bước → đóng gói ở DB** | Quy trình nghiệp vụ nhiều bước phụ thuộc nhau (đọc → tính → ghi → đánh dấu) nếu để Backend điều phối từng bước sẽ có 2 rủi ro: network latency (mỗi bước tốn 1 round-trip) và partial failure (mạng sập giữa 2 bước để lại dữ liệu nửa vời). Đóng gói vào `PROCEDURE` loại bỏ cả hai. |
| **PROCEDURE (ghi) vs FUNCTION (đọc)** | `PROCEDURE` (`CALL`, tự `COMMIT`/`ROLLBACK` được) dùng cho quy trình ghi nhiều bước cần `EXCEPTION` handler riêng. `FUNCTION` (chạy trong transaction của caller) dùng cho báo cáo/tính toán, trả `TABLE` cho tầng đọc — chọn nhầm loại sẽ không đạt transaction safety cần thiết. |
| **Tham số mảng & FILTER cho báo cáo động** | `BIGINT[]` + `= ANY()` để lọc theo danh sách ID linh hoạt; `FILTER (WHERE ...)` cho aggregate có điều kiện trong cùng 1 `SELECT` — 2 kỹ thuật tái sử dụng cho mọi hàm báo cáo động ở dự án khác. |
| **Chỉ đẩy xuống DB khi thực sự cần nguyên tử+hiệu năng** | PL/pgSQL khó version-control/test như code ứng dụng, khó scale ngang, không phải ai cũng thành thạo — chỉ nên áp dụng cho quy trình thực sự cần tính nguyên tử chặt và hiệu năng cao trên khối lượng lớn, không phải mặc định cho mọi logic. |
| **Idempotency tự nhiên qua điều kiện lọc trạng thái** | Một procedure lọc theo `WHERE status IS NULL`/`= pending` sẽ tự động idempotent (chạy lại không xử lý trùng) — nhưng nếu điều kiện lọc bị sửa sai, chạy lại có thể tính trùng kết quả; luôn kiểm tra kỹ điều kiện này khi review code. |
| **Áp dụng khi thấy Backend "điều phối" nhiều câu SQL** | Ngay khi thấy code ứng dụng gọi nhiều câu SQL liên tiếp để hoàn thành 1 quy trình ghi — cân nhắc gộp thành 1 Stored Procedure duy nhất trước khi optimize theo hướng khác. |

---

## 🎯 Nội dung học tập & Bài học rút ra (Key Learnings)

Ở các bài trước, dữ liệu được bảo vệ bằng Constraints, Locks, và Triggers — các cơ chế **phản ứng tự động**. Tuy nhiên, quy trình nghiệp vụ thực tế thường bao gồm **nhiều bước phức tạp** (đọc → tính toán → ghi → thông báo). Đẩy toàn bộ logic này lên Backend (NodeJS/Python) có 2 rủi ro:

| Rủi ro | Giải thích |
|---|---|
| **Network latency** | Mỗi bước = 1 round-trip qua mạng → chậm khi xử lý hàng triệu dòng |
| **Partial failure** | Nếu mạng sập giữa bước 2 và bước 3 → dữ liệu "nửa vời" |

Giải pháp: **Đóng gói logic vào Stored Procedure/Function** — chạy trực tiếp trong database engine, không qua mạng.

Trong bài thực hành này, bạn sẽ học cách:
1. Viết **Stored Procedure** với `EXCEPTION ... ROLLBACK` cho quy trình chốt sổ cuối tháng.
2. Viết **Dynamic Reporting Functions** trả về `TABLE`, hỗ trợ lọc bằng `BIGINT[]` (array parameter).
3. Phân biệt khi nào dùng `PROCEDURE` (ghi dữ liệu) và `FUNCTION` (đọc/tính toán).

---

## 🗂️ Các bảng Cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Thao tác thực thi (Operation) | Mục tiêu chính (Target Goal) |
|---|---|---|
| `linh_lab.partner_click` | Quét & đánh dấu đã đối soát | Chốt sổ click hợp lệ cuối tháng |
| `linh_lab.partner` | Đọc thông tin đối tác | Lấy tên, mã đối tác |
| `linh_lab.commission_rule` | Đọc tỷ lệ hoa hồng | Tính tổng payout |
| `linh_lab.promotion_program` | Đọc ngân sách chương trình | Báo cáo sử dụng ngân sách |
| `linh_lab.budget_transaction` | Tổng hợp thu/chi | Tính chi tiêu thực tế (Double-Entry Ledger) |

---

## 🔑 Ngữ cảnh (Context)

### 1. Reconciliation (Chốt sổ cuối tháng)

Vào **23:59 ngày cuối mỗi tháng**, hệ thống phải tính hoa hồng cho đối tác. Quy trình:
1. Quét toàn bộ click hợp lệ (`is_suspicious = FALSE`) chưa đối soát
2. Đánh dấu các click này là "đã đối soát" (`reconciliation_status_id = 1`)
3. Tính tổng payout = `valid_clicks × payout_rate`
4. Nếu có lỗi bất kỳ → `ROLLBACK` toàn bộ, không có dữ liệu "nửa vời"

### 2. Dynamic Reporting (Báo cáo động)

Marketing Manager cần theo dõi KPI real-time:
- **Partner Performance:** Tổng click, click gian lận, tỉ lệ fraud
- **Campaign Budget Usage:** Ngân sách đã chi, còn lại, % sử dụng

Thay vì fetch raw tables về backend rồi tính toán, ta viết `FUNCTION` trả về `TABLE` đã tính sẵn — backend chỉ cần `SELECT * FROM fn_...(...)`.

---

## 📖 Khái Niệm Cốt Lõi: PROCEDURE vs FUNCTION

| Tiêu chí | FUNCTION | PROCEDURE |
|---|---|---|
| **Gọi bằng** | `SELECT fn_name(...)` | `CALL sp_name(...)` |
| **Trả về** | Giá trị / TABLE | Không trả về giá trị |
| **Transaction control** | ❌ KHÔNG được COMMIT/ROLLBACK bên trong | ✅ CÓ THỂ COMMIT/ROLLBACK |
| **Dùng trong SELECT** | ✅ `SELECT * FROM fn(...)` | ❌ Không thể |
| **Use case** | Đọc dữ liệu, tính toán, báo cáo | Quy trình nghiệp vụ nhiều bước, ghi dữ liệu |

> **Tóm lại:** FUNCTION = "máy tính" (chỉ đọc, trả kết quả) · PROCEDURE = "quy trình công việc" (đọc + ghi, kiểm soát transaction)

---

## 🔬 Chi tiết các Bước Thực hành

### Bước 1 — Stored Procedure: Chốt Sổ Đối Tác Cuối Tháng

🎯 **Mục đích:** Đóng gói toàn bộ quy trình đối soát hoa hồng vào 1 Procedure duy nhất. Procedure nhận `partner_id`, `month`, `year` → tự động đếm click hợp lệ, đánh dấu đã đối soát, tính payout. Nếu có lỗi → `ROLLBACK` toàn bộ.

```sql
CREATE OR REPLACE PROCEDURE linh_lab.sp_reconcile_partner_payout(
    p_partner_id  BIGINT,
    p_month       INT,
    p_year        INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_valid_clicks  INT;
    v_payout_rate         NUMERIC;
    v_total_payout        NUMERIC;
    v_partner_name        VARCHAR;
BEGIN
    -- Bước 1.1: Lấy thông tin đối tác và tỷ lệ hoa hồng
    SELECT p.partner_name, cr.payout_rate
    INTO   v_partner_name, v_payout_rate
    FROM   linh_lab.partner p
    JOIN   linh_lab.commission_rule cr
           ON p.commission_rule_id = cr.commission_rule_id
    WHERE  p.partner_id = p_partner_id
      AND  p.is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partner ID % not found or has been deleted', p_partner_id;
    END IF;

    -- Bước 1.2: Đếm click hợp lệ CHƯA đối soát (Idempotent)
    SELECT COUNT(*) INTO v_total_valid_clicks
    FROM   linh_lab.partner_click
    WHERE  partner_id = p_partner_id
      AND  is_suspicious = FALSE
      AND  reconciliation_status_id IS NULL
      AND  EXTRACT(MONTH FROM clicked_at) = p_month
      AND  EXTRACT(YEAR  FROM clicked_at) = p_year;

    -- Bước 1.3: Đánh dấu các click đã đối soát
    UPDATE linh_lab.partner_click
    SET    reconciliation_status_id = 1,
           reconciled_at = NOW(),
           reconciled_by = 'SYSTEM_PROCEDURE'
    WHERE  partner_id = p_partner_id
      AND  is_suspicious = FALSE
      AND  reconciliation_status_id IS NULL
      AND  EXTRACT(MONTH FROM clicked_at) = p_month
      AND  EXTRACT(YEAR  FROM clicked_at) = p_year;

    -- Bước 1.4: Tính payout và thông báo
    v_total_payout := v_total_valid_clicks * v_payout_rate;
    RAISE INFO '✅ Partner: % | Clicks: % | Payout: % VND',
               v_partner_name, v_total_valid_clicks, v_total_payout;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE WARNING '❌ Reconciliation FAILED: %', SQLERRM;
END;
$$;
```

**Giải thích luồng xử lý:**

```
CALL sp_reconcile_partner_payout(1, 6, 2026)
  │
  ├─ 1.1 SELECT partner + payout_rate
  │   └─ NOT FOUND? → RAISE EXCEPTION → nhảy vào EXCEPTION block → ROLLBACK
  │
  ├─ 1.2 COUNT click hợp lệ chưa đối soát
  │
  ├─ 1.3 UPDATE click → reconciled
  │   └─ Lỗi bất kỳ? → nhảy vào EXCEPTION block → ROLLBACK
  │
  ├─ 1.4 Tính payout, RAISE INFO
  │
  └─ COMMIT ✅ (chỉ khi TẤT CẢ bước thành công)
```

**Tính Idempotent:** Chạy procedure lần 2 cho cùng tháng → `valid_clicks = 0` vì tất cả click đã được đánh dấu `reconciliation_status_id = 1` ở lần 1.

---

### Bước 2 — Dynamic Function 1: Báo Cáo Hiệu Suất Đối Tác

🎯 **Mục đích:** Tạo function trả về `TABLE` chứa KPI hiệu suất đối tác — tổng click, click hợp lệ, click gian lận, tỉ lệ fraud. Hỗ trợ lọc bằng `BIGINT[]` — nếu `NULL` thì trả về tất cả đối tác.

```sql
CREATE OR REPLACE FUNCTION linh_lab.fn_partner_performance_report(
    p_start_date   TIMESTAMP,
    p_end_date     TIMESTAMP,
    p_partner_ids  BIGINT[] DEFAULT NULL   -- NULL = tất cả đối tác
)
RETURNS TABLE (
    partner_code       VARCHAR,
    partner_name       VARCHAR,
    total_clicks       BIGINT,
    valid_clicks       BIGINT,
    suspicious_clicks  BIGINT,
    fraud_rate_pct     NUMERIC
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        p.partner_code,
        p.partner_name,
        COUNT(pc.click_id)                                          AS total_clicks,
        COUNT(pc.click_id) FILTER (WHERE pc.is_suspicious = FALSE)  AS valid_clicks,
        COUNT(pc.click_id) FILTER (WHERE pc.is_suspicious = TRUE)   AS suspicious_clicks,
        ROUND(
            COUNT(pc.click_id) FILTER (WHERE pc.is_suspicious = TRUE) * 100.0
            / NULLIF(COUNT(pc.click_id), 0),
            2
        )                                                           AS fraud_rate_pct
    FROM   linh_lab.partner p
    LEFT JOIN linh_lab.partner_click pc
           ON p.partner_id = pc.partner_id
          AND pc.clicked_at BETWEEN p_start_date AND p_end_date
    WHERE  p.is_deleted = FALSE
      AND  (p_partner_ids IS NULL OR p.partner_id = ANY(p_partner_ids))
    GROUP BY p.partner_code, p.partner_name
    ORDER BY total_clicks DESC;
$$;
```

**Giải thích kỹ thuật chính:**

| Kỹ thuật | Giải thích |
|---|---|
| `RETURNS TABLE (...)` | Function trả về nhiều dòng, nhiều cột — dùng như bảng ảo |
| `FILTER (WHERE ...)` | Aggregate có điều kiện — đếm riêng click hợp lệ/gian lận trong cùng 1 query |
| `NULLIF(COUNT, 0)` | Tránh chia cho 0 khi tính `fraud_rate_pct` |
| `ANY(p_partner_ids)` | So sánh `partner_id` với từng phần tử trong mảng BIGINT[] |
| `STABLE` | Đánh dấu function chỉ ĐỌC → PostgreSQL optimizer tối ưu hóa |

---

### Bước 3 — Dynamic Function 2: Báo Cáo Sử Dụng Ngân Sách

🎯 **Mục đích:** Tạo function tính ngân sách còn lại theo **Double-Entry Ledger pattern** — tổng chi = `SUM(amount) WHERE entry_type = 'spend'`, remaining = `budget_limit - actual_spent`. Hỗ trợ lọc theo `status_id` và `BIGINT[]` program_ids.

```sql
CREATE OR REPLACE FUNCTION linh_lab.fn_program_budget_usage(
    p_status_id    BIGINT   DEFAULT NULL,    -- NULL = tất cả trạng thái
    p_program_ids  BIGINT[] DEFAULT NULL     -- NULL = tất cả chương trình
)
RETURNS TABLE (
    program_name      VARCHAR,
    budget_limit      NUMERIC,
    total_income      NUMERIC,
    actual_spent      NUMERIC,
    remaining_budget  NUMERIC,
    usage_pct         NUMERIC
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        pp.program_name,
        pp.budget_limit,
        COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'income'), 0)      AS total_income,
        COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0)       AS actual_spent,
        pp.budget_limit
            - COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0) AS remaining_budget,
        ROUND(
            COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0) * 100.0
            / NULLIF(pp.budget_limit, 0),
            2
        )                                                                         AS usage_pct
    FROM   linh_lab.promotion_program pp
    LEFT JOIN linh_lab.budget_transaction bt
           ON pp.program_id = bt.program_id
          AND bt.is_deleted = FALSE
    WHERE  pp.is_deleted = FALSE
      AND  (p_status_id   IS NULL OR pp.status_id = p_status_id)
      AND  (p_program_ids IS NULL OR pp.program_id = ANY(p_program_ids))
    GROUP BY pp.program_name, pp.budget_limit
    ORDER BY usage_pct DESC NULLS LAST;
$$;
```

**Giải thích Double-Entry Ledger trong function:**

| Cột | Công thức | Ý nghĩa |
|---|---|---|
| `total_income` | `SUM(amount) FILTER (entry_type = 'income')` | Tổng ngân sách đã nạp |
| `actual_spent` | `SUM(amount) FILTER (entry_type = 'spend')` | Tổng chi tiêu thực tế |
| `remaining_budget` | `budget_limit - actual_spent` | Ngân sách còn lại |
| `usage_pct` | `actual_spent / budget_limit × 100` | Phần trăm đã sử dụng |

---

### Bước 4 — Kiểm Thử (Testing)

#### 4A — Kiểm thử Procedure: Chốt sổ đối tác

🎯 **Mục đích:** Xác minh procedure chạy đúng luồng — đếm click, đánh dấu reconciled, tính payout. Chạy lần 2 phải **idempotent** (0 click vì đã đối soát hết ở lần 1).

```sql
-- Lần 1: Chốt sổ đối tác ID=1, tháng 6/2026
CALL linh_lab.sp_reconcile_partner_payout(1, 6, 2026);
-- Kết quả mong đợi: ✅ Partner: ... | Clicks: N | Payout: X VND

-- Lần 2: Chạy lại — kiểm tra idempotency
CALL linh_lab.sp_reconcile_partner_payout(1, 6, 2026);
-- Kết quả mong đợi: ✅ Clicks: 0 | Payout: 0 VND (đã đối soát hết)
```

**Kiểm chứng click đã được đánh dấu:**
```sql
SELECT click_id, partner_id, reconciliation_status_id, reconciled_at, reconciled_by
FROM   linh_lab.partner_click
WHERE  partner_id = 1
  AND  reconciliation_status_id IS NOT NULL
LIMIT 5;
```

> **Kết quả:** Các click hiển thị `reconciliation_status_id = 1`, `reconciled_by = 'SYSTEM_PROCEDURE'`.

---

#### 4B — Kiểm thử Function 1: Báo cáo hiệu suất

🎯 **Mục đích:** Xác minh function trả về đúng KPI (total_clicks, valid_clicks, fraud_rate) và hỗ trợ lọc bằng `BIGINT[]` array.

```sql
-- Tất cả đối tác trong tháng 6/2026
SELECT * FROM linh_lab.fn_partner_performance_report(
    '2026-06-01'::TIMESTAMP,
    '2026-06-30'::TIMESTAMP
);

-- Chỉ đối tác ID 1 và 2
SELECT * FROM linh_lab.fn_partner_performance_report(
    '2026-06-01'::TIMESTAMP,
    '2026-06-30'::TIMESTAMP,
    ARRAY[1, 2]::BIGINT[]
);
```

> **So sánh:** Kết quả lần 2 chỉ chứa partner_id 1 và 2 — array filter hoạt động đúng.

---

#### 4C — Kiểm thử Function 2: Báo cáo ngân sách

🎯 **Mục đích:** Xác minh tính toán `remaining_budget` đúng theo Double-Entry Ledger, và array filter hoạt động.

```sql
-- Tất cả chương trình
SELECT * FROM linh_lab.fn_program_budget_usage();

-- Chỉ chương trình đang Active (giả sử status_id = 2)
SELECT * FROM linh_lab.fn_program_budget_usage(2);

-- Chỉ chương trình cụ thể
SELECT * FROM linh_lab.fn_program_budget_usage(NULL, ARRAY[1, 2]::BIGINT[]);
```

> **Kiểm chứng:** `remaining_budget = budget_limit - actual_spent` → giá trị phải khớp.

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

### Câu hỏi 1:
> "Trong cấu trúc Procedure ở trên, tại sao lệnh `ROLLBACK` được đặt bên trong khối `EXCEPTION`? Nếu thiếu khối EXCEPTION, thảm họa kinh tế nào có thể xảy ra nếu server mất điện giữa chừng lệnh UPDATE?"

**Trả lời:**

Khối `EXCEPTION` hoạt động như **"tấm lưới an toàn"** (safety net):

| Tình huống | Có EXCEPTION block | Không có EXCEPTION block |
|---|---|---|
| Lỗi logic (partner không tồn tại) | `ROLLBACK` → dữ liệu nguyên vẹn | Unhandled exception → crash |
| Lỗi runtime (constraint violation) | `ROLLBACK` + `RAISE WARNING` | Transaction abort, không log lỗi |
| Server mất điện giữa UPDATE | PostgreSQL tự ROLLBACK uncommitted txn | Tương tự (WAL recovery) |

> **Lưu ý quan trọng:** PostgreSQL mặc định đã có transaction safety — nếu server crash, transaction chưa COMMIT sẽ tự động ROLLBACK khi recovery nhờ WAL (Write-Ahead Log). Khối EXCEPTION ở đây chủ yếu bắt **lỗi logic** để procedure kết thúc gracefully.

---

### Câu hỏi 2:
> "Sự khác biệt lớn nhất giữa `FUNCTION` và `PROCEDURE` trong PostgreSQL là gì?"

**Trả lời:**

| Tiêu chí | FUNCTION | PROCEDURE |
|---|---|---|
| **Gọi bằng** | `SELECT fn_name(...)` | `CALL sp_name(...)` |
| **Trả về** | Giá trị / TABLE | Không trả về giá trị |
| **Transaction control** | ❌ KHÔNG được COMMIT/ROLLBACK | ✅ CÓ THỂ COMMIT/ROLLBACK |
| **Dùng trong SELECT** | ✅ Có | ❌ Không |
| **Use case** | Đọc, tính toán, báo cáo | Quy trình nhiều bước, ghi dữ liệu |

> **Tóm lại:** `sp_reconcile` dùng PROCEDURE vì nó **UPDATE dữ liệu** và cần ROLLBACK nếu lỗi. `fn_partner_performance_report` dùng FUNCTION vì nó chỉ **SELECT** và trả TABLE.

---

## 📦 File Deliverable

Sản phẩm của bài tập được lưu trữ tại:
```
tasks/task_07_advanced_procedures/advanced_procedures.sql
```
