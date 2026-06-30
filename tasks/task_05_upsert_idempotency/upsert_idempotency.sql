-- ===========================================================================
-- DDID-14 | Bài 5 — Design for Retry (Idempotency) Using Database Upserts
-- ===========================================================================
-- 🎯 Mục tiêu:
--    Thiết kế câu truy vấn INSERT có khả năng chạy lại (retry-safe)
--    mà không gây lỗi UNIQUE violation hay trùng lặp dữ liệu.
--
-- 📖 Khái niệm cốt lõi:
--    Idempotency = "Chạy 1 lần hay 10.000 lần → kết quả cuối cùng giống hệt nhau"
--
-- 🗂️ Bảng sử dụng: linh_lab.partner_click
-- ===========================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- SCENARIO A — Pipeline Giòn (Fragile Pipeline — Standard INSERT)
-- ═══════════════════════════════════════════════════════════════════════════
-- Bối cảnh:
--   Một job hàng ngày kéo 100.000 affiliate clicks từ API bên thứ 3
--   và INSERT vào bảng partner_click.
--   Hôm qua job chạy được 50.000 dòng thì mạng sập.
--   Hôm nay chạy lại → 50.000 dòng đầu đã tồn tại → BÙM!

-- ─────────────────────────────────────────────────────────────────────────
-- Bước 1 — Lần nạp đầu tiên (Thành công)
-- ─────────────────────────────────────────────────────────────────────────
INSERT INTO linh_lab.partner_click
    (click_id, partner_code, partner_id, ip_address, clicked_at, created_at, created_by)
VALUES
    ('RETRY_TEST_001', 'KOL001', 1, '192.168.1.1', NOW(), NOW(), 'ETL_USER');

-- Kết quả mong đợi: INSERT 0 1 ✅

-- ─────────────────────────────────────────────────────────────────────────
-- Bước 2 — Pipeline Retry (CRASH!)
-- ─────────────────────────────────────────────────────────────────────────
-- Pipeline sập giữa chừng, chạy lại toàn bộ script → trùng click_id
INSERT INTO linh_lab.partner_click
    (click_id, partner_code, partner_id, ip_address, clicked_at, created_at, created_by)
VALUES
    ('RETRY_TEST_001', 'KOL001', 1, '192.168.1.1', NOW(), NOW(), 'ETL_USER');

-- ❌ Kết quả mong đợi: ERROR — duplicate key value violates unique constraint "partner_click_pkey"
-- 💥 Bài học: Pipeline này GIÒN. Không thể chạy lại an toàn.


-- ═══════════════════════════════════════════════════════════════════════════
-- SCENARIO B — Pipeline Bất Tử (Bulletproof — Idempotent UPSERT)
-- ═══════════════════════════════════════════════════════════════════════════
-- Giải pháp: Sử dụng ON CONFLICT ... DO NOTHING
-- Click stream là Event Log bất biến (immutable) → nếu đã tồn tại, bỏ qua.

-- ─────────────────────────────────────────────────────────────────────────
-- Bước 1 — Refactor sang UPSERT (DO NOTHING)
-- ─────────────────────────────────────────────────────────────────────────
INSERT INTO linh_lab.partner_click
    (click_id, partner_code, partner_id, ip_address, clicked_at, created_at, created_by)
VALUES
    ('RETRY_TEST_002', 'KOL002', 2, '10.0.0.5', NOW(), NOW(), 'ETL_USER')
ON CONFLICT (click_id)
DO NOTHING;

-- Kết quả mong đợi: INSERT 0 1 ✅ (click_id mới → insert thành công)

-- ─────────────────────────────────────────────────────────────────────────
-- Bước 2 — Pipeline Retry (Bulletproof!)
-- ─────────────────────────────────────────────────────────────────────────
-- Chạy LẠI CHÍNH XÁC câu trên
INSERT INTO linh_lab.partner_click
    (click_id, partner_code, partner_id, ip_address, clicked_at, created_at, created_by)
VALUES
    ('RETRY_TEST_002', 'KOL002', 2, '10.0.0.5', NOW(), NOW(), 'ETL_USER')
ON CONFLICT (click_id)
DO NOTHING;

-- Kết quả mong đợi: INSERT 0 0 ✅
-- Không lỗi! Không trùng dữ liệu! Pipeline sống sót qua retry!

-- ─────────────────────────────────────────────────────────────────────────
-- Bước 3 — Xác minh tính Idempotent
-- ─────────────────────────────────────────────────────────────────────────
SELECT click_id, partner_code, ip_address, created_at
FROM   linh_lab.partner_click
WHERE  click_id = 'RETRY_TEST_002';

-- Kết quả mong đợi: Đúng 1 dòng, dữ liệu không thay đổi dù chạy INSERT 2 lần.


-- ═══════════════════════════════════════════════════════════════════════════
-- SCENARIO C — UPSERT cho Dimension Table (DO UPDATE)
-- ═══════════════════════════════════════════════════════════════════════════
-- Khác với Event Log (bất biến), Dimension table cần CẬP NHẬT khi có
-- dữ liệu mới hơn. Ví dụ: partner thay đổi tên hoặc commission rule.

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

-- Lần 1: INSERT 0 1 (tạo mới)

-- Giả lập dữ liệu cập nhật từ source system
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

-- Lần 2: INSERT 0 1 (update dòng cũ, không tạo dòng mới)

-- Kiểm chứng
SELECT partner_code, partner_name, commission_rule_id, created_at, updated_at
FROM   linh_lab.partner
WHERE  partner_code = 'PARTNER_UPSERT_TEST';

-- Kết quả: partner_name = 'Đối Tác Test — Đã Cập Nhật', commission_rule_id = 2
-- created_at giữ nguyên (thời điểm tạo ban đầu), updated_at thay đổi (thời điểm cập nhật)


-- ═══════════════════════════════════════════════════════════════════════════
-- CLEANUP — Dọn dữ liệu test
-- ═══════════════════════════════════════════════════════════════════════════
DELETE FROM linh_lab.partner_click WHERE click_id IN ('RETRY_TEST_001', 'RETRY_TEST_002');
DELETE FROM linh_lab.partner       WHERE partner_code = 'PARTNER_UPSERT_TEST';


-- ═══════════════════════════════════════════════════════════════════════════
-- 💬 CÂU HỎI PHẢN TƯ (Reflection Questions)
-- ═══════════════════════════════════════════════════════════════════════════

/*
 * ────────────────────────────────────────────────────────────────────────
 * Câu hỏi 1:
 * "Tại sao 'Idempotency' được coi là một trong những design pattern
 *  quan trọng nhất cho Data Engineer khi xây dựng pipeline ETL?"
 * ────────────────────────────────────────────────────────────────────────
 *
 * Trả lời:
 *
 * Trong thực tế, pipeline ETL CHẮC CHẮN sẽ thất bại tại một thời điểm nào đó
 * — do mạng timeout, disk đầy, upstream API trả lỗi, hay container bị kill.
 *
 * Khi pipeline thất bại, chiến lược phục hồi phổ biến nhất là RETRY (chạy lại).
 * Nếu pipeline không được thiết kế idempotent:
 *   - INSERT lại → duplicate key error → pipeline crash lần 2
 *   - Hoặc tệ hơn: INSERT thành công nhưng TẠO BẢN GHI TRÙNG → dữ liệu sai
 *
 * Idempotency đảm bảo:
 *   1. Pipeline có thể chạy lại BẤT KỲ LÚC NÀO mà không sợ lỗi
 *   2. Kết quả cuối cùng LUÔN ĐÚNG bất kể chạy 1 hay N lần
 *   3. Đơn giản hóa error handling — không cần logic phức tạp để track
 *      "đã insert đến đâu rồi"
 *   4. Cho phép orchestration tool (Airflow, Dagster) tự động retry
 *      mà không cần can thiệp thủ công
 *
 * Tóm lại: Idempotency biến pipeline từ "giòn" (fragile) thành "bất tử"
 * (bulletproof) — đây là yêu cầu bắt buộc cho production-grade data systems.
 *
 *
 * ────────────────────────────────────────────────────────────────────────
 * Câu hỏi 2:
 * "Trong Scenario B, ta dùng DO NOTHING vì click stream là event log
 *  bất biến. Nếu nạp Dimension table (ví dụ: linh_lab.partner),
 *  làm thế nào dùng DO UPDATE SET ... = EXCLUDED... để cập nhật
 *  payout_rate khi xảy ra conflict?"
 * ────────────────────────────────────────────────────────────────────────
 *
 * Trả lời:
 *
 * Dimension table khác Event Log ở chỗ: dữ liệu CÓ THỂ THAY ĐỔI.
 * Ví dụ: đối tác thay đổi commission rule → cần UPDATE dòng cũ.
 *
 * Cú pháp:
 *
 *   INSERT INTO linh_lab.partner (partner_code, partner_name, commission_rule_id, ...)
 *   VALUES ('KOL001', 'Partner Mới', 3, ...)
 *   ON CONFLICT (partner_code)
 *   DO UPDATE SET
 *       partner_name       = EXCLUDED.partner_name,
 *       commission_rule_id = EXCLUDED.commission_rule_id,
 *       updated_at         = NOW(),
 *       updated_by         = 'ETL_USER';
 *
 * Giải thích:
 *   - EXCLUDED là bảng ảo chứa dòng dữ liệu MỚI đang cố INSERT
 *   - Khi conflict xảy ra (partner_code đã tồn tại), PostgreSQL sẽ
 *     UPDATE dòng hiện tại bằng giá trị từ EXCLUDED
 *   - created_at giữ nguyên (thời điểm tạo ban đầu)
 *   - updated_at cập nhật = NOW() để ghi nhận thời điểm thay đổi
 *
 * Pattern này gọi là "Upsert" — kết hợp INSERT + UPDATE trong 1 câu lệnh,
 * đảm bảo idempotent cho cả Fact table (DO NOTHING) lẫn Dimension table
 * (DO UPDATE).
 *
 * Xem demo đầy đủ tại Scenario C ở trên.
 */
