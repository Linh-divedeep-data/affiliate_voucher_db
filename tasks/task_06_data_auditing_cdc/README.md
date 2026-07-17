# 📝 Bài 6 — Data Auditing: Primitive Change Data Capture (CDC)

## Kiến thức đạt được

> Đây là những gì cần **ghi nhớ và mang theo áp dụng cho các dự án sau** — không phải bản tóm tắt việc đã làm trong task này.

| Nội dung chính | Ghi nhớ & áp dụng cho dự án sau |
|---|---|
| **`updated_at` không đủ, cần History Table** | Với bất kỳ bảng nào chứa dữ liệu "có thể bị sửa và việc biết giá trị cũ là quan trọng" (cấu hình, ngân sách, trạng thái hợp đồng...), đừng chỉ dựa vào cột `updated_at` — nó chỉ nói "có đổi", không nói "đổi từ đâu". Cần History Table + Trigger `AFTER UPDATE` để giữ lại giá trị cũ. |
| **Câu hỏi nghiệp vụ báo hiệu cần audit trail** | Dạng "nếu nhân viên sửa nhầm thì sao?", "làm sao biết ai đã đổi giá trị này?", "có cần khôi phục lại bản trước không?" — mỗi câu như vậy là tín hiệu cần audit trail, bất kể domain của dự án là gì. |
| **IS DISTINCT FROM & AFTER UPDATE** | `IS DISTINCT FROM` (không phải `<>`) khi so sánh `OLD`/`NEW` trong trigger — xử lý đúng trường hợp giá trị liên quan tới `NULL`; luôn dùng `AFTER` (không `BEFORE`) cho trigger ghi log, tránh ghi lại cả thay đổi bị hủy sau đó. |
| **Trigger-based vs WAL-based CDC** | Trigger-based (đơn giản, đủ cho dự án vừa và nhỏ) vs WAL-based/Debezium (khi cần tách hẳn audit khỏi latency đường ghi chính hoặc cần real-time) — chọn theo quy mô ghi và yêu cầu độ trễ, không mặc định chọn cái phức tạp hơn nếu chưa cần. |
| **Bảng history cần chiến lược dọn dẹp ngay từ đầu** | Phải có kế hoạch archival/partition theo thời gian ngay từ khi tạo bảng history — nếu không, bảng sẽ phình to vô hạn và làm chậm cả ghi lẫn đọc sau vài năm (xem Task 11 — Partitioning). |
| **Mặc định thêm audit trail khi thiết kế schema mới** | Với bất kỳ bảng nào lưu "cấu hình/trạng thái quan trọng có thể bị sửa" ở dự án mới — thêm audit trail ngay từ đầu thay vì chỉ thêm `updated_at` rồi tính sau. |

---

## 🎯 Nội dung học tập & Bài học rút ra (Key Learnings)

**Nội dung chính:**

Khi bạn UPDATE dữ liệu (ví dụ: thay đổi ngân sách khuyến mãi), thông tin cũ sẽ bị mất mãi mãi nếu chỉ có cột `updated_at`.
Task này dạy bạn cách lưu lịch sử thay đổi để sau này có thể xem lại hoặc khôi phục dữ liệu cũ.

### Vấn đề thực tế

Giả sử nhân viên thay đổi ngân sách khuyến mãi từ 50 triệu → 500 triệu:
- Cột `updated_at` chỉ ghi "đã thay đổi lúc 14h30"
- Nhưng giá trị cũ **50 triệu** thì **mất hoàn toàn**
- Sau này muốn xem lịch sử hoặc rollback → Không có dữ liệu cũ

### Giải pháp trong task này

Bạn sẽ học cách:
1. Tạo **History Table** (bảng lưu lịch sử) — lưu bản sao dữ liệu cũ trước khi update.
2. Viết **Trigger Function** — tự động chạy mỗi khi UPDATE xảy ra.
3. Gắn **Trigger** vào bảng gốc — để tự động lưu lịch sử.
4. Dùng History Table để **khôi phục dữ liệu cũ** nếu cần.

### Change Data Capture (CDC)

Đây là kỹ thuật **bắt giữ mọi thay đổi** của dữ liệu.
- **Trong bài này:** Dùng Trigger + History Table (cách thủ công)
- **Sau này sẽ học tool hiện đại:** Debezium, Kafka Connect...

> **Tóm tắt dễ nhớ:**
> Mỗi lần UPDATE, đừng để dữ liệu cũ biến mất.
> Hãy tạo bảng lịch sử để lưu lại phiên bản cũ trước khi thay đổi.
> Đây là kỹ năng quan trọng trong Data Engineering để audit (kiểm toán) và khôi phục dữ liệu.

---

## 🗂️ Các bảng Cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Thao tác thực thi (Operation) | Mục tiêu chính (Target Goal) |
|---|---|---|
| `linh_lab.promotion_program_history` | `CREATE TABLE` (bảng mới) | Lưu trữ giá trị CŨ trước mỗi lần UPDATE |
| `linh_lab.promotion_program` | Gắn `AFTER UPDATE` Trigger | Tự động ghi audit log khi dữ liệu thay đổi |

---

## 🔑 Ngữ cảnh (Context)

Trong OLTP Database, việc theo dõi **AI** đã thay đổi **CÁI GÌ** và **KHI NÀO** được gọi là **Audit Logging** hay **Change Data Capture (CDC)** nguyên thủy.

Kiến trúc Data Engineering hiện đại thường dùng tool bên ngoài (Debezium, Kafka) để stream CDC logs. Tuy nhiên, hiểu cách track thay đổi **trực tiếp ở tầng Database bằng Trigger** là kỹ năng nền tảng mà mọi Data Engineer cần nắm.

**Ý tưởng cốt lõi:** Ra lệnh cho database "lưu một bản sao lưu (backup copy) của dòng CŨ" ngay trước khi cho phép UPDATE xảy ra.

---

## 🔬 Chi tiết các Bước Thực hành

Khi bạn UPDATE dữ liệu (ví dụ: thay đổi ngân sách khuyến mãi), thông tin cũ sẽ bị mất.
Task này dạy bạn cách lưu lịch sử thay đổi (audit trail) để sau này có thể xem lại hoặc khôi phục.

### Bước 1 — Tạo History Table (Bảng Lịch Sử)

🎯 **Mục đích:** Tạo một bảng riêng chỉ để lưu trạng thái CŨ trước mỗi lần UPDATE.

```sql
CREATE TABLE IF NOT EXISTS linh_lab.promotion_program_history (
    history_id    BIGSERIAL     PRIMARY KEY,
    program_id    BIGINT        NOT NULL,
    old_program_name VARCHAR(200),
    old_budget_limit NUMERIC(18,2),
    old_start_at  TIMESTAMP,
    old_end_at    TIMESTAMP,
    old_status_id BIGINT,
    changed_at    TIMESTAMP     NOT NULL DEFAULT NOW(),
    changed_by    VARCHAR(100)  NOT NULL DEFAULT CURRENT_USER,
    change_type   VARCHAR(20)   NOT NULL DEFAULT 'UPDATE',

    CONSTRAINT fk_history_program
        FOREIGN KEY (program_id)
        REFERENCES linh_lab.promotion_program(program_id)
);

-- Index tăng tốc truy vấn audit theo program_id
CREATE INDEX IF NOT EXISTS idx_history_program
    ON linh_lab.promotion_program_history(program_id, changed_at DESC);
```

**Tại sao cần bảng riêng?**
- Bảng gốc (`promotion_program`) chỉ giữ dữ liệu **hiện tại**
- Bảng history giữ **tất cả phiên bản cũ** → như "sổ nhật ký" của bảng

---

### Bước 2 — Tạo Trigger Function (Hàm tự động)

🎯 **Mục đích:** Viết hàm tự động chạy mỗi khi có UPDATE trên bảng gốc.

```sql
CREATE OR REPLACE FUNCTION linh_lab.fn_audit_promotion_program()
RETURNS TRIGGER AS $$
BEGIN
    -- Chỉ ghi audit khi có thay đổi thực sự
    IF OLD.program_name   IS DISTINCT FROM NEW.program_name
    OR OLD.budget_limit   IS DISTINCT FROM NEW.budget_limit
    OR OLD.start_at       IS DISTINCT FROM NEW.start_at
    OR OLD.end_at         IS DISTINCT FROM NEW.end_at
    OR OLD.status_id      IS DISTINCT FROM NEW.status_id
    THEN
        INSERT INTO linh_lab.promotion_program_history (
            program_id,
            old_program_name,
            old_budget_limit,
            old_start_at,
            old_end_at,
            old_status_id,
            changed_by
        )
        VALUES (
            OLD.program_id,
            OLD.program_name,
            OLD.budget_limit,
            OLD.start_at,
            OLD.end_at,
            OLD.status_id,
            COALESCE(NEW.updated_by, CURRENT_USER)
        );
    END IF;

    -- RETURN NEW cho phép UPDATE tiếp tục thực thi bình thường
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Giải thích biến `OLD` và `NEW`:**
- `OLD`: Chứa toàn bộ dữ liệu **cũ** trước khi UPDATE
- `NEW`: Chứa dữ liệu **mới** sau khi UPDATE
- Trigger lấy dữ liệu từ `OLD` để lưu vào history table.

**`IS DISTINCT FROM` là gì?**
- Kiểm tra "có thay đổi thật sự không"
- Nếu ai đó UPDATE nhưng không đổi giá trị gì → Trigger sẽ bỏ qua, không tạo bản ghi rác.

> **Tóm tắt dễ nhớ:**
> - Tạo bảng lịch sử riêng để lưu dữ liệu cũ
> - Viết trigger tự động chạy khi UPDATE → copy dữ liệu cũ sang bảng history
> - Nhờ vậy, bạn luôn biết **trước update là gì**, **sau update là gì**, và **ai thay đổi**
>
> Đây là kỹ thuật **Audit Trail** cơ bản trong database.

---

### Bước 3 — Gắn Trigger vào Bảng (Attach Trigger)

🎯 **Mục đích:** Kết nối hàm `fn_audit_promotion_program()` ở Bước 2 vào bảng `promotion_program`. Dùng `AFTER UPDATE` (không phải `BEFORE UPDATE`) vì ta chỉ muốn ghi audit khi UPDATE **thực sự thành công** — nếu UPDATE bị rollback thì trigger AFTER sẽ KHÔNG chạy → history table không bị "rác".

```sql
-- Xóa trigger cũ nếu tồn tại (idempotent)
DROP TRIGGER IF EXISTS trg_audit_promotion_program
    ON linh_lab.promotion_program;

CREATE TRIGGER trg_audit_promotion_program
    AFTER UPDATE ON linh_lab.promotion_program
    FOR EACH ROW
    EXECUTE FUNCTION linh_lab.fn_audit_promotion_program();
```

**Tại sao AFTER chứ không phải BEFORE?**

| Loại Trigger | Thời điểm chạy | Rủi ro |
|---|---|---|
| `BEFORE UPDATE` | Chạy **TRƯỚC** khi UPDATE hoàn tất | Nếu UPDATE bị rollback → history vẫn ghi → **phantom records** |
| `AFTER UPDATE` ✅ | Chạy **SAU** khi UPDATE thành công | Chỉ ghi khi thay đổi ĐÃ COMMIT → **audit chính xác** |

---

### Bước 4 — Kiểm Thử Hệ Thống Kiểm Toán

#### 4A — Kiểm tra trạng thái hiện tại

🎯 **Mục đích:** Ghi nhận giá trị gốc của `budget_limit` TRƯỚC KHI thay đổi, để so sánh với audit log sau.

```sql
SELECT program_id, program_name, budget_limit, status_id
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
```

> **Kết quả mong đợi:** Ghi nhớ `budget_limit` hiện tại (ví dụ: `50,000,000`).

---

#### 4B — Mô phỏng "nhân viên gian lận" thay đổi ngân sách

🎯 **Mục đích:** Giả lập tình huống nhân viên thay đổi `budget_limit` bất thường. Trigger `trg_audit_promotion_program` sẽ **tự động** lưu giá trị CŨ vào `promotion_program_history` — không cần code ứng dụng can thiệp.

```sql
UPDATE linh_lab.promotion_program
SET    budget_limit = 999000000,
       updated_at   = NOW(),
       updated_by   = 'ROGUE_EMPLOYEE'
WHERE  program_id = 1;
```

> **Kết quả:** `UPDATE 1` — Trigger đã âm thầm chạy, lưu giá trị CŨ (`50,000,000`) vào history table.

---

#### 4C — Kiểm tra Audit Log (Sổ Nhật Ký Kiểm Toán)

🎯 **Mục đích:** Xác minh trigger đã bắt giữ đúng giá trị CŨ. Đây là **bằng chứng kiểm toán** (audit evidence) — biết AI đã thay đổi, KHI NÀO, và giá trị CŨ là gì.

```sql
SELECT history_id,
       program_id,
       old_program_name,
       old_budget_limit,
       changed_at,
       changed_by,
       change_type
FROM   linh_lab.promotion_program_history
WHERE  program_id = 1
ORDER BY changed_at DESC;
```

> **Kết quả mong đợi:** 1 dòng mới xuất hiện:
>
> | history_id | program_id | old_budget_limit | changed_by | change_type |
> |---|---|---|---|---|
> | 1 | 1 | 50,000,000.00 | ROGUE_EMPLOYEE | UPDATE |
>
> ✅ Giá trị CŨ (`50,000,000`) đã được bảo toàn! Dù bảng gốc hiện tại hiển thị `999,000,000`, ta vẫn có bằng chứng kiểm toán đầy đủ.

---

#### 4D — Phục hồi dữ liệu gốc từ History Table (Rollback thủ công)

🎯 **Mục đích:** Chứng minh history table không chỉ để "nhìn" mà còn để **"sửa"** — dùng giá trị CŨ trong audit log để phục hồi dữ liệu gốc. Đây là kịch bản thực tế khi phát hiện gian lận.

```sql
UPDATE linh_lab.promotion_program pp
SET    budget_limit = h.old_budget_limit,
       updated_at   = NOW(),
       updated_by   = 'ADMIN_ROLLBACK'
FROM   linh_lab.promotion_program_history h
WHERE  pp.program_id = h.program_id
  AND  h.program_id  = 1
  AND  h.history_id  = (
           SELECT MAX(history_id)
           FROM   linh_lab.promotion_program_history
           WHERE  program_id = 1
       );
```

**Kiểm chứng:**
```sql
SELECT program_id, program_name, budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
```

> **Kết quả:** `budget_limit` đã quay về giá trị gốc (`50,000,000`). Và history table giờ có **2 dòng** — ghi nhận cả lần gian lận lẫn lần phục hồi!

---

## 📊 Tổng Kết: So Sánh Các Phương Pháp CDC

| Phương pháp | Ưu điểm | Nhược điểm | Phù hợp cho |
|---|---|---|---|
| **Cột `updated_at`** (Bài 3) | Đơn giản, nhanh | Mất giá trị cũ | Tracking "khi nào" thay đổi |
| **Trigger + History Table** (Bài 6) ✅ | Lưu đầy đủ OLD values, native PostgreSQL | Ảnh hưởng hiệu năng khi scale | Hệ thống nhỏ-vừa, audit tài chính |
| **WAL-based CDC** (Debezium) | Không ảnh hưởng OLTP, real-time streaming | Cần hạ tầng Kafka phức tạp | Production-grade, hệ thống lớn |

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

### Câu hỏi 1:
> "Tại sao ta dùng `AFTER UPDATE` trigger cho auditing, thay vì `BEFORE UPDATE` trigger?"

**Trả lời:**

`AFTER UPDATE` chỉ chạy **KHI UPDATE ĐÃ THÀNH CÔNG**:
- Nếu UPDATE bị lỗi (vi phạm constraint, deadlock, rollback) → trigger AFTER **KHÔNG chạy** → history table không bị "rác"
- `BEFORE UPDATE` chạy **TRƯỚC** khi UPDATE hoàn tất → nếu UPDATE bị rollback, dòng audit vẫn đã được ghi → **phantom records** (ghi nhận thay đổi chưa bao giờ xảy ra)

> Trong kiểm toán tài chính, chỉ ghi nhận thay đổi **ĐÃ COMMIT** mới có giá trị pháp lý.

---

### Câu hỏi 2:
> "Nếu `promotion_program` được UPDATE 10.000 lần/ngày, history table sẽ phình to rất nhanh. Trong thực tế, Data Engineer xử lý vấn đề này như thế nào?"

**Trả lời:**

| Chiến lược | Mô tả |
|---|---|
| **Table Partitioning** | Chia history theo tháng/quý bằng Range Partition trên `changed_at`. Xóa dữ liệu cũ = DROP PARTITION (nhanh hơn DELETE triệu dòng) |
| **Archive to Data Lake** | Scheduled job export history > 90 ngày sang Parquet/ORC trên S3/GCS. OLTP chỉ giữ 90 ngày gần nhất |
| **WAL-based CDC** (Debezium) | Thay trigger bằng đọc Write-Ahead Log → stream sang Kafka → không ảnh hưởng hiệu năng OLTP |
| **Retention Policy** | Scheduled job xóa records quá hạn: `DELETE FROM history WHERE changed_at < NOW() - INTERVAL '1 year'` |

> **Tóm lại:** Trigger-based CDC phù hợp hệ thống nhỏ-vừa. Khi scale lên → chuyển sang WAL-based CDC (Debezium) + Data Lake archival.

---

## 📦 File Deliverable

Sản phẩm của bài tập được lưu trữ tại:
```
tasks/task_06_data_auditing_cdc/data_auditing_cdc.sql
```
