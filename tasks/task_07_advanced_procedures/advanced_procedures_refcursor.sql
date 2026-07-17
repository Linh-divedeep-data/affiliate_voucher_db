-- ===========================================================================
-- Bài 7 (BONUS) — REFCURSOR: Cách Thay Thế cho RETURNS TABLE
-- ===========================================================================
--
-- 📖 REFCURSOR LÀ GÌ?
-- ===========================================================================
--
-- REFCURSOR (Reference Cursor) là một "con trỏ" trỏ tới kết quả của một
-- câu query. Thay vì trả về TOÀN BỘ kết quả 1 lần như RETURNS TABLE,
-- REFCURSOR cho phép caller "lướt" qua kết quả từng dòng hoặc từng batch.
--
-- Hình dung: RETURNS TABLE = đổ hết nước vào ly rồi đưa cho khách
--            REFCURSOR     = mở vòi nước, khách tự hứng bao nhiêu tùy ý
--
--
-- 🎯 TẠI SAO DÙNG REFCURSOR?
-- ===========================================================================
--
-- 1. TIẾT KIỆM BỘ NHỚ (Memory Efficiency):
--    Khi query trả về 10 triệu dòng, RETURNS TABLE load TOÀN BỘ vào RAM
--    trước khi gửi cho caller → có thể Out Of Memory.
--    REFCURSOR chỉ load N dòng mỗi lần FETCH → bộ nhớ ổn định.
--
-- 2. STREAMING / PAGINATION (Phân trang hiệu quả):
--    LIMIT/OFFSET phải chạy lại toàn bộ query mỗi lần lấy trang tiếp.
--    REFCURSOR giữ "vị trí đọc" → FETCH tiếp không cần re-execute query.
--
-- 3. NHIỀU RESULT SET (Multiple Result Sets):
--    1 function có thể mở NHIỀU cursor khác nhau → trả về nhiều bảng kết quả
--    cùng lúc. RETURNS TABLE chỉ trả được 1 bảng.
--
-- 4. ORACLE MIGRATION (Di cư từ Oracle):
--    Oracle PL/SQL dùng SYS_REFCURSOR rất phổ biến. PostgreSQL REFCURSOR
--    tương thích → dễ migrate code Oracle sang PostgreSQL.
--
--
-- ⚠️ HẠN CHẾ CỦA REFCURSOR:
-- ===========================================================================
--
-- 1. BẮT BUỘC chạy trong transaction block (BEGIN...COMMIT)
-- 2. KHÔNG dùng được trong JOIN, CTE, subquery như RETURNS TABLE
-- 3. Code phức tạp hơn (3 bước: SELECT fn → FETCH → COMMIT)
-- 4. Nếu quên COMMIT → cursor "treo" → giữ lock trên bảng
--
--
-- 📊 SO SÁNH NHANH:
--
--    ┌────────────────────────┬───────────────────────────────────────────┐
--    │ RETURNS TABLE          │ REFCURSOR                                │
--    ├────────────────────────┼───────────────────────────────────────────┤
--    │ SELECT * FROM fn(...)  │ BEGIN; SELECT fn(); FETCH ALL; COMMIT;   │
--    │ Load hết vào RAM       │ Stream từng batch (FETCH N)              │
--    │ Composable (JOIN/CTE)  │ KHÔNG composable                        │
--    │ 1 result set           │ Nhiều result set                         │
--    │ Đơn giản               │ Phức tạp hơn                             │
--    │ API / Dashboard        │ ETL batch / Data Export / Oracle migrate │
--    └────────────────────────┴───────────────────────────────────────────┘
--
-- 🗂️ Bảng sử dụng: (giống file advanced_procedures.sql)
--    - linh_lab.partner, linh_lab.partner_click
--    - linh_lab.promotion_program, linh_lab.budget_transaction
-- ===========================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- FUNCTION 1 — Partner Performance (REFCURSOR version)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- 🎯 Mục đích:
--    Viết lại fn_partner_performance_report bằng REFCURSOR.
--    Cùng logic query, khác cách trả kết quả.
--
-- 📝 GIẢI THÍCH CÚ PHÁP TỪNG DÒNG:
--
--    CREATE OR REPLACE FUNCTION ... (
--        p_cursor_name REFCURSOR DEFAULT 'partner_perf_cursor'
--                      ─────────           ──────────────────
--                      Kiểu dữ liệu       Tên cursor mặc định
--                      "con trỏ"           (caller có thể đổi tên)
--    )
--    RETURNS REFCURSOR       ← Trả về tên cursor (không phải TABLE)
--    LANGUAGE plpgsql        ← BẮT BUỘC dùng plpgsql (không dùng sql được)
--                              vì cần logic OPEN ... FOR
--
--    OPEN p_cursor_name FOR  ← "Mở con trỏ" — gắn cursor với câu query
--        SELECT ...          ← Query CHƯA chạy ở bước này, chỉ "chuẩn bị"
--                              Query thực thi khi caller gọi FETCH
--
--    RETURN p_cursor_name;   ← Trả tên cursor cho caller
--                              Caller dùng tên này để FETCH kết quả

CREATE OR REPLACE FUNCTION linh_lab.fn_partner_performance_cursor(
    p_start_date   TIMESTAMP,                               -- Ngày bắt đầu lọc click
    p_end_date     TIMESTAMP,                               -- Ngày kết thúc lọc click
    p_partner_ids  BIGINT[] DEFAULT NULL,                    -- Mảng partner ID (NULL = tất cả)
    p_cursor_name  REFCURSOR DEFAULT 'partner_perf_cursor'   -- Tên cursor trả về
)
RETURNS REFCURSOR       -- Kiểu trả về: con trỏ tham chiếu (không phải TABLE)
LANGUAGE plpgsql        -- Bắt buộc plpgsql vì cần OPEN ... FOR
AS $$
BEGIN
    -- ─────────────────────────────────────────────────────────────────
    -- OPEN cursor: "mở vòi nước" — gắn query vào cursor
    -- Ở bước này query CHƯA thực thi. Nó chỉ được "chuẩn bị" (prepared).
    -- Query sẽ chạy khi caller gọi FETCH lần đầu tiên.
    -- ─────────────────────────────────────────────────────────────────
    OPEN p_cursor_name FOR
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

    -- ─────────────────────────────────────────────────────────────────
    -- RETURN cursor name: trả "tên vòi nước" cho caller
    -- Caller sẽ dùng tên này để FETCH: FETCH ALL FROM partner_perf_cursor;
    -- ─────────────────────────────────────────────────────────────────
    RETURN p_cursor_name;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- FUNCTION 2 — Program Budget Usage (REFCURSOR version)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- 🎯 Mục đích:
--    Viết lại fn_program_budget_usage bằng REFCURSOR.
--    Tính ngân sách theo Double-Entry Ledger, streaming qua cursor.

CREATE OR REPLACE FUNCTION linh_lab.fn_program_budget_cursor(
    p_status_id    BIGINT   DEFAULT NULL,                   -- Lọc theo trạng thái (NULL = tất cả)
    p_program_ids  BIGINT[] DEFAULT NULL,                   -- Lọc theo mảng program ID
    p_cursor_name  REFCURSOR DEFAULT 'budget_cursor'        -- Tên cursor trả về
)
RETURNS REFCURSOR
LANGUAGE plpgsql
AS $$
BEGIN
    OPEN p_cursor_name FOR
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

    RETURN p_cursor_name;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- KIỂM THỬ REFCURSOR — HƯỚNG DẪN CHI TIẾT
-- ═══════════════════════════════════════════════════════════════════════════
--
-- ⚠️  LUẬT VÀNG: REFCURSOR chỉ sống TRONG transaction (BEGIN...COMMIT).
--     Ngoài transaction → cursor tự động đóng → lỗi "cursor does not exist".
--
-- 📝 LUỒNG GỌI REFCURSOR (3 bước bắt buộc):
--
--     BEGIN;                                    ← Bước 1: Mở transaction
--         SELECT fn_xxx_cursor(...);            ← Bước 2: Mở cursor (query chuẩn bị)
--         FETCH ALL FROM <cursor_name>;         ← Bước 3: Lấy kết quả
--     COMMIT;                                   ← Bước 4: Đóng transaction + giải phóng cursor
--
-- 🆚 SO SÁNH VỚI RETURNS TABLE:
--
--     -- RETURNS TABLE (1 dòng duy nhất):
--     SELECT * FROM linh_lab.fn_partner_performance_report('2026-06-01', '2026-06-30');
--
--     -- REFCURSOR (3 bước):
--     BEGIN;
--         SELECT linh_lab.fn_partner_performance_cursor('2026-06-01', '2026-06-30');
--         FETCH ALL FROM partner_perf_cursor;
--     COMMIT;
--
-- 📌 DBeaver: Bôi đen TOÀN BỘ từ BEGIN đến COMMIT rồi Ctrl+Enter.
--    Nếu chạy từng dòng riêng lẻ → cursor sẽ bị đóng giữa chừng → lỗi.


-- ─────────────────────────────────────────────────────────────────────────
-- Test 1: FETCH ALL — Lấy toàn bộ kết quả (giống RETURNS TABLE)
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Trường hợp đơn giản nhất — lấy hết 1 lần.
--    Kết quả giống hệt SELECT * FROM fn_partner_performance_report(...)
BEGIN;
    -- Mở cursor — query được "chuẩn bị" nhưng CHƯA chạy
    SELECT linh_lab.fn_partner_performance_cursor(
        '2026-06-01'::TIMESTAMP,
        '2026-06-30'::TIMESTAMP
    );

    -- FETCH ALL — lấy TẤT CẢ dòng → query chạy ở đây
    FETCH ALL FROM partner_perf_cursor;
COMMIT;
-- Kết quả mong đợi: bảng giống hệt RETURNS TABLE version


-- ─────────────────────────────────────────────────────────────────────────
-- Test 2: FETCH ALL với Array Filter
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Xác minh BIGINT[] filter vẫn hoạt động đúng trong REFCURSOR.
BEGIN;
    SELECT linh_lab.fn_partner_performance_cursor(
        '2026-06-01'::TIMESTAMP,
        '2026-06-30'::TIMESTAMP,
        ARRAY[1, 2]::BIGINT[]           -- Chỉ partner ID 1 và 2
    );
    FETCH ALL FROM partner_perf_cursor;
COMMIT;


-- ─────────────────────────────────────────────────────────────────────────
-- Test 3: FETCH N — Streaming từng batch (Pagination Pattern)
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Mô phỏng cách backend lấy dữ liệu từng "trang".
--    Đây là LÝ DO CHÍNH dùng REFCURSOR — không load hết vào RAM.
--
-- Ví dụ thực tế: ETL job export 10 triệu click → FETCH 10000 mỗi lần
--    → xử lý batch → FETCH 10000 tiếp → cho đến khi hết.
BEGIN;
    SELECT linh_lab.fn_partner_performance_cursor(
        '2026-06-01'::TIMESTAMP,
        '2026-06-30'::TIMESTAMP
    );

    -- Batch 1: Lấy 2 dòng đầu tiên
    FETCH 2 FROM partner_perf_cursor;

    -- Batch 2: Cursor TỰ ĐỘNG nhớ vị trí → lấy 2 dòng TIẾP THEO
    FETCH 2 FROM partner_perf_cursor;

    -- MOVE: Bỏ qua N dòng mà KHÔNG trả kết quả
    -- (hữu ích khi muốn skip nhanh)
    -- MOVE 5 FROM partner_perf_cursor;

    -- Batch cuối: Lấy phần còn lại
    FETCH ALL FROM partner_perf_cursor;
COMMIT;


-- ─────────────────────────────────────────────────────────────────────────
-- Test 4: Budget Cursor — Tất cả chương trình
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Xác minh fn_program_budget_cursor hoạt động đúng.
BEGIN;
    SELECT linh_lab.fn_program_budget_cursor();
    FETCH ALL FROM budget_cursor;
COMMIT;


-- ─────────────────────────────────────────────────────────────────────────
-- Test 5: Budget Cursor — Lọc theo program_ids
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
    SELECT linh_lab.fn_program_budget_cursor(NULL, ARRAY[1, 2]::BIGINT[]);
    FETCH ALL FROM budget_cursor;
COMMIT;


-- ─────────────────────────────────────────────────────────────────────────
-- Test 6: Custom Cursor Name
-- ─────────────────────────────────────────────────────────────────────────
-- 🎯 Mục đích: Chứng minh caller có thể TỰ ĐẶT TÊN cursor.
--    Hữu ích khi mở NHIỀU cursor cùng lúc trong 1 transaction.
BEGIN;
    -- Đặt tên cursor tùy ý thay vì dùng tên mặc định
    SELECT linh_lab.fn_partner_performance_cursor(
        '2026-06-01'::TIMESTAMP,
        '2026-06-30'::TIMESTAMP,
        NULL,
        'my_custom_cursor'              -- Tên tùy chọn
    );
    FETCH ALL FROM my_custom_cursor;    -- Dùng đúng tên đã đặt
COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════
-- CÁC LỆNH FETCH — TỔNG HỢP CÚ PHÁP
-- ═══════════════════════════════════════════════════════════════════════════
/*
 * ┌──────────────────────────────────────┬────────────────────────────────────┐
 * │ Lệnh                                │ Ý nghĩa                           │
 * ├──────────────────────────────────────┼────────────────────────────────────┤
 * │ FETCH ALL FROM cursor_name;         │ Lấy TẤT CẢ dòng còn lại          │
 * │ FETCH 10 FROM cursor_name;          │ Lấy 10 dòng tiếp theo             │
 * │ FETCH NEXT FROM cursor_name;        │ Lấy 1 dòng tiếp theo              │
 * │ FETCH FIRST FROM cursor_name;       │ Quay về dòng đầu tiên             │
 * │ FETCH LAST FROM cursor_name;        │ Nhảy tới dòng cuối cùng           │
 * │ FETCH PRIOR FROM cursor_name;       │ Lùi về dòng trước đó              │
 * │ FETCH ABSOLUTE 5 FROM cursor_name;  │ Nhảy tới dòng thứ 5               │
 * │ FETCH RELATIVE -3 FROM cursor_name; │ Lùi 3 dòng từ vị trí hiện tại     │
 * │ MOVE 5 FROM cursor_name;            │ Bỏ qua 5 dòng (không trả data)    │
 * │ CLOSE cursor_name;                  │ Đóng cursor thủ công               │
 * └──────────────────────────────────────┴────────────────────────────────────┘
 *
 * Lưu ý: FETCH FIRST/LAST/PRIOR/ABSOLUTE/RELATIVE chỉ hoạt động với
 *         SCROLL cursor (DECLARE ... SCROLL CURSOR FOR ...).
 *         Cursor mặc định là NO SCROLL — chỉ đi tiến, không lùi.
 */


-- ═══════════════════════════════════════════════════════════════════════════
-- SO SÁNH TỔNG HỢP: RETURNS TABLE vs REFCURSOR
-- ═══════════════════════════════════════════════════════════════════════════
/*
 * ┌─────────────────────┬──────────────────────────┬──────────────────────────┐
 * │ Tiêu chí            │ RETURNS TABLE            │ REFCURSOR                │
 * ├─────────────────────┼──────────────────────────┼──────────────────────────┤
 * │ Cú pháp gọi         │ SELECT * FROM fn(...)    │ BEGIN; SELECT fn(...);   │
 * │                     │ (1 dòng)                 │ FETCH ALL; COMMIT;       │
 * │                     │                          │ (3-4 dòng)               │
 * ├─────────────────────┼──────────────────────────┼──────────────────────────┤
 * │ Yêu cầu transaction │ Không bắt buộc           │ BẮT BUỘC trong BEGIN..   │
 * │                     │                          │ COMMIT                   │
 * ├─────────────────────┼──────────────────────────┼──────────────────────────┤
 * │ Bộ nhớ              │ Load TOÀN BỘ vào RAM     │ Stream từng batch        │
 * │                     │ trước khi trả về caller  │ qua FETCH N              │
 * ├─────────────────────┼──────────────────────────┼──────────────────────────┤
 * │ Nhiều result set    │ KHÔNG hỗ trợ             │ 1 function có thể trả    │
 * │                     │                          │ NHIỀU cursor khác nhau   │
 * ├─────────────────────┼──────────────────────────┼──────────────────────────┤
 * │ Composable          │ Dùng trong JOIN, CTE,    │ KHÔNG dùng được trong    │
 * │ (kết hợp được)      │ WHERE EXISTS, subquery   │ JOIN/CTE/subquery        │
 * ├─────────────────────┼──────────────────────────┼──────────────────────────┤
 * │ Pagination          │ LIMIT/OFFSET             │ FETCH N — hiệu quả hơn  │
 * │                     │ (re-execute query)       │ (cursor giữ vị trí)      │
 * ├─────────────────────┼──────────────────────────┼──────────────────────────┤
 * │ LANGUAGE             │ sql hoặc plpgsql         │ Chỉ plpgsql              │
 * ├─────────────────────┼──────────────────────────┼──────────────────────────┤
 * │ Best for            │ API endpoint, dashboard, │ ETL batch processing,    │
 * │                     │ báo cáo kết quả nhỏ      │ data export hàng triệu   │
 * │                     │                          │ dòng, Oracle migration   │
 * └─────────────────────┴──────────────────────────┴──────────────────────────┘
 *
 * 📌 Kết luận:
 *    - 90% trường hợp → dùng RETURNS TABLE (đơn giản, composable, đủ dùng)
 *    - 10% trường hợp → dùng REFCURSOR khi:
 *      ✅ Kết quả rất lớn (>1 triệu dòng) cần streaming
 *      ✅ Cần trả nhiều result set từ 1 function
 *      ✅ Migrate code từ Oracle PL/SQL sang PostgreSQL
 *      ✅ Backend cần pagination hiệu quả (FETCH N thay vì LIMIT/OFFSET)
 */
