-- ===========================================================================
-- Bài 7 — Advanced Data Orchestration & Dynamic Reporting
-- ===========================================================================
-- 🎯 Mục tiêu:
--    1. Đóng gói quy trình nghiệp vụ phức tạp (Reconciliation) vào
--       Stored Procedure với EXCEPTION handling.
--    2. Xây dựng Dynamic Reporting Functions trả về TABLE, hỗ trợ
--       lọc bằng BIGINT[] (array parameter).
--
-- 🗂️ Bảng sử dụng:
--    - linh_lab.partner_click     (quét & đánh dấu đã đối soát)
--    - linh_lab.partner           (đọc payout_rate)
--    - linh_lab.commission_rule   (chứa payout_rate)
--    - linh_lab.promotion_program (đọc budget)
--    - linh_lab.budget_transaction (tính chi tiêu thực tế)
-- ===========================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- BƯỚC 1 — Stored Procedure: Chốt Sổ Đối Tác Cuối Tháng (Reconciliation)
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Tạo procedure chốt sổ hoa hồng đối tác theo tháng. Procedure:
--    - Đếm click hợp lệ (is_suspicious = FALSE) chưa đối soát
--    - Đánh dấu các click này là "đã đối soát" (reconciled)
--    - Tính tổng payout = valid_clicks × payout_rate
--    - Nếu có lỗi bất kỳ → ROLLBACK toàn bộ, không có dữ liệu bị "nửa vời"
--
-- Tại sao dùng Procedure thay vì Function?
--    Procedure hỗ trợ COMMIT/ROLLBACK bên trong → phù hợp cho quy trình
--    ghi dữ liệu nhiều bước. Function thì KHÔNG được phép COMMIT/ROLLBACK.

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
    -- ─────────────────────────────────────────────────────────────────
    -- Bước 1.1: Lấy thông tin đối tác và tỷ lệ hoa hồng
    -- ─────────────────────────────────────────────────────────────────
    SELECT p.partner_name, cr.payout_rate
    INTO   v_partner_name, v_payout_rate
    FROM   linh_lab.partner p
    JOIN   linh_lab.commission_rule cr
           ON p.commission_rule_id = cr.commission_rule_id
    WHERE  p.partner_id = p_partner_id
      AND  p.is_deleted = FALSE;

    -- Kiểm tra partner tồn tại
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partner ID % not found or has been deleted', p_partner_id;
    END IF;

    -- ─────────────────────────────────────────────────────────────────
    -- Bước 1.2: Đếm click hợp lệ CHƯA đối soát trong tháng
    --           (Idempotent: chỉ đếm click có reconciliation_status_id IS NULL)
    -- ─────────────────────────────────────────────────────────────────
    SELECT COUNT(*)
    INTO   v_total_valid_clicks
    FROM   linh_lab.partner_click
    WHERE  partner_id = p_partner_id
      AND  is_suspicious = FALSE
      AND  reconciliation_status_id IS NULL
      AND  EXTRACT(MONTH FROM clicked_at) = p_month
      AND  EXTRACT(YEAR  FROM clicked_at) = p_year;

    -- ─────────────────────────────────────────────────────────────────
    -- Bước 1.3: Đánh dấu các click đã đối soát
    -- ─────────────────────────────────────────────────────────────────
    UPDATE linh_lab.partner_click
    SET    reconciliation_status_id = 1,
           reconciled_at = NOW(),
           reconciled_by = 'SYSTEM_PROCEDURE'
    WHERE  partner_id = p_partner_id
      AND  is_suspicious = FALSE
      AND  reconciliation_status_id IS NULL
      AND  EXTRACT(MONTH FROM clicked_at) = p_month
      AND  EXTRACT(YEAR  FROM clicked_at) = p_year;

    -- ─────────────────────────────────────────────────────────────────
    -- Bước 1.4: Tính tổng payout và thông báo kết quả
    -- ─────────────────────────────────────────────────────────────────
    v_total_payout := v_total_valid_clicks * v_payout_rate;

    RAISE INFO '══════════════════════════════════════════════════';
    RAISE INFO '✅ Reconciliation Report';
    RAISE INFO '   Partner    : % (ID: %)', v_partner_name, p_partner_id;
    RAISE INFO '   Period     : %/%', p_month, p_year;
    RAISE INFO '   Valid Clicks: %', v_total_valid_clicks;
    RAISE INFO '   Payout Rate: %', v_payout_rate;
    RAISE INFO '   Total Payout: % VND', v_total_payout;
    RAISE INFO '══════════════════════════════════════════════════';

    -- Lưu ý: KHÔNG cần COMMIT ở đây.
    -- Khi dùng EXCEPTION block, PostgreSQL tạo subtransaction (savepoint).
    -- COMMIT bên trong subtransaction sẽ gây lỗi:
    --   "cannot commit while a subtransaction is active"
    -- PostgreSQL tự auto-commit khi CALL kết thúc thành công.

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE WARNING '❌ Reconciliation FAILED for Partner %: %', p_partner_id, SQLERRM;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- BƯỚC 2 — Dynamic Function 1: Báo Cáo Hiệu Suất Đối Tác
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Tạo function trả về TABLE chứa KPI hiệu suất đối tác:
--    tổng click, click hợp lệ, click gian lận, tỉ lệ gian lận.
--    Hỗ trợ lọc theo khoảng thời gian và mảng partner_id (BIGINT[]).
--    Nếu p_partner_ids = NULL → trả về TẤT CẢ đối tác.
--
-- Tại sao dùng Function thay vì Procedure?
--    Function chỉ ĐỌC dữ liệu (SELECT) → không cần COMMIT/ROLLBACK.
--    Function có thể dùng trực tiếp trong SELECT: SELECT * FROM fn_...(...)

CREATE OR REPLACE FUNCTION linh_lab.fn_partner_performance_report(
    p_start_date   TIMESTAMP,
    p_end_date     TIMESTAMP,
    p_partner_ids  BIGINT[] DEFAULT NULL
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
STABLE                    -- Đánh dấu function chỉ ĐỌC, giúp optimizer tối ưu
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


-- ═══════════════════════════════════════════════════════════════════════════
-- BƯỚC 3 — Dynamic Function 2: Báo Cáo Sử Dụng Ngân Sách Chương Trình
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Tạo function tính ngân sách còn lại của chương trình khuyến mãi.
--    Sử dụng Double-Entry Ledger pattern: tổng chi = SUM(amount) WHERE entry_type = 'spend'
--    Ngân sách còn lại = budget_limit - actual_spent.
--    Hỗ trợ lọc theo status_id và mảng program_id (BIGINT[]).

CREATE OR REPLACE FUNCTION linh_lab.fn_program_budget_usage(
    p_status_id    BIGINT   DEFAULT NULL,
    p_program_ids  BIGINT[] DEFAULT NULL
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
        COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'income'), 0)     AS total_income,
        COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0)      AS actual_spent,
        pp.budget_limit
            - COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0) AS remaining_budget,
        ROUND(
            COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0) * 100.0
            / NULLIF(pp.budget_limit, 0),
            2
        )                                                                        AS usage_pct
    FROM   linh_lab.promotion_program pp
    LEFT JOIN linh_lab.budget_transaction bt
           ON pp.program_id = bt.program_id
          AND bt.is_deleted = FALSE
    WHERE  pp.is_deleted = FALSE
      AND  (p_status_id   IS NULL OR pp.status_id   = p_status_id)
      AND  (p_program_ids IS NULL OR pp.program_id   = ANY(p_program_ids))
    GROUP BY pp.program_name, pp.budget_limit
    ORDER BY usage_pct DESC NULLS LAST;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- BƯỚC 4 — Kiểm Thử (Testing)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 4A — Kiểm thử Procedure: Chốt sổ đối tác tháng 6/2026
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Xác minh procedure chạy đúng — đếm click, đánh dấu,
--    tính payout. Chạy lần 2 phải idempotent (0 click vì đã đối soát).

CALL linh_lab.sp_reconcile_partner_payout(1, 6, 2026);

-- Chạy lần 2 — kiểm tra idempotency
CALL linh_lab.sp_reconcile_partner_payout(1, 6, 2026);
-- Kết quả mong đợi: Valid Clicks = 0 (đã đối soát ở lần 1)

-- Kiểm chứng: các click đã được đánh dấu reconciled
SELECT click_id, partner_id, reconciliation_status_id, reconciled_at, reconciled_by
FROM   linh_lab.partner_click
WHERE  partner_id = 1
  AND  reconciliation_status_id IS NOT NULL
LIMIT 5;


-- ─────────────────────────────────────────────────────────────────────────
-- 4B — Kiểm thử Function 1: Báo cáo hiệu suất đối tác
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Xác minh function trả về đúng KPI và hỗ trợ lọc bằng array.

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


-- ─────────────────────────────────────────────────────────────────────────
-- 4C — Kiểm thử Function 2: Báo cáo sử dụng ngân sách
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Xác minh tính toán remaining_budget đúng theo Double-Entry Ledger.

-- Tất cả chương trình
SELECT * FROM linh_lab.fn_program_budget_usage();

-- Chỉ chương trình đang Active (giả sử status_id = 2)
SELECT * FROM linh_lab.fn_program_budget_usage(2);

-- Chỉ chương trình cụ thể
SELECT * FROM linh_lab.fn_program_budget_usage(
    NULL,
    ARRAY[1, 2]::BIGINT[]
);


-- ═══════════════════════════════════════════════════════════════════════════
-- 💬 CÂU HỎI PHẢN TƯ (Reflection Questions)
-- ═══════════════════════════════════════════════════════════════════════════

/*
 * ────────────────────────────────────────────────────────────────────────
 * Câu hỏi 1:
 * "Trong cấu trúc Procedure ở trên, tại sao lệnh ROLLBACK được đặt
 *  bên trong khối EXCEPTION? Nếu thiếu khối EXCEPTION, thảm họa kinh tế
 *  nào có thể xảy ra nếu server mất điện giữa chừng lệnh UPDATE?"
 * ────────────────────────────────────────────────────────────────────────
 *
 * Trả lời:
 *
 * Khối EXCEPTION hoạt động như một "tấm lưới an toàn" (safety net):
 *
 * 1. KHI CÓ EXCEPTION BLOCK:
 *    - Nếu bất kỳ lỗi nào xảy ra (mất kết nối, constraint violation,
 *      out of memory...), PostgreSQL nhảy vào EXCEPTION block
 *    - ROLLBACK hoàn tác TOÀN BỘ thay đổi → dữ liệu quay về trạng thái
 *      trước khi procedure bắt đầu
 *    - RAISE WARNING ghi log lỗi để debug
 *
 * 2. NẾU THIẾU EXCEPTION BLOCK — Thảm họa kinh tế:
 *    Giả sử procedure đang chạy đến Bước 1.3 (UPDATE click → reconciled),
 *    server mất điện SAU khi đánh dấu 30.000/50.000 click:
 *
 *    - 30.000 click đã bị đánh dấu "đã đối soát" → KHÔNG BAO GIỜ
 *      được tính lại hoa hồng (vì điều kiện WHERE reconciliation_status_id IS NULL)
 *    - 20.000 click còn lại chưa bị đánh dấu → vẫn có thể đối soát
 *    - Kết quả: đối tác THIẾU hoa hồng cho 30.000 click
 *      → tranh chấp tài chính, mất đối tác, rủi ro pháp lý
 *
 *    Tuy nhiên, cần lưu ý: PostgreSQL mặc định đã có transaction safety —
 *    nếu server crash, transaction chưa COMMIT sẽ tự động ROLLBACK khi
 *    recovery. Khối EXCEPTION ở đây chủ yếu bắt lỗi LOGIC (ví dụ:
 *    partner không tồn tại, constraint violation) để procedure kết thúc
 *    gracefully thay vì crash với unhandled exception.
 *
 *
 * ────────────────────────────────────────────────────────────────────────
 * Câu hỏi 2:
 * "Sự khác biệt lớn nhất giữa FUNCTION và PROCEDURE trong PostgreSQL
 *  là gì? (Gợi ý: Nghĩ về lý do sp_reconcile cần COMMIT/ROLLBACK
 *  nhưng các function báo cáo thì không)"
 * ────────────────────────────────────────────────────────────────────────
 *
 * Trả lời:
 *
 * ┌──────────────┬──────────────────────────┬──────────────────────────┐
 * │ Tiêu chí     │ FUNCTION                 │ PROCEDURE                │
 * ├──────────────┼──────────────────────────┼──────────────────────────┤
 * │ Gọi bằng     │ SELECT fn_name(...)      │ CALL sp_name(...)        │
 * │ Trả về       │ Giá trị / TABLE / void   │ Không trả về giá trị    │
 * │ Transaction  │ KHÔNG được COMMIT/       │ CÓ THỂ COMMIT/ROLLBACK  │
 * │ control      │ ROLLBACK bên trong       │ bên trong                │
 * │ Dùng trong   │ ✅ Có thể dùng trong    │ ❌ Không thể dùng       │
 * │ SELECT       │ SELECT * FROM fn(...)    │ trong SELECT             │
 * │ Use case     │ Đọc dữ liệu, tính toán, │ Quy trình nghiệp vụ     │
 * │              │ báo cáo                  │ nhiều bước, ghi dữ liệu  │
 * └──────────────┴──────────────────────────┴──────────────────────────┘
 *
 * Tóm lại:
 * - FUNCTION = "máy tính bỏ túi" → tính toán và trả kết quả, chỉ ĐỌC
 * - PROCEDURE = "quy trình công việc" → thực hiện nhiều bước GHI,
 *   có thể kiểm soát transaction (COMMIT/ROLLBACK) bên trong
 *
 * Đó là lý do:
 * - sp_reconcile_partner_payout dùng PROCEDURE: vì nó UPDATE dữ liệu
 *   và cần ROLLBACK nếu lỗi
 * - fn_partner_performance_report dùng FUNCTION: vì nó chỉ SELECT
 *   và trả TABLE → không cần transaction control
 */
