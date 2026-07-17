# 📝 Task 11 — Indexing & Table Partitioning cho Bảng Dữ liệu Lớn

## Kiến thức đạt được

> Đây là những gì cần **ghi nhớ và mang theo áp dụng cho các dự án sau** — không phải bản tóm tắt việc đã làm trong task này.

| Nội dung chính | Ghi nhớ & áp dụng cho dự án sau |
|---|---|
| **Không tạo Index vì cảm giác — luôn cần bằng chứng** | Trước khi gõ `CREATE INDEX`, phải trả lời được: query nào chậm, chậm bao nhiêu, được gọi thường xuyên tới đâu, và selectivity của điều kiện lọc có đủ thấp để đáng dùng Index không. |
| **Đúng dữ liệu chưa đủ — phải nhanh khi bảng lớn** | Constraints/Locking/Isolation/RLS (Task 03/04/08/09) bảo vệ tính đúng đắn, nhưng không tự động giải quyết hiệu năng — bảng triệu dòng mà thiếu index/partition phù hợp thì mọi báo cáo chậm dần đều bất kể logic đúng tới đâu. |
| **Index tăng tốc bên trong bảng, Partition chia nhỏ vật lý** | Index (B-Tree/BRIN, đơn/đa cột, partial/covering) giúp tìm nhanh hơn *trong* 1 bảng; Partitioning chia *vật lý* bảng thành nhiều bảng con để Planner loại bỏ hẳn phần không liên quan (pruning). Hai kỹ thuật cộng hưởng — không phải chọn 1 trong 2. |
| **Chọn theo pattern truy vấn thật, không theo thói quen** | Partition key phải khớp điều kiện `WHERE` phổ biến nhất trong hệ thống thực tế; mỗi loại Index có chi phí ghi/kích thước khác nhau — luôn đo bằng `EXPLAIN ANALYZE` trên dữ liệu thật trước khi quyết định. |
| **Checklist rủi ro khi đưa lên production** | Luôn `VACUUM`/`ANALYZE` sau bulk insert; luôn `CREATE INDEX CONCURRENTLY` trên bảng có traffic ghi; định kỳ rà soát `pg_stat_user_indexes` để xóa index thừa. |
| **Dọn dữ liệu cũ bằng DETACH/DROP, không DELETE hàng loạt** | Với bảng log/audit/event tăng trưởng không giới hạn, thiết kế partition theo thời gian **ngay từ đầu** — dọn dữ liệu quá hạn sau này chỉ là 1 thao tác gần như tức thời. |
| **Đừng mang khái niệm RDBMS khác sang Postgres chưa kiểm chứng** | "Clustered Index" (SQL Server/InnoDB) không tồn tại trong Postgres — mọi index đều "Non-Clustered"; `CLUSTER` chỉ là one-time reorder, không tự duy trì. "Bitmap Index" (Oracle) cũng không phải 1 loại index trong Postgres — chỉ là chiến lược thực thi dựng động từ B-Tree. |

---

## 🎯 Nội dung học tập & Bài học rút ra (Key Learnings)

Các Task trước đã bảo vệ **tính đúng đắn** của dữ liệu (Constraints, Locking, Isolation) và **quy trình nghiệp vụ** (Procedure, Audit, RLS). Nhưng đúng dữ liệu thôi chưa đủ — nếu bảng `partner_click` tăng lên hàng triệu dòng sau vài tháng vận hành, các báo cáo ở Task 07 (`fn_partner_performance_report`, `sp_reconcile_partner_payout`) sẽ ngày càng chậm vì phải quét toàn bộ bảng mỗi lần chạy.

| Rủi ro nếu bỏ qua | Giải thích |
|---|---|
| **Quét toàn bảng mỗi lần đọc** | Không có Index phù hợp → mọi query lọc theo `partner_id`/`clicked_at` đều là Sequential Scan, thời gian tăng tuyến tính theo số dòng |
| **Bảng phình to không kiểm soát** | Không có Partition → không có cách nào dọn dữ liệu cũ ngoài `DELETE` hàng loạt (chậm, khóa nặng, tốn WAL) |
| **Tạo Index tùy tiện** | Mỗi Index tạo thêm đều làm chậm `INSERT`/`UPDATE`/`DELETE` — tạo thừa mà không đo lường trước gây hại nhiều hơn lợi |

Giải pháp: **Index** (tăng tốc tìm kiếm trong 1 bảng) kết hợp **Table Partitioning** (chia vật lý bảng lớn) — nhưng phải đi qua đúng quy trình ra quyết định, không phải cứ thấy chậm là thêm Index bừa.

Trong bài thực hành này, bạn sẽ học cách:
1. **Ra quyết định có nên tạo Index hay không** dựa trên bằng chứng (query hot, Cardinality, Selectivity) — không dựa trên cảm giác.
2. Thiết kế **Composite B-Tree Index** đúng thứ tự cột (Equality trước, Range sau) và hiểu quy tắc **Leftmost Prefix**.
3. Dùng **Partial Index**, **Covering Index (`INCLUDE`)**, **Functional Index**, và **BRIN** cho từng use-case cụ thể.
4. Nhận biết **chi phí ẩn của Index** và cách phát hiện index thừa bằng `pg_stat_user_indexes`.
5. Tạo Index an toàn trên production bằng `CREATE INDEX CONCURRENTLY`.
6. Hiểu **bản chất lưu trữ** của Index: phân biệt **Clustered vs Non-Clustered Index** (và vì sao PostgreSQL không có Clustered Index thật sự, chỉ có lệnh `CLUSTER`), thực hành **Hash Index** (chỉ hỗ trợ `=`), và làm rõ **Bitmap Scan** không phải một loại index được lưu trữ mà là chiến lược thực thi động.
7. **Table Partitioning** theo `RANGE`/`LIST`/`HASH` — tận dụng **Partition Pruning** để tăng tốc truy vấn, và `ATTACH`/`DETACH PARTITION` để quản lý dữ liệu theo lô gần như tức thời.

---

## 🗂️ Các bảng Cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Vai trò trong bài | Ghi chú |
|---|---|---|
| `linh_lab.partner_click` | Bảng thật (Task 05/06/07) — dùng để khảo sát hiện trạng index ở Bước 1 | Không bị chỉnh sửa |
| `linh_lab.partner_click_bench` *(mới)* | Bảng benchmark 300.000 dòng — dùng xuyên suốt phần Index | Tạo riêng, không ảnh hưởng Task khác |
| `linh_lab.partner_click_seq` *(mới)* | Bản sao dữ liệu `ORDER BY clicked_at` — mô phỏng log ghi tăng dần theo thời gian | Dùng riêng cho BRIN |
| `linh_lab.partner_click_events` *(mới)* | Bảng partition theo `RANGE(clicked_at)` | Dùng cho phần Partitioning |
| `linh_lab.partner_click_by_partner` *(mới)* | Bảng partition theo `LIST(partner_id)` | So sánh với RANGE |
| `linh_lab.partner_click_hash` *(mới)* | Bảng partition theo `HASH(click_id)` | So sánh với RANGE/LIST |

> **Vì sao không thực hành trực tiếp trên `partner_click`?** Bảng thật chỉ có 5 dòng seed (không đủ để đo hiệu năng), và việc chuyển 1 bảng đã tồn tại sang partition đòi hỏi tạo lại cấu trúc (native partitioning không hỗ trợ `ALTER TABLE` biến bảng thường thành partitioned). Tạo bảng benchmark riêng an toàn hơn và không ảnh hưởng các Task khác.

---

## 🔑 Ngữ cảnh (Context)

Sau vài tháng vận hành, `partner_click` đã tăng lên hàng triệu dòng. Đội Data Analyst báo cáo rằng `fn_partner_performance_report` (Task 07) — vốn luôn lọc theo `partner_id` và khoảng ngày — ngày càng chậm. Khi kiểm tra, `partner_click` **không có bất kỳ index nào** ngoài Primary Key trên `click_id` — mọi truy vấn lọc theo `partner_id`/`clicked_at` đều phải Sequential Scan.

Task 06 cũng để lại câu hỏi mở: *"Nếu `promotion_program_history` được UPDATE 10.000 lần/ngày, bảng sẽ phình to rất nhanh — xử lý thế nào?"* — câu trả lời chính là **Table Partitioning**, được hiện thực hóa đầy đủ ở phần cuối bài này.

---

## 📖 Khái Niệm Cốt Lõi: Index vs Partition

| Tiêu chí | Index | Partition |
|---|---|---|
| **Tác động vật lý** | Cấu trúc phụ song song với bảng, không chia bảng | Chia bảng thành nhiều bảng con vật lý riêng biệt |
| **Giải quyết vấn đề** | Tìm kiếm chậm *bên trong* 1 bảng | Bảng quá lớn, cần dọn dữ liệu cũ theo lô |
| **Chi phí đánh đổi** | Ghi chậm hơn, tốn thêm dung lượng đĩa | Phức tạp hơn khi thiết kế, cần chọn đúng partition key |
| **Dùng cùng lúc được không?** | ✅ Có — Index tạo trên bảng cha tự lan truyền xuống mọi partition con | ✅ Đây là kiến trúc chuẩn cho bảng log/audit khổng lồ |

> **Tóm lại:** Index trả lời câu hỏi "tìm nhanh hơn trong 1 bảng bằng cách nào?". Partition trả lời câu hỏi "bảng này lớn tới mức nào và cần dọn dẹp ra sao?". Đây là 2 công cụ bổ trợ, không thay thế nhau.

### Bản chất lưu trữ: Clustered vs Non-Clustered, và các "loại Index" hay bị hiểu nhầm

| Khái niệm | Có tồn tại trong PostgreSQL không? | Bản chất thật |
|---|---|---|
| **Clustered Index** (SQL Server/InnoDB) | ❌ Không | Postgres không có — mọi index đều Non-Clustered (Heap tách biệt B-Tree). Gần nhất là lệnh `CLUSTER` (one-time, không tự duy trì) |
| **Non-Clustered Index** | ✅ Có — là loại **duy nhất** | Mọi B-Tree/Hash/GIN/GiST/BRIN Index trong Postgres đều thuộc loại này |
| **Hash Index** | ✅ Có, thật sự tồn tại | Chỉ hỗ trợ `=`; an toàn dùng từ PostgreSQL 10 (WAL-logged), nhưng hiếm khi tốt hơn B-Tree |
| **Bitmap Index** (Oracle) | ❌ Không phải 1 loại index lưu trữ | "Bitmap Index/Heap Scan" trong Postgres chỉ là **chiến lược thực thi** dựng động từ B-Tree lúc chạy query, không phải `CREATE INDEX` riêng |

> ⚠️ Đây là nhóm khái niệm dễ trả lời sai nhất khi phỏng vấn nếu từng làm quen với SQL Server/MySQL/Oracle trước đó — thực hành kỹ ở Bước 8-10 bên dưới.

---

## 🔬 Chi tiết các Bước Thực hành

### Bước 1 — Quyết định có tạo Index hay không

🎯 **Mục đích:** Trước khi viết bất kỳ `CREATE INDEX` nào, phải xác nhận bằng chứng cụ thể: bảng thật `partner_click` hiện không có index hỗ trợ, nhưng có đủ lớn để đáng tối ưu không?

```sql
-- Nếu có bật pg_stat_statements — nguồn bằng chứng đáng tin cậy nhất để tìm
-- query đang tốn tài nguyên hệ thống nhất:
-- SELECT query, calls, total_exec_time, mean_exec_time, rows
-- FROM   pg_stat_statements
-- ORDER BY total_exec_time DESC
-- LIMIT 10;

-- Khảo sát hiện trạng Index của bảng thật:
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'linh_lab'
  AND  tablename   = 'partner_click';

-- Đo baseline ngay trên bảng thật:
EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click WHERE partner_id = 1;
```

> **Kết quả mong đợi:** `pg_indexes` chỉ trả về 1 dòng — `partner_click_pkey` (PK trên `click_id`). `EXPLAIN ANALYZE` cho thấy `Seq Scan` nhưng execution time gần 0ms — vì bảng thật chỉ có 5 dòng seed.

**Điều đó nghĩa là:** Quyết định "có nên tạo Index" luôn phụ thuộc vào **quy mô dữ liệu thật**, không phải "bảng này có vẻ quan trọng". Vì bảng thật quá nhỏ để ra quyết định có ý nghĩa, Bước 2 sẽ tạo 1 bảng benchmark 300.000 dòng mô phỏng đúng kịch bản "`partner_click` sau vài tháng vận hành".

---

### Bước 2 — Chuẩn bị dữ liệu benchmark

🎯 **Mục đích:** Tạo `partner_click_bench` với 300.000 dòng đủ lớn để các quyết định Index tiếp theo có ý nghĩa đo lường thật.

```sql
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_bench (
    click_id                  BIGSERIAL PRIMARY KEY,
    partner_id                BIGINT      NOT NULL,
    clicked_at                TIMESTAMP   NOT NULL,
    is_suspicious             BOOLEAN     NOT NULL DEFAULT FALSE,
    reconciliation_status_id  BIGINT
);

-- partner_id ngẫu nhiên 1-5, clicked_at trải đều 6 tháng, ~10% is_suspicious=TRUE,
-- ~30% đã đối soát (reconciliation_status_id = 1):
INSERT INTO linh_lab.partner_click_bench (partner_id, clicked_at, is_suspicious, reconciliation_status_id)
SELECT
    1 + floor(random() * 5)::BIGINT,
    TIMESTAMP '2026-01-01' + (random() * INTERVAL '181 days'),
    (random() < 0.1),
    CASE WHEN random() < 0.3 THEN 1 ELSE NULL END
FROM generate_series(1, 300000);

SELECT COUNT(*) AS total_rows FROM linh_lab.partner_click_bench;
SELECT pg_size_pretty(pg_total_relation_size('linh_lab.partner_click_bench')) AS table_size;
```

> **Kết quả mong đợi:** `total_rows = 300000`; `table_size` vài chục MB.

**Điều đó nghĩa là:** Đừng bao giờ đo hiệu năng Index trên bảng nhỏ — mọi chiến lược quét đều "nhanh như nhau" ở quy mô nhỏ, che giấu mất khác biệt thật.

---

### Bước 3 — Đo Cardinality, Selectivity, `pg_stats` & `ANALYZE`

🎯 **Mục đích:** Trước khi biết cột nào đáng Index, phải đo được 2 con số quyết định: **Cardinality** (số giá trị khác nhau) và **Selectivity** (tỷ lệ dòng khớp điều kiện).

```sql
-- Cardinality thủ công:
SELECT
    COUNT(DISTINCT partner_id)               AS cardinality_partner_id,
    COUNT(DISTINCT is_suspicious)            AS cardinality_is_suspicious,
    COUNT(DISTINCT reconciliation_status_id) AS cardinality_reconciliation_status,
    COUNT(DISTINCT click_id)                 AS cardinality_click_id,
    COUNT(*)                                 AS total_rows
FROM linh_lab.partner_click_bench;

-- Selectivity thủ công của 3 điều kiện tiêu biểu:
SELECT
    ROUND((SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE partner_id = 3)::NUMERIC
        / (SELECT COUNT(*) FROM linh_lab.partner_click_bench), 4) AS selectivity_partner_3,
    ROUND((SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE is_suspicious = TRUE)::NUMERIC
        / (SELECT COUNT(*) FROM linh_lab.partner_click_bench), 4) AS selectivity_suspicious_true,
    ROUND((SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE click_id = 12345)::NUMERIC
        / (SELECT COUNT(*) FROM linh_lab.partner_click_bench), 8) AS selectivity_single_pk;
```

> **Kết quả mong đợi:** `cardinality_partner_id=5`; `selectivity_partner_3` ~0.20; `selectivity_suspicious_true` ~0.10; `selectivity_single_pk` ~0.0000033 — càng gần 0, càng đáng tạo Index.

```sql
-- pg_stats TRƯỚC khi ANALYZE (Planner đang "mù"):
SELECT attname, null_frac, n_distinct, most_common_vals, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_bench'
ORDER BY attname;

EXPLAIN SELECT * FROM linh_lab.partner_click_bench WHERE partner_id = 3;

-- Chạy ANALYZE — biến Planner từ "đoán mù" thành "ước lượng có căn cứ":
ANALYZE linh_lab.partner_click_bench;

SELECT attname, null_frac, n_distinct, most_common_vals, most_common_freqs, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_bench'
ORDER BY attname;

EXPLAIN SELECT * FROM linh_lab.partner_click_bench WHERE partner_id = 3;
```

> **Kết quả mong đợi:** Trước `ANALYZE`: `pg_stats` trống/thiếu, `rows=` trong `EXPLAIN` lệch xa so với ~60.000 thật. Sau `ANALYZE`: `pg_stats` đầy đủ, `rows=` giờ rất gần 60.000.

```sql
-- Kiểm chứng UNIQUE Index có thực sự kiểm tra dữ liệu:
CREATE UNIQUE INDEX idx_test_unique_partner ON linh_lab.partner_click_bench (partner_id);
-- Kết quả mong đợi: ERROR "could not create unique index ... is duplicated"

-- Kiểm chứng Index có index cả giá trị NULL không:
CREATE INDEX idx_pcb_recon_test ON linh_lab.partner_click_bench (reconciliation_status_id);
EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE reconciliation_status_id IS NULL;
DROP INDEX linh_lab.idx_pcb_recon_test;
```

**Điều đó nghĩa là:** `ANALYZE` là nguồn dữ liệu **duy nhất** để Planner ước lượng đúng — luôn chạy ngay sau bulk load. `UNIQUE` là ràng buộc được thực thi thật (quét dữ liệu), không phải chỉ là cái tên. B-Tree Index của PostgreSQL index cả `NULL`.

---

### Bước 4 — Composite Index & Quy tắc Leftmost Prefix

🎯 **Mục đích:** Áp dụng đúng số liệu đo ở Bước 3 để ra quyết định tạo Index — đặt cột lọc `=` trước cột lọc `range` — rồi hiểu giới hạn của nó.

```sql
-- TRƯỚC khi tạo Index:
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id  = 3
  AND  clicked_at  >= '2026-03-01'
  AND  clicked_at  <  '2026-04-01';

-- QUYẾT ĐỊNH: selectivity thấp + bảng lớn + 2 cột cùng WHERE
-- → Composite Index, equality (partner_id) trước, range (clicked_at) sau:
CREATE INDEX IF NOT EXISTS idx_pcb_partner_date
    ON linh_lab.partner_click_bench (partner_id, clicked_at);

-- SAU khi tạo Index — chạy lại đúng câu query trên:
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id  = 3
  AND  clicked_at  >= '2026-03-01'
  AND  clicked_at  <  '2026-04-01';
```

> **Kết quả mong đợi:** Trước: `Seq Scan`. Sau: `Index Scan`/`Bitmap Heap Scan using idx_pcb_partner_date`, execution time giảm rõ rệt.

```sql
-- Kiểm chứng Leftmost Prefix — bỏ cột dẫn đầu partner_id:
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  clicked_at >= '2026-03-01'
  AND  clicked_at <  '2026-04-01';
```

> **Kết quả mong đợi:** Planner quay lại `Seq Scan`! Index `(partner_id, clicked_at)` vô dụng khi bỏ qua cột dẫn đầu.

**Điều đó nghĩa là:** Index đa cột `(A, B)` chỉ hữu dụng cho truy vấn lọc theo `A`, hoặc `(A, B)` — không hữu dụng nếu chỉ lọc theo `B`. Quy trình đúng luôn là ĐO TRƯỚC → QUYẾT ĐỊNH có căn cứ → TẠO → ĐO LẠI để xác nhận.

---

### Bước 5 — Partial Index & Chi phí của Index

🎯 **Mục đích:** Tối ưu đúng tập con dữ liệu nghiệp vụ cần (`sp_reconcile_partner_payout` — Task 07 — luôn lọc `is_suspicious=FALSE AND reconciliation_status_id IS NULL`), đồng thời hiểu cái giá phải trả của mỗi Index.

```sql
CREATE INDEX IF NOT EXISTS idx_pcb_unreconciled
    ON linh_lab.partner_click_bench (partner_id, clicked_at)
    WHERE is_suspicious = FALSE AND reconciliation_status_id IS NULL;

SELECT
    pg_size_pretty(pg_relation_size('linh_lab.idx_pcb_partner_date'))  AS full_index_size,
    pg_size_pretty(pg_relation_size('linh_lab.idx_pcb_unreconciled')) AS partial_index_size;

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id               = 3
  AND  is_suspicious             = FALSE
  AND  reconciliation_status_id  IS NULL
  AND  clicked_at >= '2026-03-01'
  AND  clicked_at <  '2026-04-01';
```

> **Kết quả mong đợi:** `partial_index_size` nhỏ hơn `full_index_size` rõ rệt. Planner chọn `idx_pcb_unreconciled` (partial, nhỏ hơn) vì cost thấp hơn.

```sql
-- Chi phí Index: tạo 1 index thừa rồi phát hiện qua pg_stat_user_indexes
CREATE INDEX IF NOT EXISTS idx_pcb_partner_only
    ON linh_lab.partner_click_bench (partner_id);

SELECT pg_sleep(1);  -- chờ stats collector flush

SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM   pg_stat_user_indexes
WHERE  schemaname = 'linh_lab' AND relname = 'partner_click_bench'
ORDER BY idx_scan DESC;

DROP INDEX IF EXISTS linh_lab.idx_pcb_partner_only;
```

> **Kết quả mong đợi:** `idx_pcb_partner_only` có `idx_scan = 0` — INDEX THỪA vì `idx_pcb_partner_date` (cùng cột dẫn đầu) đã bao trùm.

**Điều đó nghĩa là:** Index không cần phủ toàn bộ bảng. Và Index không miễn phí — production thật cần định kỳ rà soát `pg_stat_user_indexes` để xóa index không dùng.

---

### Bước 6 — Covering Index, Functional Index & Top-N Query

🎯 **Mục đích:** 3 kỹ thuật nâng cao giải quyết 3 tình huống thực tế khác nhau: `SELECT` cần thêm cột (Covering), lọc/gom nhóm theo biểu thức (Functional), và truy vấn "N bản ghi gần nhất" (Top-N).

```sql
-- Covering Index (INCLUDE) — tránh Heap Fetch khi SELECT thêm cột:
CREATE INDEX IF NOT EXISTS idx_pcb_partner_date_covering
    ON linh_lab.partner_click_bench (partner_id, clicked_at)
    INCLUDE (is_suspicious);

EXPLAIN (ANALYZE, BUFFERS)
SELECT partner_id, clicked_at, is_suspicious
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3 AND clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi (trước VACUUM): Index Only Scan nhưng Heap Fetches vẫn CAO.

VACUUM ANALYZE linh_lab.partner_click_bench;

EXPLAIN (ANALYZE, BUFFERS)
SELECT partner_id, clicked_at, is_suspicious
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3 AND clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi (sau VACUUM): Heap Fetches: 0.
```

```sql
-- Functional Index — hỗ trợ GROUP BY theo ngày:
CREATE INDEX IF NOT EXISTS idx_pcb_partner_day
    ON linh_lab.partner_click_bench (partner_id, date_trunc('day', clicked_at));

EXPLAIN ANALYZE
SELECT date_trunc('day', clicked_at) AS report_day, COUNT(*) AS clicks
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3
GROUP BY date_trunc('day', clicked_at)
ORDER BY report_day;
-- Kết quả mong đợi: plan bỏ được node Sort riêng.
```

```sql
-- Top-N: ORDER BY DESC + LIMIT dùng được index ASC theo chiều ngược:
EXPLAIN ANALYZE
SELECT click_id, clicked_at
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3
ORDER BY clicked_at DESC
LIMIT 10;
-- Kết quả mong đợi: "Index Scan Backward" — không có node Sort riêng.
```

| Kỹ thuật | Vấn đề giải quyết |
|---|---|
| `INCLUDE (col)` | Tránh Heap Fetch khi `SELECT` cột ngoài điều kiện lọc — cần cả Index đủ cột lẫn `VACUUM` để đạt Index-Only Scan thật sự |
| Index trên biểu thức | `WHERE`/`GROUP BY` theo `date_trunc(...)`, `LOWER(...)` không dùng được index cột gốc — phải index đúng biểu thức |
| B-Tree quét 2 chiều | 1 index ASC đã đủ phục vụ cả `ORDER BY ASC` lẫn `DESC` — không cần tạo thêm index riêng |

---

### Bước 7 — BRIN Index & `CREATE INDEX CONCURRENTLY`

🎯 **Mục đích:** BRIN cho dữ liệu tương quan vật lý cao (log append-only); `CONCURRENTLY` để tạo Index an toàn trên bảng production đang có traffic ghi.

```sql
-- Tạo bảng mô phỏng log ghi tăng dần theo thời gian (tương quan vật lý cao):
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_seq AS
SELECT click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id
FROM   linh_lab.partner_click_bench
ORDER BY clicked_at;

ANALYZE linh_lab.partner_click_seq;

SELECT attname, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_seq' AND attname = 'clicked_at';
-- Kết quả mong đợi: correlation ~ 1.0

CREATE INDEX IF NOT EXISTS idx_seq_btree ON linh_lab.partner_click_seq (clicked_at);
CREATE INDEX IF NOT EXISTS idx_seq_brin  ON linh_lab.partner_click_seq USING BRIN (clicked_at);

SELECT
    pg_size_pretty(pg_relation_size('linh_lab.idx_seq_btree')) AS btree_size,
    pg_size_pretty(pg_relation_size('linh_lab.idx_seq_brin'))  AS brin_size;
-- Kết quả mong đợi: BRIN nhỏ hơn B-Tree hàng trăm lần.

DROP INDEX IF EXISTS linh_lab.idx_seq_btree;  -- buộc Planner dùng BRIN

EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click_seq
WHERE clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi: Bitmap Heap Scan + Recheck Cond + Bitmap Index Scan using idx_seq_brin.
```

```sql
-- ⚠️ Chạy riêng lẻ, KHÔNG trong transaction block:
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pcb_suspicious_concurrent
    ON linh_lab.partner_click_bench (is_suspicious);

SELECT indexrelid::regclass AS index_name, indisvalid
FROM   pg_index
WHERE  indexrelid = 'linh_lab.idx_pcb_suspicious_concurrent'::regclass;
-- Kết quả mong đợi: indisvalid = true.

DROP INDEX CONCURRENTLY IF EXISTS linh_lab.idx_pcb_suspicious_concurrent;
```

**Điều đó nghĩa là:** BRIN đánh đổi độ chính xác lấy kích thước cực nhỏ — chỉ đáng dùng khi cột tương quan vật lý cao. `CONCURRENTLY` chậm hơn ~2-3 lần so với `CREATE INDEX` thường, đổi lại không khóa ghi — luôn đáng đánh đổi trên production có traffic.

---

### Bước 8 — Clustered vs Non-Clustered Index (lệnh `CLUSTER`)

🎯 **Mục đích:** Đây là một trong những khái niệm hay bị hiểu nhầm nhất khi chuyển từ SQL Server/MySQL sang PostgreSQL. SQL Server/InnoDB có "Clustered Index" — dữ liệu bảng được lưu vật lý **theo đúng thứ tự của index đó** (leaf node của index *chính là* dòng dữ liệu), mỗi bảng chỉ có 1 (thường là PK). PostgreSQL **không có khái niệm này** — mọi index của Postgres đều là "Non-Clustered": Heap (nơi lưu dữ liệu thật) luôn tách biệt vật lý khỏi B-Tree Index, hai bên chỉ liên kết qua TID.

```sql
-- Tạo 1 index đơn cột trên clicked_at riêng cho thí nghiệm này:
CREATE INDEX IF NOT EXISTS idx_pcb_clustered_demo
    ON linh_lab.partner_click_bench (clicked_at);

-- Kiểm tra correlation TRƯỚC khi CLUSTER (dữ liệu insert ngẫu nhiên ở Bước 2):
SELECT attname, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_bench' AND attname = 'clicked_at';

-- CLUSTER: vật lý sắp xếp lại TOÀN BỘ Heap theo đúng thứ tự của index chỉ định.
-- ⚠️ Giữ khóa ACCESS EXCLUSIVE (chặn cả đọc lẫn ghi) trong suốt quá trình.
CLUSTER linh_lab.partner_click_bench USING idx_pcb_clustered_demo;

ANALYZE linh_lab.partner_click_bench;

SELECT attname, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_bench' AND attname = 'clicked_at';

DROP INDEX linh_lab.idx_pcb_clustered_demo;  -- dọn dẹp index chỉ dùng để minh họa
```

> **Kết quả mong đợi:** Correlation trước `CLUSTER` gần 0 (thứ tự vật lý không liên quan gì tới giá trị `clicked_at`). Sau `CLUSTER` + `ANALYZE`: correlation ~1.0 — Heap đã được viết lại vật lý theo đúng thứ tự index, y hệt hiệu ứng "Clustered Index" ở SQL Server/InnoDB.

| Tiêu chí | Clustered Index (SQL Server/InnoDB) | PostgreSQL |
|---|---|---|
| Dữ liệu bảng có nằm trong index không? | Có — leaf node của index CHÍNH LÀ dòng dữ liệu | Không — Heap luôn tách biệt, index chỉ lưu TID trỏ tới |
| Số lượng trên 1 bảng | Tối đa 1 (thường là PK) | Không áp dụng — khái niệm này không tồn tại |
| Duy trì thứ tự vật lý | Tự động, mọi lúc, với mọi INSERT | Chỉ tại thời điểm chạy `CLUSTER` — **không** tự duy trì sau đó |
| Chi phí duy trì | Trả liên tục qua từng lần ghi (ghi vào đúng vị trí sắp xếp) | Trả 1 lần khi chạy `CLUSTER` (khóa `ACCESS EXCLUSIVE` toàn bảng) |

**Điều đó nghĩa là:** Đừng mang nguyên khái niệm "Clustered Index" từ SQL Server/MySQL sang PostgreSQL mà không kiểm chứng lại — trong Postgres, thứ gần nhất là lệnh `CLUSTER`, nhưng nó là thao tác **một lần**, cần chạy lại định kỳ (trong cửa sổ bảo trì) nếu muốn giữ lợi ích, vì mọi `INSERT` sau đó vẫn ghi vào cuối Heap như bình thường.

---

### Bước 9 — Hash Index

🎯 **Mục đích:** Hash Index chỉ hỗ trợ toán tử `=` (không hỗ trợ range/sort). Từ PostgreSQL 10 đã an toàn để dùng (WAL-logged), nhưng B-Tree vẫn gần như luôn được chọn mặc định — thực hành để thấy rõ vì sao.

```sql
CREATE INDEX IF NOT EXISTS idx_pcb_partner_hash
    ON linh_lab.partner_click_bench USING HASH (partner_id);

-- B-Tree đơn cột CÙNG cột để so sánh công bằng:
CREATE INDEX IF NOT EXISTS idx_pcb_partner_btree_single
    ON linh_lab.partner_click_bench (partner_id);

SELECT
    pg_size_pretty(pg_relation_size('linh_lab.idx_pcb_partner_hash'))         AS hash_size,
    pg_size_pretty(pg_relation_size('linh_lab.idx_pcb_partner_btree_single')) AS btree_size;

EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE partner_id = 3;

-- Hash Index KHÔNG hỗ trợ điều kiện range:
EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE partner_id > 3;

DROP INDEX linh_lab.idx_pcb_partner_hash;
DROP INDEX linh_lab.idx_pcb_partner_btree_single;
```

> **Kết quả mong đợi:** Kích thước Hash và B-Tree khá gần nhau. Với `partner_id = 3`, Planner có thể chọn 1 trong 2. Với `partner_id > 3`, chỉ B-Tree (hoặc Seq Scan) xuất hiện trong plan — `idx_pcb_partner_hash` không bao giờ được dùng cho điều kiện range.

**Điều đó nghĩa là:** B-Tree phục vụ được `=`, `<`, `>`, `BETWEEN`, `ORDER BY` với chi phí tương đương Hash cho riêng equality — đây là lý do B-Tree gần như luôn được chọn mặc định. Hash Index chỉ đáng cân nhắc trong các trường hợp rất đặc thù, sau khi đã đo thực tế thấy nó nhanh hơn.

---

### Bước 10 — Bitmap Scan: Index Scan vs Bitmap Scan vs Seq Scan

🎯 **Mục đích:** Làm rõ một hiểu lầm phổ biến — **"Bitmap Index" trong PostgreSQL không phải một loại index được lưu trữ** (khác với Oracle, nơi Bitmap Index là 1 loại index thật). Trong Postgres, "Bitmap Index Scan"/"Bitmap Heap Scan" chỉ là **chiến lược thực thi** được Planner dựng động lúc chạy, từ index B-Tree đã có sẵn — không phải một `CREATE INDEX` riêng.

```sql
-- Selectivity RẤT THẤP → Index Scan thuần:
EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE click_id = 12345;

-- Selectivity VỪA PHẢI → Bitmap Heap Scan:
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id IN (1, 2)
  AND  clicked_at >= '2026-01-01' AND clicked_at < '2026-07-01';
```

> **Kết quả mong đợi:** Câu đầu — `Index Scan using partner_click_bench_pkey` (1 dòng khớp, tra thẳng qua Index). Câu sau — `Bitmap Heap Scan` + `Recheck Cond` + `Bitmap Index Scan` (nhiều dòng khớp vừa phải, đủ để Postgres xây "bản đồ" các block cần đọc trước khi đọc Heap theo đúng thứ tự vật lý).

```sql
-- Kết hợp BitmapAnd giữa 2 index KHÁC NHAU (không phải cùng 1 composite):
CREATE INDEX IF NOT EXISTS idx_pcb_suspicious_bmp
    ON linh_lab.partner_click_bench (is_suspicious);

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3 AND is_suspicious = TRUE;

DROP INDEX linh_lab.idx_pcb_suspicious_bmp;
```

> **Kết quả mong đợi:** Planner có thể dùng `BitmapAnd` để giao (AND) kết quả bitmap từ `idx_pcb_partner_date` và `idx_pcb_suspicious_bmp` lại với nhau trước khi đọc Heap — tận dụng được **cả hai** index cho 1 câu query, điều mà Index Scan thuần không làm được (chỉ dùng 1 index tại 1 thời điểm).

**Điều đó nghĩa là:** Đừng tìm cú pháp "CREATE BITMAP INDEX" trong PostgreSQL — nó không tồn tại. Thứ cần hiểu là **điều kiện nào** khiến Planner chọn chiến lược Bitmap (selectivity vừa phải, hoặc cần kết hợp nhiều index khác nhau cho cùng 1 query).

---

### Bước 11 — Table Partitioning (RANGE) & Partition Pruning

🎯 **Mục đích:** Khi Index thôi chưa đủ (bảng quá lớn, cần dọn dữ liệu cũ theo lô), chia vật lý bảng theo tháng để truy vấn theo thời gian chỉ đọc đúng 1 partition.

```sql
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events (
    click_id                  BIGINT      NOT NULL,
    partner_id                BIGINT      NOT NULL,
    clicked_at                TIMESTAMP   NOT NULL,
    is_suspicious             BOOLEAN     NOT NULL DEFAULT FALSE,
    reconciliation_status_id  BIGINT,
    PRIMARY KEY (click_id, clicked_at)
) PARTITION BY RANGE (clicked_at);

CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2026_01
    PARTITION OF linh_lab.partner_click_events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
-- ... tương tự cho 02 → 06 ...
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_default
    PARTITION OF linh_lab.partner_click_events DEFAULT;

INSERT INTO linh_lab.partner_click_events (click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id)
SELECT click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id
FROM   linh_lab.partner_click_bench;

SELECT tableoid::regclass AS partition_name, COUNT(*) AS row_count
FROM   linh_lab.partner_click_events
GROUP BY tableoid::regclass
ORDER BY partition_name;
-- Kết quả mong đợi: ~50.000 dòng mỗi partition tháng, 0 dòng ở partition default.

-- ✅ Pruning — lọc theo 1 tháng cụ thể:
EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_events
WHERE clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi: Plan CHỈ nhắc đến partner_click_events_2026_03.

-- ❌ Không pruning — lọc theo cột không phải partition key:
EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_events WHERE partner_id = 3;
-- Kết quả mong đợi: "Append" quét TẤT CẢ 7 partition.
```

**Điều đó nghĩa là:** Partitioning chỉ pruning hiệu quả khi truy vấn lọc **đúng** cột đã chọn làm partition key.

---

### Bước 12 — Bảo trì Partition & Index lan truyền xuống Partition con

🎯 **Mục đích:** Chứng minh Index + Partition cộng hưởng, và so sánh `DELETE` hàng loạt (chậm) với `DETACH`+`DROP` (gần như tức thời).

```sql
-- Thêm partition tương lai, dọn partition cũ:
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2026_07
    PARTITION OF linh_lab.partner_click_events FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

ALTER TABLE linh_lab.partner_click_events
    DETACH PARTITION linh_lab.partner_click_events_2026_01;

DROP TABLE IF EXISTS linh_lab.partner_click_events_2026_01;

SELECT tableoid::regclass AS partition_name, COUNT(*) AS row_count
FROM   linh_lab.partner_click_events
GROUP BY tableoid::regclass
ORDER BY partition_name;
-- Kết quả mong đợi: dữ liệu tháng 1 biến mất, các tháng khác nguyên vẹn.
```

```sql
-- Index tạo trên bảng cha tự lan truyền xuống mọi partition con:
CREATE INDEX IF NOT EXISTS idx_pce_partner_date
    ON linh_lab.partner_click_events (partner_id, clicked_at);

SELECT tablename, indexname
FROM   pg_indexes
WHERE  schemaname = 'linh_lab' AND tablename LIKE 'partner_click_events%'
ORDER BY tablename;
-- Kết quả mong đợi: index xuất hiện trên bảng cha VÀ trên từng partition con.

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_events
WHERE  partner_id = 3 AND clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi: Pruning (chỉ chạm 1 partition) + Index Scan bên trong nó.
```

**Điều đó nghĩa là:** `DETACH`+`DROP` chỉ sửa metadata catalog — nhanh gần như tức thời bất kể partition có bao nhiêu triệu dòng. Chỉ cần tạo Index 1 lần trên bảng cha, không cần lặp lại cho từng partition con.

---

### Bước 13 — Đưa dữ liệu lịch sử vào Partition & LIST/HASH Partitioning

🎯 **Mục đích:** Học cách migrate dữ liệu có sẵn vào partition không downtime, và so sánh 3 chiến lược RANGE/LIST/HASH trên cùng 1 bộ dữ liệu.

```sql
-- Zero-downtime attach nhờ CHECK constraint khớp sẵn range:
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2025_12 (
    click_id                  BIGINT      NOT NULL,
    partner_id                BIGINT      NOT NULL,
    clicked_at                TIMESTAMP   NOT NULL,
    is_suspicious             BOOLEAN     NOT NULL DEFAULT FALSE,
    reconciliation_status_id  BIGINT,
    PRIMARY KEY (click_id, clicked_at),
    CONSTRAINT chk_pce_2025_12_range
        CHECK (clicked_at >= '2025-12-01' AND clicked_at < '2026-01-01')
);
-- ... nạp dữ liệu lịch sử ...

ALTER TABLE linh_lab.partner_click_events
    ATTACH PARTITION linh_lab.partner_click_events_2025_12
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
-- Kết quả mong đợi: ATTACH gần như tức thời nhờ CHECK constraint khớp sẵn.
```

```sql
-- LIST Partitioning theo partner_id (khi predicate phổ biến nhất là "theo đối tác"):
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_by_partner (
    click_id BIGINT NOT NULL, partner_id BIGINT NOT NULL, clicked_at TIMESTAMP NOT NULL,
    is_suspicious BOOLEAN NOT NULL DEFAULT FALSE, reconciliation_status_id BIGINT,
    PRIMARY KEY (click_id, partner_id)
) PARTITION BY LIST (partner_id);
-- p1..p5 FOR VALUES IN (1)..(5), + DEFAULT

EXPLAIN SELECT COUNT(*) FROM linh_lab.partner_click_by_partner WHERE partner_id = 3;
-- Kết quả mong đợi: chỉ chạm 1 partition — pruning hoàn hảo.

EXPLAIN SELECT COUNT(*) FROM linh_lab.partner_click_by_partner
WHERE clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi: quét CẢ 6 partition — ngược hẳn với Bước 11, vì partition key khác.
```

```sql
-- HASH Partitioning theo click_id (khi không có tiêu chí nghiệp vụ, chỉ cần dàn tải):
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_hash (
    click_id BIGINT NOT NULL, partner_id BIGINT NOT NULL, clicked_at TIMESTAMP NOT NULL,
    is_suspicious BOOLEAN NOT NULL DEFAULT FALSE, reconciliation_status_id BIGINT,
    PRIMARY KEY (click_id)
) PARTITION BY HASH (click_id);
-- p0..p3 FOR VALUES WITH (MODULUS 4, REMAINDER 0..3)

SELECT tableoid::regclass, COUNT(*) FROM linh_lab.partner_click_hash
GROUP BY 1 ORDER BY 1;
-- Kết quả mong đợi: ~75.000 dòng mỗi partition — phân phối đồng đều.
```

**Điều đó nghĩa là:** Partition key phải khớp **đúng** predicate phổ biến nhất trong hệ thống thực tế — không có công thức "RANGE theo thời gian luôn đúng". HASH chỉ giải quyết bài toán phân phối tải, không tăng tốc truy vấn nghiệp vụ.

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

### Câu hỏi 1:
> "Vì sao phải đo Selectivity trước khi tạo Index, thay vì cứ tạo rồi xem có nhanh hơn không?"

**Trả lời:**

Vì Index có chi phí đánh đổi 2 chiều: đọc nhanh hơn nhưng ghi chậm hơn + tốn thêm dung lượng đĩa. Nếu selectivity của điều kiện lọc cao (khớp phần lớn bảng), Planner sẽ **không dùng** Index đó dù nó tồn tại — kết quả là ta vẫn chịu chi phí ghi vĩnh viễn mà không được lợi ích đọc nào. Đo trước bằng công thức `COUNT(*) WHERE điều_kiện / COUNT(*) tổng` cho biết chắc chắn Index có đáng tạo hay không, thay vì tạo xong rồi mới phát hiện Planner bỏ qua nó.

### Câu hỏi 2:
> "Tại sao Index tạo trên bảng cha của 1 bảng partition lại tự động có mặt trên mọi partition con, và điều này có ý nghĩa gì cho việc bảo trì hệ thống?"

**Trả lời:**

Từ PostgreSQL 11, khi tạo Index trên bảng cha (partitioned table), engine tự động sinh 1 Index vật lý tương ứng trên mọi partition con hiện có, và tiếp tục làm vậy cho bất kỳ partition nào được thêm vào sau này. Điều này có nghĩa: đội vận hành chỉ cần khai báo Index **1 lần duy nhất** ở bảng cha, không cần nhớ lặp lại cho từng bảng con mới tạo mỗi tháng — giảm hẳn rủi ro quên tạo Index cho partition mới, một lỗi vận hành rất dễ xảy ra nếu phải làm thủ công.

### Câu hỏi 3:
> "Nếu `promotion_program_history` (Task 06) được thiết kế lại với `PARTITION BY RANGE(changed_at)` ngay từ đầu, chính sách 'chỉ giữ 12 tháng gần nhất' thay đổi thế nào?"

**Trả lời:**

Thay vì chạy `DELETE FROM promotion_program_history WHERE changed_at < NOW() - INTERVAL '1 year'` (quét và xóa hàng triệu dòng, tốn WAL nặng nề, có thể khóa bảng đủ lâu để ảnh hưởng UPDATE đang chạy song song), chỉ cần xác định đúng partition tháng đã quá hạn, `DETACH` nó ra khỏi bảng cha rồi `DROP TABLE`. Toàn bộ thao tác gần như tức thời bất kể partition đó chứa bao nhiêu dòng, và hoàn toàn không ảnh hưởng tới các partition tháng khác đang được ghi/đọc song song — đây chính là câu trả lời Task 11 dành cho câu hỏi mở của Task 06.

### Câu hỏi 4:
> "Ứng viên từng làm SQL Server nói: 'Em sẽ tạo Clustered Index trên `clicked_at` để tăng tốc range query theo thời gian.' Câu trả lời này đúng hay sai khi áp dụng cho PostgreSQL, và bạn sẽ điều chỉnh câu trả lời của họ thế nào?"

**Trả lời:**

Câu trả lời đó phản ánh đúng tư duy SQL Server (nơi Clustered Index quyết định luôn cách dữ liệu bảng được lưu trữ vật lý), nhưng **áp dụng sai** sang PostgreSQL vì Postgres không có khái niệm Clustered Index — Heap (nơi lưu dữ liệu) luôn tách biệt khỏi mọi B-Tree Index, bất kể là PK hay Index thường. Câu trả lời đúng cho PostgreSQL: tạo 1 B-Tree Index (Non-Clustered — không có lựa chọn nào khác) trên `clicked_at`, và nếu muốn có thêm lợi ích "dữ liệu vật lý cũng được sắp theo thứ tự đó" (ví dụ để BRIN hiệu quả hơn), có thể chạy thêm `CLUSTER tablename USING index_clicked_at` — nhưng phải hiểu rõ đây là thao tác **một lần**, giữ khóa `ACCESS EXCLUSIVE`, và cần chạy lại định kỳ vì không tự động duy trì như Clustered Index thật. Đây là ví dụ điển hình về việc mang nguyên kinh nghiệm từ 1 RDBMS sang RDBMS khác mà không kiểm chứng lại kiến trúc bên dưới.

---

## 📦 File Deliverable

Sản phẩm của bài tập được lưu trữ tại:
```
tasks/task_11_index_partition/index_partition.sql
```
