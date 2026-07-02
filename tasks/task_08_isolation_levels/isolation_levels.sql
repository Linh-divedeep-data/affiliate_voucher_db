-- ===========================================================================
-- DDID-17 | Bài 8 — Isolation Levels & Read Phenomena
-- ===========================================================================
-- 🎯 Mục tiêu:
--    Hiểu 4 hiện tượng đọc sai lệch (Read Phenomena) khi nhiều Transaction
--    chạy song song, và cách PostgreSQL xử lý chúng qua Isolation Levels.
--
-- 📖 Cách thực hành:
--    Mở 2 Terminal (T1, T2) kết nối cùng database, chạy song song.
--    Thứ tự chạy lệnh RẤT QUAN TRỌNG — tuân thủ đúng timeline trong README.
--
-- 🗂️ Bảng sử dụng:
--    - linh_lab.promotion_program (theo dõi cột budget_limit)
--    - linh_lab.customer_voucher  (đếm số lượng bản ghi)
-- ===========================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1 — Dirty Read (Đọc Dữ Liệu Rác)
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Kiểm tra xem PostgreSQL có bị Dirty Read ở mức Isolation thấp nhất
--    (READ UNCOMMITTED) hay không.
--
-- Dirty Read = Transaction đọc được dữ liệu mà Transaction khác CHƯA COMMIT
--    → dữ liệu "rác" vì có thể bị ROLLBACK bất cứ lúc nào.

-- ─── TERMINAL 1 (TX1) ─────────────────────────────────────────────────────

-- t0: Ghi nhận giá trị gốc
SELECT program_id, program_name, budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Ghi nhớ: budget_limit = ??? (ví dụ: 50,000,000)

-- t1: Bắt đầu transaction với mức isolation THẤP NHẤT
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- t2: Cập nhật budget nhưng CHƯA COMMIT (dữ liệu "rác")
UPDATE linh_lab.promotion_program
SET    budget_limit = 999999999
WHERE  program_id = 1;

-- ⏸️  DỪNG — Chuyển sang Terminal 2 chạy t3

-- t4: ROLLBACK — hủy bỏ thay đổi (dữ liệu "rác" biến mất)
ROLLBACK;


-- ─── TERMINAL 2 (TX2) ─────────────────────────────────────────────────────

-- t3: Đọc budget_limit — liệu có thấy 999,999,999 (dữ liệu rác)?
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT program_id, program_name, budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Kết quả: budget_limit = ??? (50,000,000 hay 999,999,999?)

COMMIT;

-- ─── NHẬN XÉT ────────────────────────────────────────────────────────────
-- PostgreSQL KHÔNG BAO GIỜ cho phép Dirty Read!
-- Dù set READ UNCOMMITTED, PostgreSQL tự động nâng lên READ COMMITTED.
-- Đây là đặc điểm của kiến trúc MVCC (Multi-Version Concurrency Control):
-- mỗi transaction nhìn thấy "snapshot" riêng, không thấy dữ liệu uncommitted.
--
-- → TX2 luôn thấy budget_limit = 50,000,000 (giá trị GỐC, không phải rác)


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2 — Non-Repeatable Read (Đọc Không Lặp Lại)
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Chứng minh ở mức READ COMMITTED, cùng 1 câu SELECT chạy 2 lần
--    trong cùng 1 transaction có thể trả ra kết quả KHÁC NHAU
--    (vì transaction khác đã COMMIT xen giữa).
--
-- Non-Repeatable Read = Đọc lần 1 thấy giá trị A, đọc lần 2 thấy giá trị B
--    dù CHÍNH MÌNH chưa làm gì → mất tính nhất quán trong transaction.

-- ══════════════════════════════════════════
-- Kịch bản A: READ COMMITTED (bị lỗi)
-- ══════════════════════════════════════════

-- ─── TERMINAL 1 (TX1) — READ COMMITTED ────────────────────────────────────

-- t0: Bắt đầu transaction (mặc định READ COMMITTED)
BEGIN;

-- t1: Đọc budget lần 1
SELECT program_id, budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Kết quả: budget_limit = 50,000,000 ✅

-- ⏸️  DỪNG — Chuyển sang Terminal 2 chạy t2, t3

-- t4: Đọc budget lần 2 (TRONG CÙNG transaction!)
SELECT program_id, budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Kết quả: budget_limit = 45,000,000 ⚠️ — BỊ THAY ĐỔI!
-- → Non-Repeatable Read xảy ra!

COMMIT;


-- ─── TERMINAL 2 (TX2) ─────────────────────────────────────────────────────

-- t2: Bắt đầu transaction, trừ ngân sách
BEGIN;

UPDATE linh_lab.promotion_program
SET    budget_limit = budget_limit - 5000000
WHERE  program_id = 1;

-- t3: COMMIT — thay đổi trở thành "official"
COMMIT;

-- ⏸️  Quay lại Terminal 1 chạy t4


-- ══════════════════════════════════════════
-- Kịch bản B: REPEATABLE READ (đã sửa lỗi)
-- ══════════════════════════════════════════
-- Trước khi chạy, reset budget_limit về giá trị gốc:
UPDATE linh_lab.promotion_program
SET    budget_limit = 50000000
WHERE  program_id = 1;

-- ─── TERMINAL 1 (TX1) — REPEATABLE READ ───────────────────────────────────

-- t0: Bắt đầu transaction với REPEATABLE READ
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- t1: Đọc budget lần 1
SELECT program_id, budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Kết quả: budget_limit = 50,000,000 ✅

-- ⏸️  DỪNG — Chuyển sang Terminal 2 chạy t2, t3

-- t4: Đọc budget lần 2
SELECT program_id, budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Kết quả: budget_limit = 50,000,000 ✅ — KHÔNG THAY ĐỔI!
-- → REPEATABLE READ chặn được Non-Repeatable Read!

COMMIT;


-- ─── TERMINAL 2 (TX2) — Giống Kịch Bản A ─────────────────────────────────

-- t2-t3: (giống kịch bản A — UPDATE rồi COMMIT)
BEGIN;
UPDATE linh_lab.promotion_program
SET    budget_limit = budget_limit - 5000000
WHERE  program_id = 1;
COMMIT;


-- ─── NHẬN XÉT ────────────────────────────────────────────────────────────
-- READ COMMITTED: mỗi SELECT lấy snapshot MỚI NHẤT → thấy thay đổi của TX khác
-- REPEATABLE READ: toàn bộ transaction dùng CÙNG 1 snapshot (tại thời điểm BEGIN)
--   → SELECT lần 2 vẫn thấy giá trị cũ, bất kể TX khác đã COMMIT


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 3 — Phantom Read (Đọc Bóng Ma)
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Chứng minh PostgreSQL MVCC chống được Phantom Read
--    dù chuẩn SQL nói REPEATABLE READ không bảo vệ được.
--
-- Phantom Read = Đếm lần 1 được N dòng, transaction khác INSERT thêm dòng mới
--    rồi COMMIT, đếm lần 2 thấy N+1 dòng → dòng mới "xuất hiện như bóng ma".

-- Reset dữ liệu trước khi test:
UPDATE linh_lab.promotion_program
SET    budget_limit = 50000000
WHERE  program_id = 1;

-- ─── TERMINAL 1 (TX1) — REPEATABLE READ ───────────────────────────────────

-- t0: Bắt đầu transaction
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- t1: Đếm voucher lần 1
SELECT COUNT(*) AS total_vouchers
FROM   linh_lab.customer_voucher
WHERE  voucher_id IN (
    SELECT voucher_id FROM linh_lab.voucher WHERE program_id = 1
);
-- Kết quả: total_vouchers = N (ví dụ: 3)

-- ⏸️  DỪNG — Chuyển sang Terminal 2 chạy t2, t3

-- t4: Đếm voucher lần 2 (sau khi TX2 đã INSERT + COMMIT)
SELECT COUNT(*) AS total_vouchers
FROM   linh_lab.customer_voucher
WHERE  voucher_id IN (
    SELECT voucher_id FROM linh_lab.voucher WHERE program_id = 1
);
-- Kết quả: total_vouchers = N (VẪN BẰNG lần 1!)
-- → PostgreSQL MVCC chặn được Phantom Read ở REPEATABLE READ!

COMMIT;


-- ─── TERMINAL 2 (TX2) ─────────────────────────────────────────────────────

-- t2: INSERT voucher mới cho program 1
BEGIN;

INSERT INTO linh_lab.customer_voucher
    (customer_id, voucher_id, status_id, saved_at, created_at, created_by)
VALUES
    (1, (SELECT voucher_id FROM linh_lab.voucher WHERE program_id = 1 LIMIT 1),
     1, NOW(), NOW(), 'PHANTOM_TEST');

-- t3: COMMIT — dòng mới chính thức tồn tại
COMMIT;

-- ⏸️  Quay lại Terminal 1 chạy t4


-- ─── BONUS: Phantom Read với UPDATE ──────────────────────────────────────
-- Nếu TX1 chạy UPDATE tác động lên TẤT CẢ voucher (kể cả dòng mới từ TX2),
-- PostgreSQL sẽ phát hiện conflict và có thể:
-- - Ở REPEATABLE READ: RAISE ERROR "could not serialize access"
-- - Ở SERIALIZABLE: luôn RAISE ERROR khi phát hiện write conflict

-- ─── NHẬN XÉT ────────────────────────────────────────────────────────────
-- Chuẩn SQL nói REPEATABLE READ KHÔNG chặn Phantom Read.
-- Nhưng PostgreSQL dùng MVCC (snapshot-based) → chặn được!
-- Đây là điểm MẠNH HƠN chuẩn SQL của PostgreSQL.


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 4 — Lost Update (Ghi Đè Dữ Liệu)
-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 Mục đích:
--    Mô phỏng thảm họa khi 2 transaction cùng đọc → cùng tính toán →
--    cùng ghi → 1 kết quả bị "bốc hơi" (Lost Update).
--
-- Kịch bản:
--    Budget = 10,000,000. TX1 muốn tiêu 1,000,000. TX2 muốn tiêu 2,000,000.
--    Kết quả đúng: 10,000,000 - 1,000,000 - 2,000,000 = 7,000,000
--    Kết quả sai (Lost Update): 8,000,000 (mất khoản tiêu của TX1!)

-- Reset budget trước khi test:
UPDATE linh_lab.promotion_program
SET    budget_limit = 10000000
WHERE  program_id = 1;

-- ══════════════════════════════════════════
-- Kịch bản A: READ COMMITTED (bị Lost Update!)
-- ══════════════════════════════════════════

-- ─── TERMINAL 1 (TX1) ─────────────────────────────────────────────────────

-- t0: Đọc budget hiện tại
BEGIN;
SELECT budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Kết quả: budget_limit = 10,000,000
-- App tính: new_budget = 10,000,000 - 1,000,000 = 9,000,000

-- ⏸️  DỪNG — Chuyển sang Terminal 2 chạy t1, t2

-- t3: Ghi lại giá trị đã tính (DỰA TRÊN DỮ LIỆU CŨ!)
UPDATE linh_lab.promotion_program
SET    budget_limit = 9000000    -- App tính: 10M - 1M = 9M
WHERE  program_id = 1;

-- t4: COMMIT
COMMIT;

-- Kiểm tra: budget_limit = 9,000,000 ← SAI! Phải là 7,000,000!
-- → Khoản tiêu 2,000,000 của TX2 bị GHI ĐÈ (Lost Update)!


-- ─── TERMINAL 2 (TX2) ─────────────────────────────────────────────────────

-- t1: Đọc budget (CÙNG THỜI ĐIỂM với TX1, cùng thấy 10M)
BEGIN;
SELECT budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Kết quả: budget_limit = 10,000,000
-- App tính: new_budget = 10,000,000 - 2,000,000 = 8,000,000

-- t2: Ghi lại giá trị
UPDATE linh_lab.promotion_program
SET    budget_limit = 8000000    -- App tính: 10M - 2M = 8M
WHERE  program_id = 1;
COMMIT;

-- ⏸️  Quay lại Terminal 1 chạy t3, t4


-- ══════════════════════════════════════════
-- Kịch bản B: SERIALIZABLE (PostgreSQL chặn Lost Update)
-- ══════════════════════════════════════════

-- Reset budget:
UPDATE linh_lab.promotion_program
SET    budget_limit = 10000000
WHERE  program_id = 1;

-- ─── TERMINAL 1 (TX1) — SERIALIZABLE ──────────────────────────────────────

-- t0: Đọc budget
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;
-- Kết quả: 10,000,000

-- ⏸️  DỪNG — Chuyển sang Terminal 2

-- t3: Ghi lại
UPDATE linh_lab.promotion_program
SET    budget_limit = 9000000
WHERE  program_id = 1;
-- ❌ ERROR: could not serialize access due to concurrent update
-- PostgreSQL phát hiện conflict → BẮN LỖI → bảo vệ dữ liệu!

ROLLBACK;  -- Phải retry transaction


-- ─── TERMINAL 2 (TX2) — SERIALIZABLE ──────────────────────────────────────

-- t1-t2: (giống kịch bản A nhưng dùng SERIALIZABLE)
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT budget_limit
FROM   linh_lab.promotion_program
WHERE  program_id = 1;

UPDATE linh_lab.promotion_program
SET    budget_limit = 8000000
WHERE  program_id = 1;
COMMIT;


-- ─── CÁCH SỬA ĐÚNG (không cần SERIALIZABLE) ─────────────────────────────
-- Dùng atomic UPDATE thay vì "đọc → tính → ghi":
UPDATE linh_lab.promotion_program
SET    budget_limit = budget_limit - 1000000   -- Atomic!
WHERE  program_id = 1;
-- PostgreSQL tự xử lý concurrency → KHÔNG BAO GIỜ bị Lost Update.


-- ═══════════════════════════════════════════════════════════════════════════
-- TỔNG KẾT: ISOLATION LEVELS trong PostgreSQL
-- ═══════════════════════════════════════════════════════════════════════════
/*
 * ┌────────────────────┬──────────┬────────────────────┬──────────────┬─────────────┐
 * │ Isolation Level    │ Dirty    │ Non-Repeatable     │ Phantom      │ Lost        │
 * │                    │ Read     │ Read               │ Read         │ Update      │
 * ├────────────────────┼──────────┼────────────────────┼──────────────┼─────────────┤
 * │ READ UNCOMMITTED * │ ❌ Chặn  │ ⚠️ Cho phép        │ ⚠️ Cho phép  │ ⚠️ Cho phép │
 * │ READ COMMITTED     │ ❌ Chặn  │ ⚠️ Cho phép        │ ⚠️ Cho phép  │ ⚠️ Cho phép │
 * │ REPEATABLE READ    │ ❌ Chặn  │ ❌ Chặn            │ ❌ Chặn **   │ ⚠️ Cho phép │
 * │ SERIALIZABLE       │ ❌ Chặn  │ ❌ Chặn            │ ❌ Chặn      │ ❌ Chặn     │
 * └────────────────────┴──────────┴────────────────────┴──────────────┴─────────────┘
 *
 * *  PostgreSQL tự nâng READ UNCOMMITTED → READ COMMITTED (MVCC)
 * ** PostgreSQL chặn Phantom Read ở REPEATABLE READ nhờ MVCC snapshot
 *    (mạnh hơn chuẩn SQL yêu cầu)
 *
 * Best Practice:
 * - Hầu hết trường hợp: READ COMMITTED (mặc định) + atomic UPDATE là đủ
 * - Báo cáo tài chính cần consistency: REPEATABLE READ
 * - Quy trình nghiệp vụ quan trọng, chống Lost Update: SERIALIZABLE
 *   (nhưng phải handle retry khi bị serialization error)
 */
