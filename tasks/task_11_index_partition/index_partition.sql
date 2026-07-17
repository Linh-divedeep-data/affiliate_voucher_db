-- ============================================================================
-- 📘 TASK 11 — Indexing & Partitioning: Từ "Có nên tạo Index không?" đến Production
-- ============================================================================
-- Mục tiêu: Luyện tập ĐÚNG THỨ TỰ một Senior Data/Database Engineer thật sự làm
-- khi gặp 1 bảng/query chậm:
--   STEP 0        — QUYẾT ĐỊNH có cần Index không, dựa trên bằng chứng.
--   STEP 1-6      — INDEX NỀN TẢNG: bench data, Cardinality/Selectivity/ANALYZE,
--                    Composite Index, Leftmost Prefix, Partial Index, chi phí Index.
--   STEP 7-11     — INDEX NÂNG CAO: Covering, Functional, ORDER BY+LIMIT, BRIN,
--                    CONCURRENTLY.
--   STEP 12-14    — BẢN CHẤT LƯU TRỮ CỦA INDEX: Clustered vs Non-Clustered
--                    (lệnh CLUSTER), Hash Index, Bitmap Scan (Index Scan vs
--                    Bitmap Scan vs Seq Scan, BitmapAnd/BitmapOr).
--   STEP 15-20    — PARTITIONING khi Index thôi chưa đủ: RANGE + Pruning,
--                    Attach/Detach, Index lan truyền, LIST, HASH.
--   STEP 21       — Checklist Production mang thẳng vào dự án công ty thực tế.
--
-- Cách dùng: chạy TỪNG STEP một theo đúng thứ tự. Đọc "Mục đích" trước khi chạy,
-- tự dự đoán kết quả, rồi so với "Kết quả mong đợi" trong comment. Toàn bộ giải
-- thích chi tiết (vì sao, cơ chế bên dưới, câu hỏi phỏng vấn tự luyện) nằm ở
-- README.md cùng thư mục — 2 file này luôn đi cùng nhau.
-- ============================================================================

-- ============================================================================
-- 🧹 CLEANUP (Chạy khi muốn reset toàn bộ, bỏ qua nếu chạy lần đầu)
-- ============================================================================
-- DROP TABLE IF EXISTS linh_lab.partner_click_events CASCADE;
-- DROP TABLE IF EXISTS linh_lab.partner_click_by_partner CASCADE;
-- DROP TABLE IF EXISTS linh_lab.partner_click_hash CASCADE;
-- DROP TABLE IF EXISTS linh_lab.partner_click_seq CASCADE;
-- DROP TABLE IF EXISTS linh_lab.partner_click_bench CASCADE;


-- ============================================================================
-- STEP 0 — QUYẾT ĐỊNH có tạo Index hay không (trước khi viết bất kỳ DDL nào)
-- ============================================================================
-- Mục đích: Đây là bước quan trọng nhất và dễ bị bỏ qua nhất. Không tạo Index
-- vì "cảm giác chắc sẽ nhanh hơn" — phải có BẰNG CHỨNG: query nào đang chậm,
-- chậm bao nhiêu, được gọi thường xuyên tới đâu, và điều kiện lọc của nó có
-- đáng để Index hỗ trợ hay không (Selectivity). Xem quy trình đầy đủ 10 bước
-- ở README.md Phần 0.
-- ============================================================================

-- 0.1) Tìm bằng chứng: query nào đang tốn thời gian nhất / được gọi nhiều nhất?
-- Chỉ chạy được nếu extension pg_stat_statements đã bật trên instance của bạn.
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- SELECT query, calls, total_exec_time, mean_exec_time, rows
-- FROM   pg_stat_statements
-- ORDER BY total_exec_time DESC
-- LIMIT 10;
-- Nếu KHÔNG có extension này (phổ biến ở môi trường managed DB hạn chế quyền),
-- dùng log ứng dụng hoặc bật `log_min_duration_statement` trong postgresql.conf.

-- 0.2) Khảo sát hiện trạng Index của bảng THẬT (partner_click — Task 05/06/07):
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'linh_lab'
  AND  tablename   = 'partner_click';
-- Kết quả mong đợi: CHỈ có 1 dòng — partner_click_pkey (PK trên click_id).
-- Không có index nào hỗ trợ lọc theo partner_id/clicked_at.

-- 0.3) Đo baseline ngay trên bảng thật bằng EXPLAIN ANALYZE:
EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click WHERE partner_id = 1;
-- Kết quả mong đợi: "Seq Scan" — NHƯNG execution time gần như 0ms, vì bảng thật
-- chỉ có 5 dòng seed. Bài học: với bảng NHỎ, Seq Scan đã đủ nhanh — tạo Index ở
-- quy mô này là lãng phí thuần túy. Quyết định "CÓ nên tạo Index" luôn phụ
-- thuộc vào QUY MÔ dữ liệu thật, không phải "bảng này có vẻ quan trọng".

-- 💡 Học được: Vì bảng thật quá nhỏ để thấy khác biệt, STEP 1 sẽ tạo 1 bảng
-- benchmark 300.000 dòng — mô phỏng đúng kịch bản "partner_click sau vài tháng
-- vận hành" — để có đủ dữ liệu ra quyết định thật sự.


-- ============================================================================
-- STEP 1 — Sinh dữ liệu benchmark đủ lớn
-- ============================================================================
-- Mục đích: Xây bảng đủ lớn (300.000 dòng) để các quyết định Index ở Step 2 trở
-- đi có ý nghĩa đo lường thật, thay vì chỉ là lý thuyết suông.
-- ============================================================================

CREATE TABLE IF NOT EXISTS linh_lab.partner_click_bench (
    click_id                  BIGSERIAL PRIMARY KEY,
    partner_id                BIGINT      NOT NULL,
    clicked_at                TIMESTAMP   NOT NULL,
    is_suspicious             BOOLEAN     NOT NULL DEFAULT FALSE,
    reconciliation_status_id  BIGINT
);

-- Bơm 300.000 dòng: partner_id ngẫu nhiên 1-5, clicked_at trải đều 6 tháng
-- (2026-01 → 2026-06), ~10% is_suspicious = TRUE, ~30% đã đối soát.
INSERT INTO linh_lab.partner_click_bench (partner_id, clicked_at, is_suspicious, reconciliation_status_id)
SELECT
    1 + floor(random() * 5)::BIGINT,
    TIMESTAMP '2026-01-01' + (random() * INTERVAL '181 days'),
    (random() < 0.1),
    CASE WHEN random() < 0.3 THEN 1 ELSE NULL END
FROM generate_series(1, 300000);

SELECT COUNT(*) AS total_rows FROM linh_lab.partner_click_bench;
SELECT pg_size_pretty(pg_total_relation_size('linh_lab.partner_click_bench')) AS table_size;
-- Kết quả mong đợi: total_rows = 300000; table_size vài chục MB.

-- 💡 Học được: Đừng bao giờ thử đo hiệu năng Index trên bảng nhỏ — mọi chiến
-- lược quét đều "nhanh như nhau" ở quy mô nhỏ, che giấu mất sự khác biệt thật.


-- ============================================================================
-- STEP 2 — Cardinality, Selectivity, pg_stats & ANALYZE (cầu nối lý thuyết → thực hành)
-- ============================================================================
-- Mục đích: Trước khi biết CÓ NÊN tạo Index cho 1 cột hay không, phải đo được
-- Cardinality (số giá trị khác nhau) và Selectivity (tỷ lệ dòng khớp điều kiện)
-- của cột đó — đây là 2 con số quyết định trực tiếp câu trả lời, không phải
-- cảm tính "cột này chắc quan trọng". Xem lý thuyết đầy đủ ở README.md Phần I.
-- ============================================================================

-- 2.1) Đo Cardinality thủ công:
SELECT
    COUNT(DISTINCT partner_id)               AS cardinality_partner_id,
    COUNT(DISTINCT is_suspicious)            AS cardinality_is_suspicious,
    COUNT(DISTINCT reconciliation_status_id) AS cardinality_reconciliation_status,
    COUNT(DISTINCT click_id)                 AS cardinality_click_id,
    COUNT(*)                                 AS total_rows
FROM linh_lab.partner_click_bench;
-- Kết quả mong đợi: cardinality_partner_id = 5; cardinality_is_suspicious = 2;
-- cardinality_click_id = total_rows = 300000 (PK, mỗi giá trị duy nhất).

-- 2.2) Đo Selectivity thủ công của 3 điều kiện tiêu biểu:
SELECT
    ROUND((SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE partner_id = 3)::NUMERIC
        / (SELECT COUNT(*) FROM linh_lab.partner_click_bench), 4) AS selectivity_partner_3,
    ROUND((SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE is_suspicious = TRUE)::NUMERIC
        / (SELECT COUNT(*) FROM linh_lab.partner_click_bench), 4) AS selectivity_suspicious_true,
    ROUND((SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE click_id = 12345)::NUMERIC
        / (SELECT COUNT(*) FROM linh_lab.partner_click_bench), 8) AS selectivity_single_pk;
-- Kết quả mong đợi: selectivity_partner_3 ~ 0.20; selectivity_suspicious_true ~
-- 0.10; selectivity_single_pk ~ 0.0000033 — càng gần 0, càng đáng tạo Index.

-- 2.3) Kiểm tra pg_stats TRƯỚC khi ANALYZE (bảng vừa nạp, Planner đang "mù"):
SELECT attname, null_frac, n_distinct, most_common_vals, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_bench'
ORDER BY attname;

EXPLAIN SELECT * FROM linh_lab.partner_click_bench WHERE partner_id = 3;
-- Kết quả mong đợi: pg_stats có thể trống/thiếu; "rows=" trong EXPLAIN có thể
-- lệch xa so với ~60.000 dòng thật (300.000 × 0.20 vừa tính ở trên).

-- 2.4) Chạy ANALYZE — biến Planner từ "đoán mù" thành "ước lượng có căn cứ":
ANALYZE linh_lab.partner_click_bench;

SELECT attname, null_frac, n_distinct, most_common_vals, most_common_freqs, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_bench'
ORDER BY attname;

EXPLAIN SELECT * FROM linh_lab.partner_click_bench WHERE partner_id = 3;
-- Kết quả mong đợi: pg_stats giờ đầy đủ (most_common_vals chứa cả 5 partner_id
-- với freq ~0.2 mỗi giá trị); "rows=" trong EXPLAIN giờ rất gần ~60.000.

-- 💡 Học được: ANALYZE không phải bước "dọn dẹp" tùy chọn — nó là nguồn dữ liệu
-- DUY NHẤT để Planner ước lượng đúng. Luôn ANALYZE ngay sau bulk load.

-- 2.5) UNIQUE Index có THỰC SỰ kiểm tra dữ liệu, không chỉ là cái tên:
CREATE UNIQUE INDEX idx_test_unique_partner ON linh_lab.partner_click_bench (partner_id);
-- Kết quả mong đợi: LỖI "could not create unique index ... is duplicated" — vì
-- partner_id có nhiều dòng trùng giá trị (mỗi partner ~60.000 dòng). PostgreSQL
-- thực sự quét dữ liệu hiện có để xác nhận, không tạo mù quáng theo tên gọi.

-- 2.6) Index có "bỏ qua" giá trị NULL không? (reconciliation_status_id ~70% NULL)
CREATE INDEX idx_pcb_recon_test ON linh_lab.partner_click_bench (reconciliation_status_id);
EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE reconciliation_status_id IS NULL;
-- Kết quả mong đợi: B-Tree Index CÓ index cả dòng NULL (khác một số RDBMS khác)
-- — Planner có thể dùng Index/Bitmap Scan cho điều kiện IS NULL.
DROP INDEX linh_lab.idx_pcb_recon_test;  -- dọn dẹp, chỉ để minh họa


-- ============================================================================
-- STEP 3 — Ra quyết định & tạo Composite Index đầu tiên
-- ============================================================================
-- Mục đích: Áp dụng đúng kết quả đo ở Step 2 (selectivity ~20% cho partner_id,
-- kết hợp range clicked_at còn thấp hơn nữa) để RA QUYẾT ĐỊNH tạo Index — rồi
-- kiểm chứng bằng EXPLAIN ANALYZE rằng quyết định đó đúng.
-- ============================================================================

-- TRƯỚC khi tạo Index — hành vi mặc định khi chưa quyết định gì:
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id  = 3
  AND  clicked_at  >= '2026-03-01'
  AND  clicked_at  <  '2026-04-01';
-- Kết quả mong đợi: "Seq Scan" — quét toàn bộ 300.000 dòng dù chỉ cần ~12.000
-- dòng khớp (selectivity kết hợp ~4%, đủ thấp để đáng tạo Index).

-- QUYẾT ĐỊNH: selectivity thấp + bảng lớn + 2 cột cùng xuất hiện trong WHERE
-- → tạo Composite Index, đặt cột lọc "=" (partner_id) trước cột lọc "range"
-- (clicked_at) — đúng quy tắc Equality-trước-Range.
CREATE INDEX IF NOT EXISTS idx_pcb_partner_date
    ON linh_lab.partner_click_bench (partner_id, clicked_at);

-- SAU khi tạo Index — chạy lại ĐÚNG câu query trên để kiểm chứng quyết định:
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id  = 3
  AND  clicked_at  >= '2026-03-01'
  AND  clicked_at  <  '2026-04-01';
-- Kết quả mong đợi: "Index Scan" hoặc "Bitmap Heap Scan using idx_pcb_partner_
-- date" — execution time giảm rõ rệt so với Seq Scan ở trên.

-- 💡 Học được: Quy trình đúng luôn là ĐO TRƯỚC → QUYẾT ĐỊNH có căn cứ → TẠO →
-- ĐO LẠI để xác nhận. Không bao giờ chỉ "tạo rồi hy vọng".


-- ============================================================================
-- STEP 4 — Quy tắc Leftmost Prefix (giới hạn của Composite Index)
-- ============================================================================
-- Mục đích: Hiểu rõ composite index KHÔNG phải "cây đũa thần" cho mọi truy vấn
-- — nó chỉ hữu dụng khi truy vấn lọc theo đúng (các) cột dẫn đầu.
-- ============================================================================

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  clicked_at >= '2026-03-01'
  AND  clicked_at <  '2026-04-01';
-- Kết quả mong đợi: Planner quay lại "Seq Scan"! Index (partner_id, clicked_at)
-- vô dụng cho truy vấn này vì bỏ qua cột dẫn đầu (partner_id).

-- 💡 Học được: Index đa cột (A, B) chỉ hữu dụng cho truy vấn lọc theo A, hoặc
-- (A, B) — không hữu dụng nếu chỉ lọc theo B. Đây là lý do STEP 3 phải đặt
-- đúng thứ tự cột ngay từ đầu, không phải chuyện "thêm cột nào cũng được".


-- ============================================================================
-- STEP 5 — Partial Index (tối ưu đúng tập dữ liệu nghiệp vụ cần)
-- ============================================================================
-- Mục đích: sp_reconcile_partner_payout (Task 07) luôn lọc thêm is_suspicious =
-- FALSE AND reconciliation_status_id IS NULL. Thay vì Index cả 300.000 dòng,
-- chỉ Index đúng tập con "click hợp lệ, chưa đối soát".
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_pcb_unreconciled
    ON linh_lab.partner_click_bench (partner_id, clicked_at)
    WHERE is_suspicious = FALSE AND reconciliation_status_id IS NULL;

SELECT
    pg_size_pretty(pg_relation_size('linh_lab.idx_pcb_partner_date'))  AS full_index_size,
    pg_size_pretty(pg_relation_size('linh_lab.idx_pcb_unreconciled')) AS partial_index_size;
-- Kết quả mong đợi: partial_index_size nhỏ hơn full_index_size rõ rệt.

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id               = 3
  AND  is_suspicious             = FALSE
  AND  reconciliation_status_id  IS NULL
  AND  clicked_at >= '2026-03-01'
  AND  clicked_at <  '2026-04-01';
-- Kết quả mong đợi: Planner chọn idx_pcb_unreconciled (partial, nhỏ hơn) thay
-- vì idx_pcb_partner_date (đầy đủ) vì cost thấp hơn.

-- 💡 Học được: Index không nhất thiết phải phủ toàn bộ bảng — index hóa đúng
-- tập con nghiệp vụ thường dùng vừa nhỏ hơn vừa được Planner ưu tiên hơn.


-- ============================================================================
-- STEP 6 — Chi phí của Index & phát hiện Index thừa
-- ============================================================================
-- Mục đích: Index không miễn phí — mỗi INSERT/UPDATE/DELETE phải cập nhật TẤT
-- CẢ index trên bảng đó. Tạo 1 index "thừa" rồi dùng pg_stat_user_indexes để
-- phát hiện — đây là kỹ năng review định kỳ cần mang vào công ty thực tế.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_pcb_partner_only
    ON linh_lab.partner_click_bench (partner_id);

SELECT pg_sleep(1);  -- chờ stats collector flush số liệu idx_scan

SELECT
    indexrelname AS index_name,
    idx_scan      AS times_used,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM   pg_stat_user_indexes
WHERE  schemaname = 'linh_lab'
  AND  relname    = 'partner_click_bench'
ORDER BY idx_scan DESC;
-- Kết quả mong đợi: idx_pcb_partner_only có idx_scan = 0 (hoặc rất thấp) vì
-- idx_pcb_partner_date (cùng cột dẫn đầu) đã bao trùm mọi truy vấn lọc theo
-- partner_id — đây là INDEX THỪA, chỉ tốn chi phí ghi mà không tăng tốc đọc.

DROP INDEX IF EXISTS linh_lab.idx_pcb_partner_only;  -- Dọn dẹp index thừa vừa test

-- 💡 Học được: Production thật cần định kỳ rà soát pg_stat_user_indexes để xóa
-- index không dùng — không phải "tạo xong là xong việc".


-- ============================================================================
-- STEP 7 — Covering Index (INCLUDE) & Index-Only Scan
-- ============================================================================
-- Mục đích: idx_pcb_partner_date chỉ chứa (partner_id, clicked_at). Nếu SELECT
-- thêm is_suspicious, Postgres phải quay lại bảng chính (Heap Fetch). INCLUDE
-- đính kèm thêm cột để tránh việc đó.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_pcb_partner_date_covering
    ON linh_lab.partner_click_bench (partner_id, clicked_at)
    INCLUDE (is_suspicious);

EXPLAIN (ANALYZE, BUFFERS)
SELECT partner_id, clicked_at, is_suspicious
FROM   linh_lab.partner_click_bench
WHERE  partner_id  = 3
  AND  clicked_at  >= '2026-03-01'
  AND  clicked_at  <  '2026-04-01';
-- Kết quả mong đợi (trước VACUUM): "Index Only Scan" nhưng "Heap Fetches" vẫn
-- CAO — visibility map chưa cập nhật sau INSERT hàng loạt.

VACUUM ANALYZE linh_lab.partner_click_bench;

EXPLAIN (ANALYZE, BUFFERS)
SELECT partner_id, clicked_at, is_suspicious
FROM   linh_lab.partner_click_bench
WHERE  partner_id  = 3
  AND  clicked_at  >= '2026-03-01'
  AND  clicked_at  <  '2026-04-01';
-- Kết quả mong đợi (sau VACUUM): "Heap Fetches: 0" — truy vấn không chạm bảng
-- chính, chỉ đọc Index.

-- 💡 Học được: Index-Only Scan chỉ thật sự né được bảng chính khi (1) mọi cột
-- SELECT nằm trong Index, VÀ (2) visibility map đã cập nhật qua VACUUM.


-- ============================================================================
-- STEP 8 — Functional / Expression Index cho báo cáo theo ngày
-- ============================================================================
-- Mục đích: Báo cáo thực tế thường GROUP BY theo NGÀY, không phải timestamp
-- thô. Index trên biểu thức date_trunc('day', clicked_at) tránh Planner phải
-- Sort dữ liệu trước khi gom nhóm.
-- ============================================================================

EXPLAIN ANALYZE
SELECT date_trunc('day', clicked_at) AS report_day, COUNT(*) AS clicks
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3
GROUP BY date_trunc('day', clicked_at)
ORDER BY report_day;

CREATE INDEX IF NOT EXISTS idx_pcb_partner_day
    ON linh_lab.partner_click_bench (partner_id, date_trunc('day', clicked_at));

EXPLAIN ANALYZE
SELECT date_trunc('day', clicked_at) AS report_day, COUNT(*) AS clicks
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3
GROUP BY date_trunc('day', clicked_at)
ORDER BY report_day;
-- Kết quả mong đợi: Sau khi tạo index, plan bỏ được node "Sort" riêng vì dữ
-- liệu đọc ra từ index đã có sẵn thứ tự theo ngày.

-- 💡 Học được: Biểu thức trong query phải khớp Y HỆT biểu thức đã Index thì
-- Planner mới nhận diện được — index thường trên clicked_at KHÔNG hỗ trợ được
-- truy vấn lọc/gom nhóm theo date_trunc('day', clicked_at).


-- ============================================================================
-- STEP 9 — Index cho ORDER BY + LIMIT (Top-N query)
-- ============================================================================
-- Mục đích: Dashboard "10 click gần nhất của partner X" là pattern cực phổ
-- biến. B-Tree quét được CẢ HAI CHIỀU — không cần tạo thêm index DESC riêng.
-- ============================================================================

EXPLAIN ANALYZE
SELECT click_id, clicked_at
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3
ORDER BY clicked_at DESC
LIMIT 10;
-- Kết quả mong đợi: "Limit" → "Index Scan Backward using idx_pcb_partner_date"
-- — KHÔNG có node "Sort" riêng, dù index tạo theo thứ tự ASC.

-- 💡 Học được: 1 index ASC đã đủ phục vụ cả ORDER BY ASC lẫn DESC — đừng tạo
-- thêm index chỉ vì đổi chiều sắp xếp.


-- ============================================================================
-- STEP 10 — BRIN Index cho dữ liệu tương quan vật lý cao (append-only log)
-- ============================================================================
-- Mục đích: partner_click_bench có clicked_at NGẪU NHIÊN — không tương quan
-- vật lý với thứ tự lưu trữ, nên BRIN sẽ không hiệu quả. Tạo bảng mô phỏng
-- đúng tính chất "log ghi liên tục theo thời gian" để so sánh công bằng.
-- ============================================================================

CREATE TABLE IF NOT EXISTS linh_lab.partner_click_seq AS
SELECT click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id
FROM   linh_lab.partner_click_bench
ORDER BY clicked_at;

ANALYZE linh_lab.partner_click_seq;

SELECT attname, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_seq' AND attname = 'clicked_at';
-- Kết quả mong đợi: correlation ~ 1.0 — điều kiện tiên quyết để BRIN hoạt động tốt.

CREATE INDEX IF NOT EXISTS idx_seq_btree ON linh_lab.partner_click_seq (clicked_at);
CREATE INDEX IF NOT EXISTS idx_seq_brin  ON linh_lab.partner_click_seq USING BRIN (clicked_at);

SELECT
    pg_size_pretty(pg_relation_size('linh_lab.idx_seq_btree')) AS btree_size,
    pg_size_pretty(pg_relation_size('linh_lab.idx_seq_brin'))  AS brin_size;
-- Kết quả mong đợi: BRIN nhỏ hơn B-Tree hàng trăm lần.

DROP INDEX IF EXISTS linh_lab.idx_seq_btree;  -- buộc Planner dùng BRIN để kiểm chứng

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_seq
WHERE  clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi: "Bitmap Heap Scan" + "Recheck Cond" + "Bitmap Index Scan
-- using idx_seq_brin".

-- 💡 Học được: BRIN đánh đổi độ chính xác lấy kích thước cực nhỏ — chỉ đáng
-- dùng khi cột có tương quan vật lý cao (log/event append-only). Nếu dữ liệu
-- insert không theo thứ tự, BRIN gần như vô dụng — quay lại B-Tree.


-- ============================================================================
-- STEP 11 — CREATE INDEX CONCURRENTLY (không khóa ghi trên production)
-- ============================================================================
-- Mục đích: CREATE INDEX thường giữ khóa SHARE, chặn mọi ghi trong lúc build.
-- Trên bảng production có traffic, luôn dùng CONCURRENTLY.
-- ⚠️ Chạy riêng lẻ — KHÔNG được nằm trong transaction block.
-- ============================================================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pcb_suspicious_concurrent
    ON linh_lab.partner_click_bench (is_suspicious);

SELECT indexrelid::regclass AS index_name, indisvalid
FROM   pg_index
WHERE  indexrelid = 'linh_lab.idx_pcb_suspicious_concurrent'::regclass;
-- Kết quả mong đợi: indisvalid = true. Nếu build bị gián đoạn, index sẽ ở
-- trạng thái INVALID — phải DROP rồi build CONCURRENTLY lại.

DROP INDEX CONCURRENTLY IF EXISTS linh_lab.idx_pcb_suspicious_concurrent;

-- 💡 Học được: CONCURRENTLY chậm hơn ~2-3 lần so với CREATE INDEX thường, đổi
-- lại không khóa ghi — luôn đáng đánh đổi trên bảng production có traffic.


-- ============================================================================
-- STEP 12 — Clustered vs Non-Clustered Index (lệnh CLUSTER)
-- ============================================================================
-- Mục đích: SQL Server/MySQL InnoDB có khái niệm "Clustered Index" — dữ liệu
-- BẢNG được lưu vật lý theo đúng thứ tự của index đó (leaf node CỦA index CHÍNH
-- LÀ dòng dữ liệu), mỗi bảng chỉ có 1 (thường là PK). PostgreSQL KHÔNG có khái
-- niệm này theo đúng nghĩa — MỌI index của Postgres đều là "Non-Clustered":
-- Heap (nơi lưu dữ liệu thật) luôn tách biệt vật lý khỏi B-Tree Index, chỉ liên
-- kết qua TID. Lệnh CLUSTER là cách GẦN NHẤT Postgres có để mô phỏng lợi ích
-- của Clustered Index — nhưng chỉ là thao tác MỘT LẦN, không tự duy trì.
-- ============================================================================

-- Tạo 1 index đơn cột trên clicked_at riêng cho thí nghiệm này (để đo correlation
-- rõ ràng, tách biệt khỏi index composite đã có):
CREATE INDEX IF NOT EXISTS idx_pcb_clustered_demo
    ON linh_lab.partner_click_bench (clicked_at);

-- Kiểm tra correlation TRƯỚC khi CLUSTER — dữ liệu được INSERT ngẫu nhiên ở
-- STEP 1 nên correlation phải thấp (gần 0):
SELECT attname, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_bench' AND attname = 'clicked_at';
-- Kết quả mong đợi: correlation gần 0 — thứ tự vật lý trên đĩa KHÔNG liên quan
-- gì tới thứ tự giá trị clicked_at.

-- CLUSTER: vật lý sắp xếp lại TOÀN BỘ Heap theo đúng thứ tự của index chỉ định.
-- ⚠️ Đây là thao tác NẶNG: giữ khóa ACCESS EXCLUSIVE (chặn CẢ đọc lẫn ghi) trong
-- suốt quá trình, và cần đủ dung lượng đĩa trống để viết lại toàn bộ bảng.
CLUSTER linh_lab.partner_click_bench USING idx_pcb_clustered_demo;

ANALYZE linh_lab.partner_click_bench;

SELECT attname, correlation
FROM   pg_stats
WHERE  schemaname = 'linh_lab' AND tablename = 'partner_click_bench' AND attname = 'clicked_at';
-- Kết quả mong đợi: correlation ~ 1.0 — Heap giờ đã được viết lại vật lý theo
-- đúng thứ tự clicked_at, y hệt hiệu ứng "Clustered Index" ở SQL Server/InnoDB.

-- ⚠️ Nhược điểm cốt lõi: CLUSTER KHÔNG được duy trì tự động. Mọi INSERT sau thời
-- điểm này sẽ được ghi vào cuối Heap như bình thường, dần dần làm correlation
-- giảm trở lại theo thời gian — phải CLUSTER lại định kỳ (trong cửa sổ bảo trì)
-- nếu muốn giữ lợi ích này, khác hẳn Clustered Index của SQL Server/InnoDB vốn
-- tự động duy trì thứ tự với MỌI lần ghi.

DROP INDEX linh_lab.idx_pcb_clustered_demo;  -- dọn dẹp index chỉ dùng để minh họa

-- 💡 Học được: "Clustered Index" và "Non-Clustered Index" là khái niệm của các
-- RDBMS khác — PostgreSQL không có Clustered Index thật sự, chỉ có CLUSTER (một
-- lệnh one-time reorder). Đừng mang nguyên khái niệm từ SQL Server/MySQL sang
-- Postgres mà không kiểm chứng lại.


-- ============================================================================
-- STEP 13 — Hash Index
-- ============================================================================
-- Mục đích: Hash Index chỉ hỗ trợ toán tử "=" (không hỗ trợ range/sort), đổi lại
-- về lý thuyết tra cứu equality nhanh hơn B-Tree. Từ PostgreSQL 10, Hash Index
-- đã được WAL-logged (an toàn khi crash/replication) — trước đó thường bị
-- khuyến cáo tránh dùng. Thực hành để thấy vì sao B-Tree vẫn thường được chọn
-- hơn trong đa số trường hợp thực tế.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_pcb_partner_hash
    ON linh_lab.partner_click_bench USING HASH (partner_id);

-- Tạo thêm 1 B-Tree đơn cột CÙNG cột để so sánh công bằng (không dùng
-- idx_pcb_partner_date vì đó là composite 2 cột, sẽ không so sánh đúng bản chất):
CREATE INDEX IF NOT EXISTS idx_pcb_partner_btree_single
    ON linh_lab.partner_click_bench (partner_id);

SELECT
    pg_size_pretty(pg_relation_size('linh_lab.idx_pcb_partner_hash'))         AS hash_size,
    pg_size_pretty(pg_relation_size('linh_lab.idx_pcb_partner_btree_single')) AS btree_size;
-- Kết quả mong đợi: kích thước 2 loại khá gần nhau (không có ưu thế áp đảo).

EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE partner_id = 3;
-- Kết quả mong đợi: Planner có thể chọn 1 trong 2 index (thường B-Tree vẫn được
-- ưu tiên nếu cost tương đương, vì B-Tree "linh hoạt" hơn cho các câu query khác).

-- Hash Index KHÔNG hỗ trợ điều kiện range — chỉ B-Tree mới dùng được ở đây:
EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE partner_id > 3;
-- Kết quả mong đợi: Plan dùng idx_pcb_partner_btree_single (hoặc Seq Scan) —
-- idx_pcb_partner_hash không bao giờ xuất hiện trong plan này.

DROP INDEX linh_lab.idx_pcb_partner_hash;
DROP INDEX linh_lab.idx_pcb_partner_btree_single;

-- 💡 Học được: Hash Index chỉ phục vụ đúng 1 loại toán tử (`=`), trong khi
-- B-Tree phục vụ được `=`, `<`, `>`, `BETWEEN`, `ORDER BY` với chi phí tương
-- đương cho equality — đây là lý do B-Tree gần như luôn được chọn mặc định,
-- Hash Index chỉ đáng cân nhắc trong các trường hợp rất đặc thù (ví dụ cột cực
-- rộng mà chỉ cần so sánh bằng, và đã đo thực tế thấy Hash nhanh hơn).


-- ============================================================================
-- STEP 14 — Bitmap Scan (Index Scan vs Bitmap Scan vs Seq Scan)
-- ============================================================================
-- Mục đích: Làm rõ 1 hiểu lầm phổ biến — "Bitmap Index" trong PostgreSQL KHÔNG
-- PHẢI một loại index được lưu trữ (khác với Oracle, nơi Bitmap Index là 1 loại
-- index thật). Trong Postgres, "Bitmap Index Scan"/"Bitmap Heap Scan" chỉ là
-- một CHIẾN LƯỢC THỰC THI được Planner dựng ĐỘNG lúc chạy, từ index B-Tree
-- (hoặc bất kỳ access method nào) đã có sẵn — không phải một CREATE INDEX riêng.
-- ============================================================================

-- 14.1) Selectivity RẤT THẤP → Index Scan thuần (đã thấy ở STEP 4, nhắc lại để so sánh):
EXPLAIN ANALYZE
SELECT COUNT(*) FROM linh_lab.partner_click_bench WHERE click_id = 12345;
-- Kết quả mong đợi: "Index Scan using partner_click_bench_pkey" — số dòng khớp
-- quá ít (1 dòng) nên Postgres tra thẳng từng dòng qua Index, không cần bitmap.

-- 14.2) Selectivity VỪA PHẢI → Bitmap Heap Scan (nhiều dòng khớp, nhưng chưa
-- đủ nhiều để Seq Scan thắng):
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id IN (1, 2)
  AND  clicked_at >= '2026-01-01' AND clicked_at < '2026-07-01';
-- Kết quả mong đợi: "Bitmap Heap Scan" + "Recheck Cond" + "Bitmap Index Scan
-- using idx_pcb_partner_date" (hoặc "BitmapOr" nếu Planner tách IN (1,2) thành
-- 2 lần quét bitmap rồi hợp lại). Đây chính là hành vi "Bitmap Index" mà Oracle
-- gọi là 1 loại index riêng — ở Postgres nó CHỈ là 1 bước trung gian.

-- 14.3) Kết hợp BitmapAnd giữa 2 index KHÁC NHAU (không phải cùng 1 composite):
CREATE INDEX IF NOT EXISTS idx_pcb_suspicious_bmp
    ON linh_lab.partner_click_bench (is_suspicious);

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_bench
WHERE  partner_id = 3 AND is_suspicious = TRUE;
-- Kết quả mong đợi: Planner CÓ THỂ dùng "BitmapAnd" để giao (AND) kết quả bitmap
-- từ idx_pcb_partner_date và idx_pcb_suspicious_bmp lại với nhau trước khi đọc
-- Heap — tận dụng được CẢ HAI index cho 1 câu query duy nhất, điều mà Index
-- Scan thuần không làm được (chỉ dùng được 1 index tại 1 thời điểm).

DROP INDEX linh_lab.idx_pcb_suspicious_bmp;

-- 💡 Học được: "Bitmap Index Scan"/"BitmapAnd"/"BitmapOr" là CHIẾN LƯỢC THỰC THI
-- linh hoạt dựng động từ các B-Tree Index đã có — không phải 1 loại CREATE INDEX
-- riêng như ở Oracle. Đừng tìm cú pháp "CREATE BITMAP INDEX" trong PostgreSQL —
-- nó không tồn tại; thứ cần hiểu là ĐIỀU KIỆN nào khiến Planner chọn chiến lược
-- này (selectivity vừa phải, hoặc cần kết hợp nhiều index khác nhau).


-- ============================================================================
-- STEP 15 — Table Partitioning (RANGE theo tháng) + Partition Pruning
-- ============================================================================
-- Mục đích: Index giúp tìm nhanh hơn TRONG 1 bảng, nhưng bảng vẫn là MỘT khối
-- vật lý duy nhất. Khi Index thôi chưa đủ (bảng quá lớn, cần dọn dữ liệu cũ
-- theo lô), Partitioning chia vật lý bảng thành nhiều bảng con.
-- ============================================================================

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
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2026_02
    PARTITION OF linh_lab.partner_click_events FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2026_03
    PARTITION OF linh_lab.partner_click_events FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2026_04
    PARTITION OF linh_lab.partner_click_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2026_05
    PARTITION OF linh_lab.partner_click_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2026_06
    PARTITION OF linh_lab.partner_click_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
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

EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_events
WHERE clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi: Plan CHỈ nhắc đến partner_click_events_2026_03 — 6
-- partition còn lại bị loại bỏ ngay từ bước lập kế hoạch (Partition Pruning).

EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_events WHERE partner_id = 3;
-- Kết quả mong đợi: "Append" quét TẤT CẢ 7 partition — Planner không biết
-- partner_id = 3 nằm ở tháng nào.

-- 💡 Học được: Partitioning chỉ pruning hiệu quả khi truy vấn lọc ĐÚNG cột đã
-- chọn làm partition key — chọn sai key khiến pruning vô dụng.


-- ============================================================================
-- STEP 16 — Bảo trì Partition: thêm mới & dọn dữ liệu cũ (Attach/Detach/Drop)
-- ============================================================================
-- Mục đích: So sánh DELETE hàng loạt (chậm) với DETACH/DROP (gần như tức thời).
-- ============================================================================

-- Thêm partition tháng 7 cho tương lai — không downtime, không khóa bảng:
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_events_2026_07
    PARTITION OF linh_lab.partner_click_events FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

-- "Xóa" nguyên tháng 1 bằng cách tách rồi drop:
ALTER TABLE linh_lab.partner_click_events
    DETACH PARTITION linh_lab.partner_click_events_2026_01;

DROP TABLE IF EXISTS linh_lab.partner_click_events_2026_01;

SELECT tableoid::regclass AS partition_name, COUNT(*) AS row_count
FROM   linh_lab.partner_click_events
GROUP BY tableoid::regclass
ORDER BY partition_name;
-- Kết quả mong đợi: dữ liệu tháng 1 đã biến mất, các tháng khác nguyên vẹn.

-- 💡 Học được: DETACH + DROP chỉ sửa metadata catalog — nhanh gần như tức thời
-- bất kể partition có bao nhiêu triệu dòng, khác hẳn DELETE (quét + xóa + ghi
-- WAL từng dòng).


-- ============================================================================
-- STEP 17 — Index trên bảng cha lan truyền xuống Partition con
-- ============================================================================
-- Mục đích: Chứng minh Index và Partition CỘNG HƯỞNG — tạo 1 lần trên bảng cha
-- là đủ, Postgres tự nhân bản xuống mọi partition con.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_pce_partner_date
    ON linh_lab.partner_click_events (partner_id, clicked_at);

SELECT tablename, indexname
FROM   pg_indexes
WHERE  schemaname = 'linh_lab'
  AND  tablename  LIKE 'partner_click_events%'
ORDER BY tablename;
-- Kết quả mong đợi: idx_pce_partner_date xuất hiện trên bảng cha VÀ trên từng
-- partition con dưới dạng index vật lý riêng.

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM   linh_lab.partner_click_events
WHERE  partner_id = 3
  AND  clicked_at >= '2026-03-01'
  AND  clicked_at <  '2026-04-01';
-- Kết quả mong đợi: Plan chỉ chạm partner_click_events_2026_03 (Pruning), và
-- bên trong là Index Scan (Index tăng tốc bên trong) — Index + Partition dùng
-- cùng lúc.


-- ============================================================================
-- STEP 18 — Đưa dữ liệu lịch sử có sẵn vào làm Partition (Zero-downtime)
-- ============================================================================
-- Mục đích: Dữ liệu "tháng cũ" thường đã tồn tại trước khi quyết định partition
-- hóa. CHECK constraint khớp sẵn range giúp ATTACH bỏ qua bước quét validate.
-- ============================================================================

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

INSERT INTO linh_lab.partner_click_events_2025_12 (click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id)
SELECT
    900000 + gs,
    1 + floor(random() * 5)::BIGINT,
    TIMESTAMP '2025-12-01' + (random() * INTERVAL '30 days'),
    (random() < 0.1),
    NULL
FROM generate_series(1, 100) AS gs;

ALTER TABLE linh_lab.partner_click_events
    ATTACH PARTITION linh_lab.partner_click_events_2025_12
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
-- Kết quả mong đợi: ATTACH hoàn tất gần như tức thời nhờ CHECK constraint đã
-- chứng minh sẵn dữ liệu khớp range — Postgres bỏ qua bước quét validate.

SELECT tableoid::regclass AS partition_name, COUNT(*) AS row_count
FROM   linh_lab.partner_click_events
GROUP BY tableoid::regclass
ORDER BY partition_name;


-- ============================================================================
-- STEP 19 — LIST Partitioning (phân vùng theo giá trị rời rạc)
-- ============================================================================
-- Mục đích: RANGE phù hợp khi predicate phổ biến nhất là "khoảng thời gian".
-- Nếu nghiệp vụ luôn tách dữ liệu theo TỪNG PARTNER, LIST mới khớp đúng pattern.
-- ============================================================================

CREATE TABLE IF NOT EXISTS linh_lab.partner_click_by_partner (
    click_id                  BIGINT      NOT NULL,
    partner_id                BIGINT      NOT NULL,
    clicked_at                TIMESTAMP   NOT NULL,
    is_suspicious             BOOLEAN     NOT NULL DEFAULT FALSE,
    reconciliation_status_id  BIGINT,
    PRIMARY KEY (click_id, partner_id)
) PARTITION BY LIST (partner_id);

CREATE TABLE IF NOT EXISTS linh_lab.partner_click_by_partner_p1
    PARTITION OF linh_lab.partner_click_by_partner FOR VALUES IN (1);
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_by_partner_p2
    PARTITION OF linh_lab.partner_click_by_partner FOR VALUES IN (2);
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_by_partner_p3
    PARTITION OF linh_lab.partner_click_by_partner FOR VALUES IN (3);
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_by_partner_p4
    PARTITION OF linh_lab.partner_click_by_partner FOR VALUES IN (4);
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_by_partner_p5
    PARTITION OF linh_lab.partner_click_by_partner FOR VALUES IN (5);
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_by_partner_default
    PARTITION OF linh_lab.partner_click_by_partner DEFAULT;

INSERT INTO linh_lab.partner_click_by_partner (click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id)
SELECT click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id
FROM   linh_lab.partner_click_bench;

EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_by_partner WHERE partner_id = 3;
-- Kết quả mong đợi: Chỉ chạm partner_click_by_partner_p3 — pruning hoàn hảo.

EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_by_partner
WHERE clicked_at >= '2026-03-01' AND clicked_at < '2026-04-01';
-- Kết quả mong đợi: "Append" quét CẢ 6 partition — ngược hẳn với STEP 15, vì
-- partition key ở đây là partner_id, không phải thời gian.

-- 💡 Học được: Partition key phải khớp predicate phổ biến nhất trong hệ thống
-- thực tế — không có công thức "RANGE theo thời gian luôn đúng".


-- ============================================================================
-- STEP 20 — HASH Partitioning (phân phối đều, không theo tiêu chí nghiệp vụ)
-- ============================================================================
-- Mục đích: Khi không có tiêu chí nghiệp vụ tự nhiên, chỉ cần dàn đều tải ghi.
-- ============================================================================

CREATE TABLE IF NOT EXISTS linh_lab.partner_click_hash (
    click_id                  BIGINT      NOT NULL,
    partner_id                BIGINT      NOT NULL,
    clicked_at                TIMESTAMP   NOT NULL,
    is_suspicious             BOOLEAN     NOT NULL DEFAULT FALSE,
    reconciliation_status_id  BIGINT,
    PRIMARY KEY (click_id)
) PARTITION BY HASH (click_id);

CREATE TABLE IF NOT EXISTS linh_lab.partner_click_hash_p0
    PARTITION OF linh_lab.partner_click_hash FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_hash_p1
    PARTITION OF linh_lab.partner_click_hash FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_hash_p2
    PARTITION OF linh_lab.partner_click_hash FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE IF NOT EXISTS linh_lab.partner_click_hash_p3
    PARTITION OF linh_lab.partner_click_hash FOR VALUES WITH (MODULUS 4, REMAINDER 3);

INSERT INTO linh_lab.partner_click_hash (click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id)
SELECT click_id, partner_id, clicked_at, is_suspicious, reconciliation_status_id
FROM   linh_lab.partner_click_bench;

SELECT tableoid::regclass AS partition_name, COUNT(*) AS row_count
FROM   linh_lab.partner_click_hash
GROUP BY tableoid::regclass
ORDER BY partition_name;
-- Kết quả mong đợi: ~75.000 dòng mỗi partition — phân phối đồng đều.

EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_hash WHERE click_id = 12345;
-- Kết quả mong đợi: chỉ 1 partition được chạm tới.

EXPLAIN
SELECT COUNT(*) FROM linh_lab.partner_click_hash WHERE partner_id = 3;
-- Kết quả mong đợi: "Append" quét cả 4 partition — HASH chỉ phục vụ mục đích
-- phân phối tải/ghi đều, KHÔNG tăng tốc truy vấn theo nghiệp vụ.


-- ============================================================================
-- STEP 21 — Tổng kết: Checklist Production
-- ============================================================================
-- Mục đích: Danh sách kiểm tra trước khi mang Index/Partition lên production —
-- ghi nhớ đây là bước bắt buộc, không phải "làm cho có".
-- ============================================================================

-- [ ] Đã dùng EXPLAIN (ANALYZE, BUFFERS) trên dữ liệu volume THẬT, không chỉ
--     tin vào lý thuyết.
-- [ ] Đã ANALYZE / VACUUM ANALYZE ngay sau bulk load.
-- [ ] Đã dùng CREATE INDEX CONCURRENTLY nếu bảng có traffic ghi.
-- [ ] Đã kiểm tra pg_stat_user_indexes định kỳ, loại bỏ index không dùng.
-- [ ] Partition key đã khớp predicate phổ biến nhất trong hệ thống thực tế.
-- [ ] Đã có kế hoạch tự động tạo partition tương lai (cron/job) trước khi dữ
--     liệu "tràn" vào partition DEFAULT.
-- [ ] Có kế hoạch dọn dữ liệu cũ bằng DETACH/DROP, không DELETE hàng loạt.
-- [ ] Mọi quyết định tạo Index đều bắt đầu từ STEP 0 — bằng chứng thật, không
--     phải cảm giác.
--
-- Xem quy trình đầy đủ (10 bước + bảng quyết định + câu hỏi phỏng vấn tự luyện)
-- tại README.md cùng thư mục.


-- ============================================================================
-- 🧹 DỌN DẸP SAU KHI HOÀN THÀNH BÀI THỰC HÀNH
-- ============================================================================
-- DROP TABLE IF EXISTS linh_lab.partner_click_events CASCADE;
-- DROP TABLE IF EXISTS linh_lab.partner_click_by_partner CASCADE;
-- DROP TABLE IF EXISTS linh_lab.partner_click_hash CASCADE;
-- DROP TABLE IF EXISTS linh_lab.partner_click_seq CASCADE;
-- DROP TABLE IF EXISTS linh_lab.partner_click_bench CASCADE;
