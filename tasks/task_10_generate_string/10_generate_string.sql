-- ============================================================================
-- 📘 TASK 10 — Generate WHERE Clause String from Config Table
-- ============================================================================
-- Ticket: DDID-19
-- Mục tiêu: Viết function tự động sinh điều kiện WHERE từ bảng cấu hình RLS.
-- ============================================================================

-- ============================================================================
-- 🧹 CLEANUP (Chạy khi muốn reset toàn bộ)
-- ============================================================================
-- DROP FUNCTION IF EXISTS linh_lab.fn_generate_where_clause(VARCHAR, VARCHAR);
-- DROP TABLE IF EXISTS linh_lab.t_config_rls;
-- DROP TABLE IF EXISTS linh_lab."Product";
-- DROP TABLE IF EXISTS linh_lab."Vendor";
-- DROP TABLE IF EXISTS linh_lab."DeliveryMethod";


-- ============================================================================
-- STEP 1: Tạo bảng cấu hình T_CONFIG_RLS + Dữ liệu
-- ============================================================================

-- 1️⃣ Tạo bảng cấu hình
CREATE TABLE IF NOT EXISTS linh_lab.t_config_rls (
    user_id    VARCHAR(30),
    table_name VARCHAR(50),
    field_name VARCHAR(50),
    value      VARCHAR(255)
);

-- 2️⃣ INSERT dữ liệu cấu hình
INSERT INTO linh_lab.t_config_rls (user_id, table_name, field_name, value) VALUES
-- U03: PurchaseOrder — nhiều field, nhiều value
('U03', 'PurchaseOrder',   'VendorId',           'VS04,UK8A'),
('U03', 'PurchaseOrder',   'PlantID',            'W1,W4'),
('U03', 'PurchaseOrder',   'DeliveryMethodName', '%sea%,air%'),
('U03', 'ProductCategory', 'CategoryName',       'OLED'),

-- U31: Wildcard toàn bộ → 1=1 cho mọi bảng
('U31', '*', '*', '*'),

-- U05: PurchaseOrder wildcard → 1=1 cho PurchaseOrder
('U05', 'PurchaseOrder', '*', '*'),

-- U09: Customer — có 1 field wildcard value
('U09', 'Customer', 'PostalCityID',        '1,6,7,3'),
('U09', 'Customer', 'CustomerCategoryName', '%Suspects%,Loyal%,%Referral'),
('U09', 'Customer', 'DeliveryCityID',       '*'),

-- U15: Invoice — 1 field với LIKE
('U15', 'Invoice', 'CustomerCategoryName', '%boxes'),

-- UE1: SaleOrder + SaleOrderDetail
('UE1', 'SaleOrder',       'CustomerID', '%123'),
('UE1', 'SaleOrderDetail', 'ProductID',  '143,F35'),

-- ADV: Wildcard table nhưng field cụ thể (Advanced case)
('ADV', '*', 'DeliveryMethodName', 'Road%,%Rail'),
('ADV', '*', 'VendorId',          'VP19,UB55');

-- ✅ Kiểm tra dữ liệu
SELECT * FROM linh_lab.t_config_rls ORDER BY user_id, table_name;
-- 🖥️ Mong đợi: 16 dòng dữ liệu cấu hình


-- ============================================================================
-- STEP 2: Tạo bảng phụ cho Advanced Case (ADV)
-- ============================================================================
-- ⚠️ Dùng dấu ngoặc kép "" để giữ tên CamelCase đúng theo đề bài.
-- PostgreSQL mặc định lowercase tất cả tên nếu không có "".

-- Bảng Product — KHÔNG có VendorId, KHÔNG có DeliveryMethodName
CREATE TABLE IF NOT EXISTS linh_lab."Product" (
    "ProductID"   VARCHAR(30) PRIMARY KEY,
    "ProductName" VARCHAR(255),
    "Price"       DECIMAL(10, 2)
);

-- Bảng Vendor — CÓ cột VendorID
CREATE TABLE IF NOT EXISTS linh_lab."Vendor" (
    "VendorID"   VARCHAR(10) PRIMARY KEY,
    "VendorName" VARCHAR(255),
    "Address"    VARCHAR(500)
);

-- Bảng DeliveryMethod — CÓ cột DeliveryMethodName
CREATE TABLE IF NOT EXISTS linh_lab."DeliveryMethod" (
    "DeliveryMethodID"   VARCHAR(10) PRIMARY KEY,
    "DeliveryMethodName" VARCHAR(255)
);


-- ============================================================================
-- STEP 3: Tạo Function fn_generate_where_clause
-- ============================================================================
-- Input:  p_user_id (VARCHAR), p_table_name (VARCHAR)
-- Output: TEXT — chuỗi điều kiện WHERE
--
-- Logic xử lý (theo thứ tự ưu tiên):
-- 1. User có (TableName='*', FieldName='*') → return '1=1' (luôn luôn)
-- 2. User có (TableName=input, FieldName='*') hoặc Value='*' → return '1=1'
-- 3. User có (TableName='*', FieldName=cụ thể) → Advanced: kiểm tra cột
-- 4. User có (TableName=input, FieldName=cụ thể) → sinh điều kiện
-- 5. Không match → return '1=0'
-- ============================================================================

CREATE OR REPLACE FUNCTION linh_lab.fn_generate_where_clause(
    p_user_id   VARCHAR,
    p_table_name VARCHAR
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_result       TEXT := '';
    v_field_cond   TEXT;
    v_values       TEXT[];
    v_single_val   TEXT;
    v_like_parts   TEXT[];
    v_in_parts     TEXT[];
    v_has_match    BOOLEAN := FALSE;
    v_field_exists BOOLEAN;
    rec            RECORD;
BEGIN
    -- ===================================================================
    -- RULE 1: User có wildcard toàn bộ (TableName='*' AND FieldName='*')
    -- Ví dụ: U31 → '1=1' cho MỌI bảng
    -- ===================================================================
    IF EXISTS (
        SELECT 1 FROM linh_lab.t_config_rls
        WHERE user_id = p_user_id
          AND table_name = '*'
          AND field_name = '*'
    ) THEN
        RETURN '1=1';
    END IF;

    -- ===================================================================
    -- RULE 2: User có wildcard cho bảng cụ thể
    -- FieldName='*' hoặc Value='*' → '1=1' cho bảng đó
    -- Ví dụ: U05 + PurchaseOrder, U09 + Customer (DeliveryCityID='*')
    -- ===================================================================
    IF EXISTS (
        SELECT 1 FROM linh_lab.t_config_rls
        WHERE user_id = p_user_id
          AND table_name = p_table_name
          AND (field_name = '*' OR value = '*')
    ) THEN
        RETURN '1=1';
    END IF;

    -- ===================================================================
    -- RULE 3 & 4: Xử lý các field cụ thể
    -- Lấy cả config cho bảng cụ thể VÀ config wildcard (TableName='*')
    -- ===================================================================
    FOR rec IN
        SELECT field_name, value, table_name AS config_table
        FROM linh_lab.t_config_rls
        WHERE user_id = p_user_id
          AND field_name != '*'
          AND value != '*'
          AND (table_name = p_table_name OR table_name = '*')
        ORDER BY field_name
    LOOP
        -- =============================================================
        -- RULE 3 (Advanced): Nếu config có TableName='*',
        -- kiểm tra xem cột có tồn tại trong bảng đích không
        -- =============================================================
        IF rec.config_table = '*' THEN
            SELECT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'linh_lab'
                  AND table_name = p_table_name
                  AND LOWER(column_name) = LOWER(rec.field_name)
            ) INTO v_field_exists;

            IF NOT v_field_exists THEN
                CONTINUE;  -- Bỏ qua field không tồn tại
            END IF;
        END IF;

        v_has_match := TRUE;

        -- =============================================================
        -- Tách values theo dấu phẩy và phân loại LIKE / IN
        -- =============================================================
        v_values := string_to_array(rec.value, ',');
        v_like_parts := ARRAY[]::TEXT[];
        v_in_parts := ARRAY[]::TEXT[];

        FOREACH v_single_val IN ARRAY v_values LOOP
            v_single_val := TRIM(v_single_val);

            IF v_single_val LIKE '%\%%' ESCAPE '\' THEN
                -- Value chứa % → dùng LIKE
                v_like_parts := array_append(
                    v_like_parts,
                    rec.field_name || ' LIKE ''' || v_single_val || ''''
                );
            ELSE
                -- Value bình thường → dùng IN
                v_in_parts := array_append(v_in_parts, '''' || v_single_val || '''');
            END IF;
        END LOOP;

        -- =============================================================
        -- Ghép điều kiện cho field này
        -- =============================================================
        v_field_cond := '';

        -- Nếu có cả LIKE và IN
        IF array_length(v_like_parts, 1) > 0 AND array_length(v_in_parts, 1) > 0 THEN
            v_field_cond := '(' || array_to_string(v_like_parts, ' OR ') ||
                            ' OR ' || rec.field_name || ' IN (' ||
                            array_to_string(v_in_parts, ',') || '))';

        -- Chỉ có LIKE
        ELSIF array_length(v_like_parts, 1) > 0 THEN
            IF array_length(v_like_parts, 1) = 1 THEN
                v_field_cond := v_like_parts[1];
            ELSE
                v_field_cond := '(' || array_to_string(v_like_parts, ' OR ') || ')';
            END IF;

        -- Chỉ có IN
        ELSIF array_length(v_in_parts, 1) > 0 THEN
            IF array_length(v_in_parts, 1) = 1 THEN
                -- 1 giá trị → dùng = thay vì IN
                v_field_cond := rec.field_name || ' = ' || v_in_parts[1];
            ELSE
                v_field_cond := rec.field_name || ' IN (' ||
                                array_to_string(v_in_parts, ',') || ')';
            END IF;
        END IF;

        -- Ghép vào kết quả chung (AND giữa các field)
        IF v_field_cond != '' THEN
            IF v_result != '' THEN
                v_result := v_result || ' AND ';
            END IF;
            v_result := v_result || v_field_cond;
        END IF;
    END LOOP;

    -- ===================================================================
    -- RULE 5: Không có match → return '1=0'
    -- ===================================================================
    IF NOT v_has_match THEN
        RETURN '1=0';
    END IF;

    RETURN v_result;
END;
$$;


-- ============================================================================
-- STEP 4: Test tất cả các case
-- ============================================================================

-- ────────────────────────────────────────────────────────────
-- TEST 1: U31 — Wildcard toàn bộ → '1=1'
-- ────────────────────────────────────────────────────────────
SELECT 'U31 + BấtKỳBảngNào' AS test_case,
       linh_lab.fn_generate_where_clause('U31', 'BấtKỳBảngNào') AS result;
-- 🖥️ Mong đợi: 1=1

-- ────────────────────────────────────────────────────────────
-- TEST 2: U05 — PurchaseOrder wildcard → '1=1'
-- ────────────────────────────────────────────────────────────
SELECT 'U05 + PurchaseOrder' AS test_case,
       linh_lab.fn_generate_where_clause('U05', 'PurchaseOrder') AS result;
-- 🖥️ Mong đợi: 1=1

-- ────────────────────────────────────────────────────────────
-- TEST 3: U05 — Bảng khác (không có config) → '1=0'
-- ────────────────────────────────────────────────────────────
SELECT 'U05 + Invoice' AS test_case,
       linh_lab.fn_generate_where_clause('U05', 'Invoice') AS result;
-- 🖥️ Mong đợi: 1=0

-- ────────────────────────────────────────────────────────────
-- TEST 4: U09 — Customer có DeliveryCityID='*' → '1=1'
-- ────────────────────────────────────────────────────────────
SELECT 'U09 + Customer' AS test_case,
       linh_lab.fn_generate_where_clause('U09', 'Customer') AS result;
-- 🖥️ Mong đợi: 1=1 (vì DeliveryCityID có Value='*')

-- ────────────────────────────────────────────────────────────
-- TEST 5: UE1 — SaleOrder → LIKE
-- ────────────────────────────────────────────────────────────
SELECT 'UE1 + SaleOrder' AS test_case,
       linh_lab.fn_generate_where_clause('UE1', 'SaleOrder') AS result;
-- 🖥️ Mong đợi: CustomerID LIKE '%123'

-- ────────────────────────────────────────────────────────────
-- TEST 6: UE1 — SaleOrderDetail → IN
-- ────────────────────────────────────────────────────────────
SELECT 'UE1 + SaleOrderDetail' AS test_case,
       linh_lab.fn_generate_where_clause('UE1', 'SaleOrderDetail') AS result;
-- 🖥️ Mong đợi: ProductID IN ('143','F35')

-- ────────────────────────────────────────────────────────────
-- TEST 7: U03 — PurchaseOrder → nhiều field AND
-- ────────────────────────────────────────────────────────────
SELECT 'U03 + PurchaseOrder' AS test_case,
       linh_lab.fn_generate_where_clause('U03', 'PurchaseOrder') AS result;
-- 🖥️ Mong đợi: (DeliveryMethodName LIKE '%sea%' OR DeliveryMethodName LIKE 'air%')
--              AND PlantID IN ('W1','W4')
--              AND VendorId IN ('VS04','UK8A')

-- ────────────────────────────────────────────────────────────
-- TEST 8: U03 — ProductCategory → 1 value, dùng =
-- ────────────────────────────────────────────────────────────
SELECT 'U03 + ProductCategory' AS test_case,
       linh_lab.fn_generate_where_clause('U03', 'ProductCategory') AS result;
-- 🖥️ Mong đợi: CategoryName = 'OLED'

-- ────────────────────────────────────────────────────────────
-- TEST 9: U15 — Invoice → LIKE
-- ────────────────────────────────────────────────────────────
SELECT 'U15 + Invoice' AS test_case,
       linh_lab.fn_generate_where_clause('U15', 'Invoice') AS result;
-- 🖥️ Mong đợi: CustomerCategoryName LIKE '%boxes'

-- ────────────────────────────────────────────────────────────
-- TEST 10: User không tồn tại → '1=0'
-- ────────────────────────────────────────────────────────────
SELECT 'XXX + AnyTable' AS test_case,
       linh_lab.fn_generate_where_clause('XXX', 'AnyTable') AS result;
-- 🖥️ Mong đợi: 1=0

-- ────────────────────────────────────────────────────────────
-- TEST 11: U09 — Bảng không có config → '1=0'
-- ────────────────────────────────────────────────────────────
SELECT 'U09 + Invoice' AS test_case,
       linh_lab.fn_generate_where_clause('U09', 'Invoice') AS result;
-- 🖥️ Mong đợi: 1=0

-- ────────────────────────────────────────────────────────────
-- TEST 12: U09 — CustomerCategoryName LIKE (nhiều pattern)
-- ────────────────────────────────────────────────────────────
-- Lưu ý: U09 + Customer sẽ trả '1=1' vì DeliveryCityID='*'
-- Nên test này chỉ để xác nhận behavior

-- ============================================================================
-- STEP 5: Advanced Tests — ADV User
-- ============================================================================
-- ADV có TableName='*' nhưng FieldName cụ thể.
-- Function phải kiểm tra xem cột có tồn tại trong bảng đích không.

-- ────────────────────────────────────────────────────────────
-- TEST ADV-1: DeliveryMethod — CÓ cột DeliveryMethodName
-- ────────────────────────────────────────────────────────────
SELECT 'ADV + DeliveryMethod' AS test_case,
       linh_lab.fn_generate_where_clause('ADV', 'DeliveryMethod') AS result;
-- 🖥️ Mong đợi: (DeliveryMethodName LIKE 'Road%' OR DeliveryMethodName LIKE '%Rail')

-- ────────────────────────────────────────────────────────────
-- TEST ADV-2: Vendor — CÓ cột VendorID
-- ────────────────────────────────────────────────────────────
SELECT 'ADV + Vendor' AS test_case,
       linh_lab.fn_generate_where_clause('ADV', 'Vendor') AS result;
-- 🖥️ Mong đợi: VendorId IN ('VP19','UB55')

-- ────────────────────────────────────────────────────────────
-- TEST ADV-3: Product — KHÔNG có DeliveryMethodName, KHÔNG có VendorId
-- ────────────────────────────────────────────────────────────
SELECT 'ADV + Product' AS test_case,
       linh_lab.fn_generate_where_clause('ADV', 'Product') AS result;
-- 🖥️ Mong đợi: 1=0


-- ============================================================================
-- 📊 Chạy tất cả test 1 lần (Summary Table)
-- ============================================================================
SELECT test_case, result
FROM (
    VALUES
        ('U31 + AnyTable',      linh_lab.fn_generate_where_clause('U31', 'AnyTable')),
        ('U05 + PurchaseOrder', linh_lab.fn_generate_where_clause('U05', 'PurchaseOrder')),
        ('U05 + Invoice',       linh_lab.fn_generate_where_clause('U05', 'Invoice')),
        ('U09 + Customer',      linh_lab.fn_generate_where_clause('U09', 'Customer')),
        ('UE1 + SaleOrder',     linh_lab.fn_generate_where_clause('UE1', 'SaleOrder')),
        ('UE1 + SaleOrderDetail', linh_lab.fn_generate_where_clause('UE1', 'SaleOrderDetail')),
        ('U03 + PurchaseOrder', linh_lab.fn_generate_where_clause('U03', 'PurchaseOrder')),
        ('U03 + ProductCategory', linh_lab.fn_generate_where_clause('U03', 'ProductCategory')),
        ('U15 + Invoice',       linh_lab.fn_generate_where_clause('U15', 'Invoice')),
        ('XXX + AnyTable',      linh_lab.fn_generate_where_clause('XXX', 'AnyTable')),
        ('U09 + Invoice',       linh_lab.fn_generate_where_clause('U09', 'Invoice')),
        ('ADV + DeliveryMethod', linh_lab.fn_generate_where_clause('ADV', 'DeliveryMethod')),
        ('ADV + Vendor',        linh_lab.fn_generate_where_clause('ADV', 'Vendor')),
        ('ADV + Product',       linh_lab.fn_generate_where_clause('ADV', 'Product'))
) AS t(test_case, result);
