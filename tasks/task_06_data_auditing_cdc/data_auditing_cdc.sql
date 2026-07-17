-- ===========================================================================
-- Bài 6 — Data Auditing (Primitive Change Data Capture)
-- ===========================================================================
-- 🎯 Mục tiêu:
--    Xây dựng hệ thống kiểm toán (audit) ở tầng Database bằng History Table
--    + AFTER UPDATE Trigger. Mỗi khi dữ liệu quan trọng bị thay đổi,
--    giá trị CŨ sẽ được lưu lại → không bao giờ mất dấu vết.
--
-- 📖 Khái niệm cốt lõi:
--    Change Data Capture (CDC) = Bắt giữ mọi thay đổi dữ liệu
--    Ở đây ta dùng cơ chế CDC nguyên thủy (Primitive CDC) bằng Trigger,
--    trước khi tìm hiểu các tool CDC hiện đại (Debezium, Kafka Connect).
--
-- 🗂️ Bảng sử dụng:
--    - linh_lab.promotion_program (nguồn dữ liệu gốc)
--    - linh_lab.promotion_program_history (bảng lịch sử — MỚI TẠO)
-- ===========================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- BƯỚC 1 — Tạo History Table (Bảng Lịch Sử)
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Tạo bảng chuyên dụng để lưu trữ trạng thái CŨ của promotion_program
--    trước mỗi lần UPDATE. Đây là "sổ nhật ký" ghi lại mọi thay đổi.
--
-- Tại sao cần bảng riêng?
--    Nếu chỉ dùng cột updated_at trên bảng gốc, ta biết "KHI NÀO" thay đổi
--    nhưng KHÔNG biết giá trị CŨ là gì → mất dấu vết kiểm toán.

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


-- ═══════════════════════════════════════════════════════════════════════════
-- BƯỚC 2 — Tạo Trigger Function (Hàm Kiểm Toán)
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Viết hàm PL/pgSQL truy cập biến đặc biệt OLD (chứa giá trị TRƯỚC KHI
--    update) và INSERT vào history table. Biến NEW chứa giá trị SAU KHI update.
--
-- Giải thích OLD vs NEW:
--    - OLD.budget_limit = giá trị budget TRƯỚC khi UPDATE (ví dụ: 50 triệu)
--    - NEW.budget_limit = giá trị budget SAU khi UPDATE (ví dụ: 500 triệu)
--    - Ta lưu OLD vào history table để luôn có thể truy vết ngược

CREATE OR REPLACE FUNCTION linh_lab.fn_audit_promotion_program()
RETURNS TRIGGER AS $$
BEGIN
    -- Chỉ ghi audit khi có thay đổi thực sự (tránh ghi dư khi UPDATE không đổi giá trị)
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


-- ═══════════════════════════════════════════════════════════════════════════
-- BƯỚC 3 — Gắn Trigger vào Bảng (Attach Trigger)
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Kết nối hàm fn_audit ở Bước 2 vào bảng promotion_program.
--    Dùng AFTER UPDATE (không phải BEFORE) vì ta chỉ muốn ghi audit
--    khi UPDATE THỰC SỰ THÀNH CÔNG — nếu UPDATE bị rollback thì không ghi.

-- Xóa trigger cũ nếu tồn tại (idempotent)
DROP TRIGGER IF EXISTS trg_audit_promotion_program
    ON linh_lab.promotion_program;

CREATE TRIGGER trg_audit_promotion_program
    AFTER UPDATE ON linh_lab.promotion_program
    FOR EACH ROW
    EXECUTE FUNCTION linh_lab.fn_audit_promotion_program();


-- ═══════════════════════════════════════════════════════════════════════════
-- BƯỚC 4 — Kiểm Thử Hệ Thống Kiểm Toán
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 4A — Kiểm tra trạng thái hiện tại TRƯỚC KHI thay đổi
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Ghi nhận giá trị gốc của budget_limit để so sánh sau.

SELECT program_id, program_name, budget_limit, status_id
FROM   linh_lab.promotion_program
WHERE  program_id = 1;

-- Ghi nhớ: budget_limit = ??? (ví dụ: 50,000,000)


-- ─────────────────────────────────────────────────────────────────────────
-- 4B — Mô phỏng "nhân viên gian lận" thay đổi ngân sách
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Giả lập tình huống nhân viên thay đổi budget bất thường.
--    Trigger sẽ tự động lưu giá trị CŨ vào history table.

UPDATE linh_lab.promotion_program
SET    budget_limit = 999000000,
       updated_at   = NOW(),
       updated_by   = 'ROGUE_EMPLOYEE'
WHERE  program_id = 1;

-- Trigger đã âm thầm chạy! Giá trị CŨ (50 triệu) đã được lưu vào history.


-- ─────────────────────────────────────────────────────────────────────────
-- 4C — Kiểm tra Audit Log (Sổ Nhật Ký Kiểm Toán)
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Xác minh trigger đã bắt giữ đúng giá trị CŨ.
--    Đây là bằng chứng kiểm toán (audit evidence) quan trọng.

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

-- Kết quả mong đợi:
-- ┌────────────┬────────────┬──────────────────┬──────────────────┬─────────────────────┬─────────────────┐
-- │ history_id │ program_id │ old_program_name  │ old_budget_limit │ changed_at          │ changed_by      │
-- ├────────────┼────────────┼──────────────────┼──────────────────┼─────────────────────┼─────────────────┤
-- │ 1          │ 1          │ Flash Sale 12.12 │ 50000000.00      │ 2026-06-30 10:00:00 │ ROGUE_EMPLOYEE  │
-- └────────────┴────────────┴──────────────────┴──────────────────┴─────────────────────┴─────────────────┘
--
-- ✅ Giá trị CŨ (50 triệu) đã được bảo toàn! Ta biết:
--    - AI đã thay đổi (ROGUE_EMPLOYEE)
--    - KHI NÀO thay đổi (changed_at)
--    - GIÁ TRỊ CŨ là gì (50,000,000)
--    - GIÁ TRỊ MỚI là gì (999,000,000 — xem bảng gốc)


-- ─────────────────────────────────────────────────────────────────────────
-- 4D — Phục hồi dữ liệu gốc (Rollback thủ công)
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Dùng history table để phục hồi giá trị CŨ,
--    chứng minh audit log không chỉ để "nhìn" mà còn để "sửa".

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

-- Kiểm tra: budget_limit đã quay về giá trị gốc
SELECT program_id, program_name, budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;


-- ═══════════════════════════════════════════════════════════════════════════
-- 💬 CÂU HỎI PHẢN TƯ (Reflection Questions)
-- ═══════════════════════════════════════════════════════════════════════════

/*
 * ────────────────────────────────────────────────────────────────────────
 * Câu hỏi 1:
 * "Tại sao ta dùng AFTER UPDATE trigger cho auditing,
 *  thay vì BEFORE UPDATE trigger?"
 * ────────────────────────────────────────────────────────────────────────
 *
 * Trả lời:
 *
 * 1. AFTER UPDATE chỉ chạy KHI UPDATE ĐÃ THÀNH CÔNG.
 *    Nếu UPDATE bị lỗi (vi phạm constraint, deadlock, rollback),
 *    trigger AFTER sẽ KHÔNG chạy → history table không bị "rác"
 *    với các thay đổi chưa bao giờ thực sự xảy ra.
 *
 * 2. BEFORE UPDATE chạy TRƯỚC KHI UPDATE hoàn tất.
 *    Nếu UPDATE sau đó bị rollback, dòng audit vẫn đã được ghi →
 *    history table chứa "bản ghi ma" (phantom records) — ghi nhận
 *    thay đổi CHƯA BAO GIỜ thực sự xảy ra trong database.
 *
 * 3. Trong ngữ cảnh kiểm toán tài chính (financial auditing),
 *    chỉ ghi nhận thay đổi ĐÃ COMMIT mới có giá trị pháp lý.
 *    AFTER trigger đảm bảo tính chính xác của audit trail.
 *
 * Tóm lại: AFTER = "chỉ ghi khi chắc chắn", BEFORE = "ghi trước rồi tính"
 *
 *
 * ────────────────────────────────────────────────────────────────────────
 * Câu hỏi 2:
 * "Nếu promotion_program được UPDATE 10.000 lần/ngày, history table
 *  sẽ phình to rất nhanh. Trong thực tế, Data Engineer xử lý vấn đề
 *  này như thế nào?"
 * ────────────────────────────────────────────────────────────────────────
 *
 * Trả lời:
 *
 * Trong kiến trúc Data Engineering hiện đại, có nhiều chiến lược:
 *
 * 1. TABLE PARTITIONING (Phân vùng bảng):
 *    Chia history table theo tháng/quý bằng Range Partition trên changed_at.
 *    Ví dụ: promotion_program_history_2026_06, _2026_07, ...
 *    Khi cần xóa dữ liệu cũ, chỉ cần DROP PARTITION thay vì DELETE hàng triệu dòng.
 *
 * 2. ARCHIVAL TO DATA LAKE (Chuyển sang Data Lake):
 *    Dùng scheduled job (Airflow/cron) export dữ liệu history > 90 ngày
 *    sang Parquet/ORC trên S3/GCS. OLTP database chỉ giữ 90 ngày gần nhất.
 *
 * 3. EXTERNAL CDC TOOLS (Thay thế trigger bằng CDC hiện đại):
 *    - Debezium: đọc WAL (Write-Ahead Log) của PostgreSQL và stream
 *      thay đổi sang Kafka → không cần trigger, không ảnh hưởng hiệu năng OLTP.
 *    - AWS DMS, GCP Datastream: managed CDC services.
 *    Đây là giải pháp production-grade, nhưng đòi hỏi hạ tầng phức tạp hơn.
 *
 * 4. RETENTION POLICY (Chính sách lưu giữ):
 *    Tạo scheduled job xóa history records quá hạn:
 *    DELETE FROM history WHERE changed_at < NOW() - INTERVAL '1 year';
 *
 * Tóm lại: Trigger-based CDC phù hợp cho hệ thống nhỏ-vừa. Khi scale lên,
 * chuyển sang WAL-based CDC (Debezium) + Data Lake archival.
 */
