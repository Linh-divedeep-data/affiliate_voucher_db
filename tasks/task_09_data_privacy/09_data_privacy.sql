-- ============================================================================
-- 📘 TASK 09 — Data Privacy: Row-Level Security (RLS) & Column-Level Security (CLS)
-- ============================================================================
-- Mục tiêu: Bảo vệ dữ liệu nhạy cảm (PII) bằng CLS và phân quyền dữ liệu
--           theo vùng miền bằng RLS trong PostgreSQL.
-- ============================================================================

-- ============================================================================
-- 🧹 CLEANUP (Chạy khi muốn reset toàn bộ)
-- ============================================================================
-- Chạy phần này nếu muốn xóa sạch và làm lại từ đầu.
-- Nếu chạy lần đầu → bỏ qua phần này.

-- DROP POLICY IF EXISTS policy_region_select ON linh_lab.customer_profiles;
-- DROP POLICY IF EXISTS policy_region_insert ON linh_lab.customer_profiles;
-- DROP FUNCTION IF EXISTS linh_lab.fn_get_customer_profiles(VARCHAR);
-- DROP TABLE IF EXISTS linh_lab.user_region_mapping;
-- DROP TABLE IF EXISTS linh_lab.customer_profiles;
-- REVOKE ALL ON SCHEMA linh_lab FROM da_north, da_south;
-- DROP ROLE IF EXISTS da_north;
-- DROP ROLE IF EXISTS da_south;


-- ============================================================================
-- STEP 1: Chuẩn bị Role & Data (Setup)
-- ============================================================================
-- Mục tiêu: Tạo môi trường giả lập với các User có vai trò khác nhau.
-- ============================================================================

-- 1️⃣ Tạo bảng customer_profiles
CREATE TABLE IF NOT EXISTS linh_lab.customer_profiles (
    profile_id   SERIAL PRIMARY KEY,
    full_name    VARCHAR(100) NOT NULL,
    email        VARCHAR(150) NOT NULL,        -- 🔒 Dữ liệu PII
    phone_number VARCHAR(20)  NOT NULL,        -- 🔒 Dữ liệu PII
    region       VARCHAR(10)  NOT NULL         -- Giá trị: 'NORTH', 'SOUTH', 'CENTRAL'
        CHECK (region IN ('NORTH', 'SOUTH', 'CENTRAL'))
);

-- 2️⃣ INSERT 45 dòng dữ liệu mẫu (15 dòng mỗi vùng)
INSERT INTO linh_lab.customer_profiles (full_name, email, phone_number, region) VALUES
-- === NORTH (15 khách hàng miền Bắc) ===
('Nguyễn Văn An',      'an.nguyen@email.com',       '0901-111-001', 'NORTH'),
('Trần Thị Bích',      'bich.tran@email.com',       '0901-111-002', 'NORTH'),
('Lê Hoàng Cường',     'cuong.le@email.com',        '0901-111-003', 'NORTH'),
('Phạm Minh Đức',      'duc.pham@email.com',        '0901-111-004', 'NORTH'),
('Hoàng Thị Hoa',      'hoa.hoang@email.com',       '0901-111-005', 'NORTH'),
('Vũ Đình Khải',       'khai.vu@email.com',         '0901-111-006', 'NORTH'),
('Đỗ Thị Lan',         'lan.do@email.com',          '0901-111-007', 'NORTH'),
('Bùi Quang Minh',     'minh.bui@email.com',        '0901-111-008', 'NORTH'),
('Ngô Thanh Nga',      'nga.ngo@email.com',         '0901-111-009', 'NORTH'),
('Dương Văn Phong',    'phong.duong@email.com',     '0901-111-010', 'NORTH'),
('Lý Thị Quỳnh',      'quynh.ly@email.com',        '0901-111-011', 'NORTH'),
('Đinh Công Sơn',      'son.dinh@email.com',        '0901-111-012', 'NORTH'),
('Trịnh Thị Thanh',    'thanh.trinh@email.com',     '0901-111-013', 'NORTH'),
('Cao Minh Tuấn',      'tuan.cao@email.com',        '0901-111-014', 'NORTH'),
('Mai Thị Uyên',       'uyen.mai@email.com',        '0901-111-015', 'NORTH'),

-- === SOUTH (15 khách hàng miền Nam) ===
('Nguyễn Thị Ánh',     'anh.nguyen.s@email.com',    '0908-222-001', 'SOUTH'),
('Trần Quốc Bảo',      'bao.tran@email.com',        '0908-222-002', 'SOUTH'),
('Lê Thị Cẩm',         'cam.le@email.com',          '0908-222-003', 'SOUTH'),
('Phạm Hữu Danh',      'danh.pham@email.com',       '0908-222-004', 'SOUTH'),
('Hoàng Minh Gia',      'gia.hoang@email.com',       '0908-222-005', 'SOUTH'),
('Vũ Thị Hạnh',        'hanh.vu@email.com',         '0908-222-006', 'SOUTH'),
('Đỗ Quốc Khánh',      'khanh.do@email.com',        '0908-222-007', 'SOUTH'),
('Bùi Thị Linh',       'linh.bui@email.com',        '0908-222-008', 'SOUTH'),
('Ngô Minh Nam',        'nam.ngo@email.com',         '0908-222-009', 'SOUTH'),
('Dương Thị Oanh',      'oanh.duong@email.com',      '0908-222-010', 'SOUTH'),
('Lý Quang Phúc',       'phuc.ly@email.com',         '0908-222-011', 'SOUTH'),
('Đinh Thị Quyên',      'quyen.dinh@email.com',      '0908-222-012', 'SOUTH'),
('Trịnh Minh Sang',     'sang.trinh@email.com',      '0908-222-013', 'SOUTH'),
('Cao Thị Tâm',         'tam.cao@email.com',         '0908-222-014', 'SOUTH'),
('Mai Văn Uy',           'uy.mai@email.com',          '0908-222-015', 'SOUTH'),

-- === CENTRAL (15 khách hàng miền Trung) ===
('Nguyễn Đình Bình',    'binh.nguyen.c@email.com',   '0905-333-001', 'CENTRAL'),
('Trần Thị Diệu',       'dieu.tran@email.com',       '0905-333-002', 'CENTRAL'),
('Lê Quang Hải',         'hai.le@email.com',          '0905-333-003', 'CENTRAL'),
('Phạm Thị Kim',         'kim.pham@email.com',        '0905-333-004', 'CENTRAL'),
('Hoàng Văn Long',       'long.hoang@email.com',      '0905-333-005', 'CENTRAL'),
('Vũ Thị Mai',           'mai.vu@email.com',          '0905-333-006', 'CENTRAL'),
('Đỗ Minh Nhật',         'nhat.do@email.com',         '0905-333-007', 'CENTRAL'),
('Bùi Thị Phương',       'phuong.bui@email.com',      '0905-333-008', 'CENTRAL'),
('Ngô Quang Rin',        'rin.ngo@email.com',          '0905-333-009', 'CENTRAL'),
('Dương Thị Sen',        'sen.duong@email.com',        '0905-333-010', 'CENTRAL'),
('Lý Văn Thành',         'thanh.ly@email.com',         '0905-333-011', 'CENTRAL'),
('Đinh Thị Uyên',        'uyen.dinh@email.com',        '0905-333-012', 'CENTRAL'),
('Trịnh Quốc Việt',      'viet.trinh@email.com',       '0905-333-013', 'CENTRAL'),
('Cao Thị Xuân',          'xuan.cao@email.com',         '0905-333-014', 'CENTRAL'),
('Mai Đình Yên',          'yen.mai@email.com',          '0905-333-015', 'CENTRAL');

-- ✅ Kiểm tra: Đếm số lượng theo vùng
SELECT region, COUNT(*) AS total
FROM linh_lab.customer_profiles
GROUP BY region ORDER BY region;
-- 🖥️ Mong đợi:
-- | region  | total |
-- |---------|-------|
-- | CENTRAL |  15   |
-- | NORTH   |  15   |
-- | SOUTH   |  15   |

-- 3️⃣ Tạo 2 Role (Data Analyst)
-- da_north = Data Analyst miền Bắc
-- da_south = Data Analyst miền Nam
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'da_north') THEN
        CREATE ROLE da_north LOGIN PASSWORD 'north123';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'da_south') THEN
        CREATE ROLE da_south LOGIN PASSWORD 'south123';
    END IF;
END $$;

-- 4️⃣ Cấp quyền kết nối database + USAGE trên schema
GRANT CONNECT ON DATABASE postgres TO da_north, da_south;
GRANT USAGE ON SCHEMA linh_lab TO da_north, da_south;

-- ✅ Kiểm tra: Xem danh sách role
SELECT rolname FROM pg_roles WHERE rolname IN ('da_north', 'da_south');
-- 🖥️ Mong đợi:
-- | rolname  |
-- |----------|
-- | da_north |
-- | da_south |


-- ============================================================================
-- STEP 2: Áp dụng Column-Level Security (CLS)
-- ============================================================================
-- Mục tiêu: Data Analyst KHÔNG được xem PII (email, phone_number).
-- Chỉ được xem: profile_id, full_name, region.
-- ============================================================================

-- 1️⃣ Thu hồi TOÀN BỘ quyền SELECT trên bảng (nếu có)
REVOKE ALL ON linh_lab.customer_profiles FROM da_north, da_south;

-- 2️⃣ Cấp quyền SELECT CHỈ trên 3 cột an toàn
GRANT SELECT (profile_id, full_name, region)
ON linh_lab.customer_profiles
TO da_north, da_south;

-- ✅ Kiểm tra: Xem quyền đã cấp
SELECT grantee, privilege_type, column_name
FROM information_schema.column_privileges
WHERE table_schema = 'linh_lab'
  AND table_name = 'customer_profiles'
  AND grantee IN ('da_north', 'da_south')
ORDER BY grantee, column_name;
-- 🖥️ Mong đợi:
-- | grantee  | privilege_type | column_name |
-- |----------|----------------|-------------|
-- | da_north | SELECT         | full_name   |
-- | da_north | SELECT         | profile_id  |
-- | da_north | SELECT         | region      |
-- | da_south | SELECT         | full_name   |
-- | da_south | SELECT         | profile_id  |
-- | da_south | SELECT         | region      |

-- 3️⃣ Test: Chuyển sang role da_north
SET ROLE da_north;

-- Thử SELECT * (sẽ BỊ LỖI vì không có quyền xem email, phone_number)
SELECT * FROM linh_lab.customer_profiles;
-- 🖥️ Mong đợi LỖI:
-- ERROR: permission denied for table customer_profiles
--
-- 💡 Giải thích: SELECT * yêu cầu quyền trên TẤT CẢ cột.
-- Vì da_north KHÔNG có quyền trên cột email và phone_number
-- → PostgreSQL từ chối toàn bộ câu query.

-- 4️⃣ Test: SELECT chỉ các cột được phép (sẽ THÀNH CÔNG ✅)
SELECT profile_id, full_name, region
FROM linh_lab.customer_profiles;
-- 🖥️ Mong đợi: Bảng 45 dòng, chỉ có 3 cột (profile_id, full_name, region)
-- KHÔNG thấy email và phone_number!

-- 5️⃣ Test: Cố tình SELECT cột PII (sẽ BỊ LỖI)
SELECT profile_id, full_name, email FROM linh_lab.customer_profiles;
-- 🖥️ Mong đợi LỖI:
-- ERROR: permission denied for table customer_profiles
--
-- 💡 Giải thích: Chỉ cần 1 cột không có quyền → cả câu query bị từ chối.
-- Đây chính là Column-Level Security (CLS).

-- Quay lại Admin
RESET ROLE;


-- ============================================================================
-- STEP 3: Áp dụng Row-Level Security (RLS) — DYNAMIC FILTERING
-- ============================================================================
-- Mục tiêu: da_north chỉ thấy NORTH, da_south chỉ thấy SOUTH.
-- Dữ liệu bị "tàng hình" hoàn toàn — không lỗi, không warning.
-- Cách làm: Dynamic RLS bằng bảng Mapping (KHÔNG hardcode từng Policy).
-- ============================================================================

-- 1️⃣ Tạo bảng mapping: user → region
CREATE TABLE IF NOT EXISTS linh_lab.user_region_mapping (
    username        VARCHAR(50) PRIMARY KEY,
    assigned_region VARCHAR(10) NOT NULL
        CHECK (assigned_region IN ('NORTH', 'SOUTH', 'CENTRAL'))
);

-- 2️⃣ INSERT mapping
INSERT INTO linh_lab.user_region_mapping (username, assigned_region) VALUES
('da_north', 'NORTH'),
('da_south', 'SOUTH')
ON CONFLICT (username) DO UPDATE
SET assigned_region = EXCLUDED.assigned_region;

-- Cấp quyền SELECT cho PUBLIC (để Policy có thể đọc bảng mapping)
GRANT SELECT ON linh_lab.user_region_mapping TO PUBLIC;

-- ✅ Kiểm tra mapping
SELECT * FROM linh_lab.user_region_mapping;
-- 🖥️ Mong đợi:
-- | username | assigned_region |
-- |----------|-----------------|
-- | da_north | NORTH           |
-- | da_south | SOUTH           |

-- 3️⃣ Kích hoạt RLS trên bảng customer_profiles
ALTER TABLE linh_lab.customer_profiles ENABLE ROW LEVEL SECURITY;

-- FORCE RLS cho cả table owner (nếu không, owner/superuser sẽ bypass RLS)
-- Lưu ý: Superuser luôn bypass RLS, FORCE chỉ ảnh hưởng table owner.
ALTER TABLE linh_lab.customer_profiles FORCE ROW LEVEL SECURITY;

-- 4️⃣ Tạo MỘT Policy DUY NHẤT (Dynamic — không hardcode role)
-- Policy này áp dụng cho lệnh SELECT, cho TẤT CẢ role (TO PUBLIC)
CREATE POLICY policy_region_select
ON linh_lab.customer_profiles
FOR SELECT
TO PUBLIC
USING (
    -- Kiểm tra: region của dòng hiện tại có khớp với assigned_region
    -- của CURRENT_USER trong bảng mapping không?
    region = (
        SELECT assigned_region
        FROM linh_lab.user_region_mapping
        WHERE username = CURRENT_USER
    )
    -- Nếu user không có trong mapping → subquery trả về NULL
    -- → NULL = region → FALSE → dòng bị ẩn
    -- Superuser bypass RLS nên vẫn thấy hết
);

-- ✅ Kiểm tra Policy đã tạo
SELECT policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'customer_profiles';
-- 🖥️ Mong đợi: 1 dòng — policy_region_select, SELECT, (region = subquery)

-- 5️⃣ Test: Chuyển sang da_north → chỉ thấy NORTH
SET ROLE da_north;

SELECT profile_id, full_name, region
FROM linh_lab.customer_profiles;
-- 🖥️ Mong đợi: CHỈ 15 dòng, tất cả region = 'NORTH'
-- Dữ liệu SOUTH và CENTRAL "tàng hình" hoàn toàn — KHÔNG có lỗi!

-- Đếm để xác nhận
SELECT region, COUNT(*) AS total
FROM linh_lab.customer_profiles
GROUP BY region;
-- 🖥️ Mong đợi:
-- | region | total |
-- |--------|-------|
-- | NORTH  |  15   |
-- (chỉ có 1 dòng, không thấy SOUTH và CENTRAL)

RESET ROLE;

-- 6️⃣ Test: Chuyển sang da_south → chỉ thấy SOUTH
SET ROLE da_south;

SELECT profile_id, full_name, region
FROM linh_lab.customer_profiles;
-- 🖥️ Mong đợi: CHỈ 15 dòng, tất cả region = 'SOUTH'

SELECT region, COUNT(*) AS total
FROM linh_lab.customer_profiles
GROUP BY region;
-- 🖥️ Mong đợi:
-- | region | total |
-- |--------|-------|
-- | SOUTH  |  15   |

RESET ROLE;

-- 7️⃣ [BONUS] Policy cho INSERT — Ép user chỉ INSERT đúng vùng mình quản lý
-- Cần cấp thêm quyền INSERT cho các cột được phép
GRANT INSERT (profile_id, full_name, email, phone_number, region)
ON linh_lab.customer_profiles
TO da_north, da_south;

-- Cấp quyền sử dụng sequence (cần cho SERIAL/auto-increment)
GRANT USAGE, SELECT ON SEQUENCE linh_lab.customer_profiles_profile_id_seq
TO da_north, da_south;

CREATE POLICY policy_region_insert
ON linh_lab.customer_profiles
FOR INSERT
TO PUBLIC
WITH CHECK (
    -- Kiểm tra: region của dòng mới phải khớp với assigned_region của CURRENT_USER
    region = (
        SELECT assigned_region
        FROM linh_lab.user_region_mapping
        WHERE username = CURRENT_USER
    )
);

-- Test: da_north thử INSERT khách hàng miền Nam → BỊ LỖI
SET ROLE da_north;

INSERT INTO linh_lab.customer_profiles (full_name, email, phone_number, region)
VALUES ('Hacker Test', 'hack@test.com', '0900-000-000', 'SOUTH');
-- 🖥️ Mong đợi LỖI:
-- ERROR: new row violates row-level security policy for table "customer_profiles"
--
-- 💡 Giải thích: WITH CHECK kiểm tra region='SOUTH' nhưng da_north chỉ được
-- quản lý 'NORTH' → vi phạm policy → PostgreSQL từ chối INSERT.

-- Test: da_north INSERT khách hàng miền Bắc → THÀNH CÔNG ✅
INSERT INTO linh_lab.customer_profiles (full_name, email, phone_number, region)
VALUES ('Nguyễn Test Bắc', 'test.bac@email.com', '0901-000-999', 'NORTH');
-- 🖥️ Mong đợi: INSERT 0 1

-- Xác nhận
SELECT profile_id, full_name, region
FROM linh_lab.customer_profiles
WHERE full_name = 'Nguyễn Test Bắc';
-- 🖥️ Mong đợi: 1 dòng — Nguyễn Test Bắc, NORTH

RESET ROLE;


-- ============================================================================
-- STEP 4: SECURITY DEFINER vs SECURITY INVOKER
-- ============================================================================
-- Mục tiêu: Hiểu cơ chế phân quyền khi truy cập dữ liệu gián tiếp qua Function.
--
-- 🔑 Khái niệm quan trọng: "Effective User ID"
-- - SECURITY DEFINER: Function chạy với quyền của NGƯỜI TẠO (Admin/Owner)
--   → Effective User ID = Admin → RLS bị bypass!
-- - SECURITY INVOKER: Function chạy với quyền của NGƯỜI GỌI (User thực tế)
--   → Effective User ID = da_north → RLS được tôn trọng!
-- ============================================================================

-- 1️⃣ Tạo function SECURITY DEFINER (NGUY HIỂM!)
CREATE OR REPLACE FUNCTION linh_lab.fn_get_customer_profiles(p_region VARCHAR)
RETURNS TABLE (
    profile_id   INT,
    full_name    VARCHAR,
    region       VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER  -- ⚠️ Chạy với quyền của NGƯỜI TẠO (Admin)
AS $$
BEGIN
    RETURN QUERY
    SELECT cp.profile_id, cp.full_name, cp.region
    FROM linh_lab.customer_profiles cp
    WHERE cp.region = p_region;
END;
$$;

-- Cấp quyền EXECUTE cho da_north
GRANT EXECUTE ON FUNCTION linh_lab.fn_get_customer_profiles(VARCHAR) TO da_north;

-- 2️⃣ Test: da_north gọi hàm với tham số 'SOUTH'
SET ROLE da_north;

SELECT * FROM linh_lab.fn_get_customer_profiles('SOUTH');
-- 🖥️ Mong đợi: 15 dòng miền NAM! ⚠️ RLS BỊ XUYÊN THỦNG!
--
-- 💡 TẠI SAO?
-- Vì function dùng SECURITY DEFINER:
-- → Effective User ID = Admin (người tạo function)
-- → Admin là superuser → BYPASS RLS
-- → da_north "mượn quyền" Admin để xem dữ liệu miền Nam
--
-- Đây là lỗ hổng bảo mật nghiêm trọng!
-- Nếu Admin tạo function SECURITY DEFINER mà không cẩn thận,
-- user có thể truy cập dữ liệu không thuộc quyền hạn.

RESET ROLE;

-- 3️⃣ Sửa lại: Đổi thành SECURITY INVOKER (an toàn)
CREATE OR REPLACE FUNCTION linh_lab.fn_get_customer_profiles(p_region VARCHAR)
RETURNS TABLE (
    profile_id   INT,
    full_name    VARCHAR,
    region       VARCHAR
)
LANGUAGE plpgsql
SECURITY INVOKER  -- ✅ Chạy với quyền của NGƯỜI GỌI
AS $$
BEGIN
    RETURN QUERY
    SELECT cp.profile_id, cp.full_name, cp.region
    FROM linh_lab.customer_profiles cp
    WHERE cp.region = p_region;
END;
$$;

-- 4️⃣ Test lại: da_north gọi hàm với tham số 'SOUTH'
SET ROLE da_north;

SELECT * FROM linh_lab.fn_get_customer_profiles('SOUTH');
-- 🖥️ Mong đợi: 0 dòng! ✅ RLS ĐƯỢC TÔN TRỌNG!
--
-- 💡 TẠI SAO?
-- Vì function dùng SECURITY INVOKER:
-- → Effective User ID = da_north (người gọi function)
-- → RLS kiểm tra: da_north quản lý 'NORTH'
-- → Tham số 'SOUTH' ≠ 'NORTH' → Policy chặn → 0 kết quả
--
-- Kể cả gọi hàm với 'NORTH':
SELECT * FROM linh_lab.fn_get_customer_profiles('NORTH');
-- 🖥️ Mong đợi: 15 dòng miền BẮC ✅ (khớp với quyền của da_north)

RESET ROLE;


-- ============================================================================
-- 🤔 REFLECTION: View với SECURITY_BARRIER
-- ============================================================================
--
-- Câu hỏi: "Nếu dùng View thay thế cho function, liệu có an toàn hơn không?"
--
-- Trả lời: CÓ, nhưng cần dùng SECURITY_BARRIER.
--
-- 🔍 View thường (KHÔNG có SECURITY_BARRIER):
-- - PostgreSQL có thể "đẩy" điều kiện WHERE của user VÀO bên trong view
-- - Attacker có thể viết function tùy chỉnh trong WHERE để "leak" dữ liệu
--   trước khi RLS filter kịp chạy.
--
-- 🛡️ View có SECURITY_BARRIER:
-- - PostgreSQL ÉP chạy filter của View TRƯỚC → rồi mới chạy WHERE của user
-- - Ngăn attacker "nhìn lén" dữ liệu qua side-channel
--
-- Ví dụ:
-- CREATE VIEW linh_lab.v_safe_profiles WITH (security_barrier = true) AS
-- SELECT profile_id, full_name, region
-- FROM linh_lab.customer_profiles;
--
-- So sánh:
-- | Tiêu chí            | Function (INVOKER) | View (SECURITY_BARRIER) |
-- |---------------------|--------------------|-------------------------|
-- | RLS được tôn trọng  | ✅ Có              | ✅ Có                   |
-- | Chống side-channel  | ❌ Không            | ✅ Có                   |
-- | Linh hoạt (tham số) | ✅ Có              | ❌ Không (cố định)      |
-- | Performance         | Tốt                | Có thể chậm hơn 1 chút |
--
-- Kết luận:
-- - Nếu cần truy vấn đơn giản → Dùng View + SECURITY_BARRIER (an toàn nhất)
-- - Nếu cần tham số/logic phức tạp → Dùng Function + SECURITY INVOKER
-- - KHÔNG BAO GIỜ dùng SECURITY DEFINER cho function truy cập dữ liệu nhạy cảm
-- ============================================================================


-- ============================================================================
-- 📊 TỔNG KẾT
-- ============================================================================
--
-- CLS (Column-Level Security):
-- - REVOKE ALL → GRANT SELECT chỉ trên cột an toàn
-- - SELECT * sẽ bị lỗi nếu thiếu quyền trên bất kỳ cột nào
--
-- RLS (Row-Level Security):
-- - ENABLE ROW LEVEL SECURITY → kích hoạt
-- - CREATE POLICY ... USING (...) → filter dòng
-- - Dynamic RLS bằng bảng mapping → linh hoạt, không hardcode
-- - Dữ liệu bị "tàng hình" — không lỗi, không warning
--
-- SECURITY DEFINER vs INVOKER:
-- - DEFINER: Function chạy quyền NGƯỜI TẠO → bypass RLS → NGUY HIỂM
-- - INVOKER: Function chạy quyền NGƯỜI GỌI → tôn trọng RLS → AN TOÀN
--
-- SECURITY_BARRIER (View):
-- - Ngăn side-channel attack qua WHERE clause optimization
-- - An toàn hơn function cho truy vấn đơn giản
-- ============================================================================
