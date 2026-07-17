# 📘 Task 09 — Data Privacy: Row-Level Security (RLS) & Column-Level Security (CLS)

## Kiến thức đạt được

> Đây là những gì cần **ghi nhớ và mang theo áp dụng cho các dự án sau** — không phải bản tóm tắt việc đã làm trong task này.

| Nội dung chính | Ghi nhớ & áp dụng cho dự án sau |
|---|---|
| **Phân quyền có 2 chiều: cột và dòng** | Bất kỳ khi nào nghe "user A không được xem thông tin nhạy cảm (PII)" → cần CLS (`GRANT SELECT (cols)`); "user A chỉ được xem dữ liệu thuộc phạm vi của mình" → cần RLS (`CREATE POLICY`). Đừng cố nhét cả hai vào 1 cơ chế `GRANT`/`REVOKE` cấp bảng thông thường. |
| **Dynamic RLS qua bảng mapping, không hard-code N policy** | Dùng 1 policy tra cứu bảng mapping (`user_region_mapping`) thay vì tạo N policy tĩnh cho N vùng/role — thêm quyền mới chỉ là 1 dòng `INSERT`, không cần `ALTER`/deploy lại. |
| **RLS lớn cần index để không thành nút cổ chai** | Subquery trong policy chạy lại cho mỗi dòng kiểm tra — trên bảng lớn, phải đảm bảo cột dùng trong điều kiện policy có index phù hợp (liên hệ Task 11), nếu không RLS sẽ làm chậm mọi truy vấn của mọi user. |
| **CLS thất bại bằng lỗi, RLS thất bại bằng im lặng** | Ghi nhớ để không tốn thời gian debug sai hướng: `permission denied` là do CLS; 0 dòng bất thường (không có exception) là dấu hiệu RLS đang lọc. |
| **Không bao giờ dùng SECURITY DEFINER cho dữ liệu nhạy cảm** | Đây là quy tắc vàng mang theo mọi dự án: `SECURITY DEFINER` chạy quyền owner, có thể vô tình trở thành backdoor bypass RLS — mặc định dùng `SECURITY INVOKER`, chỉ đổi sang `DEFINER` khi có lý do rõ ràng và đã cân nhắc rủi ro. |
| **Áp dụng ngay khi có yêu cầu "phân quyền theo vai trò/vùng"** | Bất kỳ dự án nào có nhiều loại người dùng cần thấy tập con dữ liệu khác nhau — thiết kế RLS/CLS ngay từ đầu thay vì lọc bằng `WHERE` ở tầng ứng dụng (dễ bị quên/bypass khi có thêm 1 đường truy vấn mới). |

---

## 📋 Mục tiêu

Học cách bảo vệ dữ liệu nhạy cảm trong PostgreSQL bằng 3 kỹ thuật chính:

### 1. CLS — Column Level Security (Bảo mật theo cột)

**Ý nghĩa:** Ẩn một số cột nhạy cảm (PII) sao cho một số người không thấy được.

**Ví dụ:**
- Data Analyst chỉ được xem `id`, `name`, `region`
- **Không** được xem cột `email`, `phone`, `salary`

→ Dùng lệnh `GRANT` + `COLUMN` để kiểm soát quyền xem từng cột.

### 2. RLS — Row Level Security (Bảo mật theo dòng)

**Ý nghĩa:** Ẩn một số dòng dữ liệu theo quy tắc.

**Ví dụ:**
- Nhân viên miền Bắc → Chỉ thấy dữ liệu của khách hàng miền Bắc
- Nhân viên miền Nam → Chỉ thấy dữ liệu của khách hàng miền Nam
- Admin → Thấy tất cả

→ Dùng `Policy` để PostgreSQL tự động lọc dòng theo user.

### 3. SECURITY DEFINER vs INVOKER

- **SECURITY DEFINER:** Function chạy với quyền của **người tạo** function (thường là owner). Có thể **"xuyên thủng" RLS** (xem được dữ liệu bị ẩn).
- **SECURITY INVOKER** (mặc định): Function chạy với quyền của **người gọi**. Tuân thủ RLS bình thường.

→ Giúp kiểm soát function có được phép xem dữ liệu nhạy cảm hay không.

### Tóm tắt dễ nhớ

- **CLS:** Ẩn **cột** (email, phone, lương…)
- **RLS:** Ẩn **dòng** theo người dùng (miền Bắc, miền Nam…)
- **SECURITY DEFINER:** Function "siêu quyền" (có thể xem hết)

> Đây là các kỹ thuật bảo mật nâng cao rất quan trọng trong **production**, đặc biệt khi có nhiều user/role khác nhau.

## 📂 File

- [`09_data_privacy.sql`](./09_data_privacy.sql) — Toàn bộ script SQL

---

## ⚙️ Chuẩn bị trước khi bắt đầu

1. Mở DBeaver, kết nối vào database PostgreSQL
2. Mở file `09_data_privacy.sql`
3. **Quan trọng:** Chạy **TỪNG LỆNH MỘT** (bôi đen 1 lệnh → Ctrl+Enter)
4. Đảm bảo đang dùng role **Admin/Superuser** (không phải da_north hay da_south)

> ⚠️ Nếu chạy lại từ đầu: Bỏ comment phần **CLEANUP** ở đầu file SQL và chạy trước.

---

## 🔬 STEP 1 — Chuẩn bị Role & Data (Setup)

**Mục tiêu:** Tạo bảng dữ liệu khách hàng + 2 role Data Analyst.

### Bước làm

**1️⃣ Tạo bảng `customer_profiles`:**
```sql
CREATE TABLE IF NOT EXISTS linh_lab.customer_profiles (
    profile_id   SERIAL PRIMARY KEY,
    full_name    VARCHAR(100) NOT NULL,
    email        VARCHAR(150) NOT NULL,        -- 🔒 PII
    phone_number VARCHAR(20)  NOT NULL,        -- 🔒 PII
    region       VARCHAR(10)  NOT NULL
        CHECK (region IN ('NORTH', 'SOUTH', 'CENTRAL'))
);
```
> 🖥️ **DBeaver hiển thị:** `CREATE TABLE`

**2️⃣ INSERT 45 dòng dữ liệu mẫu** (15 NORTH + 15 SOUTH + 15 CENTRAL):
```sql
INSERT INTO linh_lab.customer_profiles (full_name, email, phone_number, region) VALUES
-- (... xem chi tiết trong file SQL ...)
```
> 🖥️ **DBeaver hiển thị:** `INSERT 0 45`

**3️⃣ Kiểm tra dữ liệu:**
```sql
SELECT region, COUNT(*) AS total
FROM linh_lab.customer_profiles
GROUP BY region ORDER BY region;
```
> 🖥️ **DBeaver hiển thị:**
>
> | region  | total |
> |---------|-------|
> | CENTRAL | 15    |
> | NORTH   | 15    |
> | SOUTH   | 15    |

**4️⃣ Tạo 2 Role:**
```sql
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'da_north') THEN
        CREATE ROLE da_north LOGIN PASSWORD 'north123';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'da_south') THEN
        CREATE ROLE da_south LOGIN PASSWORD 'south123';
    END IF;
END $$;
```
> 🖥️ **DBeaver hiển thị:** `DO`

**5️⃣ Cấp quyền cơ bản:**
```sql
GRANT CONNECT ON DATABASE postgres TO da_north, da_south;
GRANT USAGE ON SCHEMA linh_lab TO da_north, da_south;
```
> 🖥️ **DBeaver hiển thị:** `GRANT` (2 lần)

**6️⃣ Kiểm tra role đã tạo:**
```sql
SELECT rolname FROM pg_roles WHERE rolname IN ('da_north', 'da_south');
```
> 🖥️ **DBeaver hiển thị:**
>
> | rolname  |
> |----------|
> | da_north |
> | da_south |

---

## 🔬 STEP 2 — Column-Level Security (CLS)

**Mục tiêu:** Data Analyst **KHÔNG được xem** cột PII (email, phone_number). Chỉ được xem: `profile_id`, `full_name`, `region`.

### CLS là gì?

- **Column-Level Security** = Phân quyền ở cấp **CỘT**
- Thay vì cho xem toàn bộ bảng → chỉ cho xem một số cột nhất định
- Cột nhạy cảm (email, phone) bị **ẩn hoàn toàn** — query sẽ bị **LỖI** nếu cố truy cập

### Bước làm

**1️⃣ Thu hồi toàn bộ quyền SELECT:**
```sql
REVOKE ALL ON linh_lab.customer_profiles FROM da_north, da_south;
```
> 🖥️ **DBeaver hiển thị:** `REVOKE`

**2️⃣ Cấp SELECT chỉ trên 3 cột an toàn:**
```sql
GRANT SELECT (profile_id, full_name, region)
ON linh_lab.customer_profiles
TO da_north, da_south;
```
> 🖥️ **DBeaver hiển thị:** `GRANT`

**3️⃣ Kiểm tra quyền đã cấp:**
```sql
SELECT grantee, privilege_type, column_name
FROM information_schema.column_privileges
WHERE table_schema = 'linh_lab'
  AND table_name = 'customer_profiles'
  AND grantee IN ('da_north', 'da_south')
ORDER BY grantee, column_name;
```
> 🖥️ **DBeaver hiển thị:**
>
> | grantee  | privilege_type | column_name |
> |----------|----------------|-------------|
> | da_north | SELECT         | full_name   |
> | da_north | SELECT         | profile_id  |
> | da_north | SELECT         | region      |
> | da_south | SELECT         | full_name   |
> | da_south | SELECT         | profile_id  |
> | da_south | SELECT         | region      |

**4️⃣ Test — Chuyển sang da_north:**
```sql
SET ROLE da_north;
```
> 🖥️ **DBeaver hiển thị:** `SET`

**5️⃣ Thử SELECT * (sẽ BỊ LỖI ❌):**
```sql
SELECT * FROM linh_lab.customer_profiles;
```
> 🖥️ **DBeaver hiển thị LỖI:**
> ```
> SQL Error [42501]: ERROR: permission denied for table customer_profiles
> ```
>
> 💡 **Tại sao?** `SELECT *` yêu cầu quyền trên **TẤT CẢ** cột. Vì `da_north` không có quyền trên cột `email` và `phone_number` → PostgreSQL từ chối **toàn bộ** câu query.

**6️⃣ SELECT chỉ cột được phép (THÀNH CÔNG ✅):**
```sql
SELECT profile_id, full_name, region
FROM linh_lab.customer_profiles;
```
> 🖥️ **DBeaver hiển thị:** Bảng 45 dòng, chỉ có 3 cột — **KHÔNG thấy email và phone_number!**

**7️⃣ Cố tình truy cập cột PII (sẽ BỊ LỖI ❌):**
```sql
SELECT profile_id, full_name, email FROM linh_lab.customer_profiles;
```
> 🖥️ **DBeaver hiển thị LỖI:**
> ```
> SQL Error [42501]: ERROR: permission denied for table customer_profiles
> ```
>
> 💡 Chỉ cần **1 cột** không có quyền → cả câu query bị từ chối.

**8️⃣ Quay lại Admin:**
```sql
RESET ROLE;
```
> 🖥️ **DBeaver hiển thị:** `RESET`

### 📝 Kết luận Step 2

**CLS hoạt động như thế nào?**
- `REVOKE ALL` → Xóa sạch mọi quyền trên bảng
- `GRANT SELECT (cột1, cột2)` → Chỉ cho phép xem các cột được chỉ định
- Nếu query chứa **bất kỳ cột nào** không được phép → **LỖI** (không phải ẩn, mà là **từ chối hoàn toàn**)

**So sánh CLS và RLS:**

| Tiêu chí | CLS (Column) | RLS (Row) |
|----------|-------------|-----------|
| Ẩn cái gì? | Ẩn **cột** | Ẩn **dòng** |
| Khi truy cập sai? | **LỖI** (permission denied) | **Im lặng** (trả về 0 dòng) |
| Cấu hình bằng? | `GRANT/REVOKE` | `CREATE POLICY` |

### 🐛 Debug

| Vấn đề | Nguyên nhân | Cách sửa |
|--------|-------------|----------|
| `SELECT *` không bị lỗi | Đang dùng role Admin | Chạy `SET ROLE da_north;` trước |
| Lỗi `role "da_north" does not exist` | Chưa chạy Step 1 | Quay lại chạy Step 1 trước |
| `SET ROLE` bị lỗi | Admin chưa có quyền SET ROLE | Chạy `GRANT da_north TO <your_admin>;` |

---

## 🔬 STEP 3 — Row-Level Security (RLS) — Dynamic Filtering

**Mục tiêu:** `da_north` chỉ thấy khách hàng miền Bắc. `da_south` chỉ thấy miền Nam. Dữ liệu bị **"tàng hình" âm thầm** — không lỗi, không warning.

### RLS là gì?

- **Row-Level Security** = Phân quyền ở cấp **DÒNG**
- Mỗi user chỉ nhìn thấy các dòng thuộc quyền hạn của mình
- Dòng không thuộc quyền → **biến mất** (không lỗi — chỉ đơn giản là không tồn tại)

### Dynamic RLS là gì?

Thay vì tạo **từng Policy** cho **từng role** (cách tĩnh):
```sql
-- ❌ Cách tĩnh (hardcode) — Phải tạo nhiều policy
CREATE POLICY p1 ... TO da_north USING (region = 'NORTH');
CREATE POLICY p2 ... TO da_south USING (region = 'SOUTH');
```

Ta tạo **MỘT Policy DUY NHẤT** + **bảng mapping** (cách động):
```sql
-- ✅ Cách động (Dynamic) — 1 policy cho tất cả
CREATE POLICY p ... TO PUBLIC USING (
    region = (SELECT assigned_region FROM mapping WHERE username = CURRENT_USER)
);
```
> 💡 Thêm user mới? Chỉ cần INSERT vào bảng mapping — **KHÔNG cần sửa Policy!**

### Bước làm

**1️⃣ Tạo bảng mapping:**
```sql
CREATE TABLE IF NOT EXISTS linh_lab.user_region_mapping (
    username        VARCHAR(50) PRIMARY KEY,
    assigned_region VARCHAR(10) NOT NULL
        CHECK (assigned_region IN ('NORTH', 'SOUTH', 'CENTRAL'))
);
```
> 🖥️ **DBeaver hiển thị:** `CREATE TABLE`

**2️⃣ INSERT mapping:**
```sql
INSERT INTO linh_lab.user_region_mapping (username, assigned_region) VALUES
('da_north', 'NORTH'),
('da_south', 'SOUTH')
ON CONFLICT (username) DO UPDATE
SET assigned_region = EXCLUDED.assigned_region;
```
> 🖥️ **DBeaver hiển thị:** `INSERT 0 2`

**3️⃣ Cấp quyền SELECT mapping cho PUBLIC:**
```sql
GRANT SELECT ON linh_lab.user_region_mapping TO PUBLIC;
```
> 🖥️ **DBeaver hiển thị:** `GRANT`

**4️⃣ Kích hoạt RLS:**
```sql
ALTER TABLE linh_lab.customer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE linh_lab.customer_profiles FORCE ROW LEVEL SECURITY;
```
> 🖥️ **DBeaver hiển thị:** `ALTER TABLE` (2 lần)
>
> 💡 `ENABLE` = bật RLS. `FORCE` = ép table owner cũng phải tuân theo (superuser vẫn bypass).

**5️⃣ Tạo Policy Dynamic:**
```sql
CREATE POLICY policy_region_select
ON linh_lab.customer_profiles
FOR SELECT
TO PUBLIC
USING (
    region = (
        SELECT assigned_region
        FROM linh_lab.user_region_mapping
        WHERE username = CURRENT_USER
    )
);
```
> 🖥️ **DBeaver hiển thị:** `CREATE POLICY`
>
> 💡 **Cách Policy hoạt động:**
> - Với mỗi dòng, PostgreSQL kiểm tra: `region` của dòng = `assigned_region` của `CURRENT_USER`?
> - Nếu ĐÚNG → hiện dòng. Nếu SAI → ẩn dòng.
> - Nếu user không có trong mapping → subquery trả về NULL → tất cả dòng đều ẩn.

**6️⃣ Test — da_north chỉ thấy NORTH:**
```sql
SET ROLE da_north;
```
> 🖥️ `SET`

```sql
SELECT profile_id, full_name, region
FROM linh_lab.customer_profiles;
```
> 🖥️ **DBeaver hiển thị:** CHỈ **15 dòng**, tất cả `region = 'NORTH'`
>
> Dữ liệu SOUTH và CENTRAL **tàng hình hoàn toàn** — không lỗi, không warning!

```sql
SELECT region, COUNT(*) AS total
FROM linh_lab.customer_profiles GROUP BY region;
```
> 🖥️ **DBeaver hiển thị:**
>
> | region | total |
> |--------|-------|
> | NORTH  | 15    |
>
> (Chỉ 1 dòng — SOUTH và CENTRAL không tồn tại trong "thế giới" của da_north!)

```sql
RESET ROLE;
```

**7️⃣ Test — da_south chỉ thấy SOUTH:**
```sql
SET ROLE da_south;
```

```sql
SELECT profile_id, full_name, region
FROM linh_lab.customer_profiles;
```
> 🖥️ **DBeaver hiển thị:** CHỉ **15 dòng**, tất cả `region = 'SOUTH'`

```sql
RESET ROLE;
```

**8️⃣ [BONUS] Policy INSERT — Ép user chỉ INSERT đúng vùng:**

```sql
-- Cấp quyền INSERT cho các cột
GRANT INSERT (profile_id, full_name, email, phone_number, region)
ON linh_lab.customer_profiles TO da_north, da_south;

GRANT USAGE, SELECT ON SEQUENCE linh_lab.customer_profiles_profile_id_seq
TO da_north, da_south;
```
> 🖥️ `GRANT` (2 lần)

```sql
CREATE POLICY policy_region_insert
ON linh_lab.customer_profiles
FOR INSERT TO PUBLIC
WITH CHECK (
    region = (
        SELECT assigned_region
        FROM linh_lab.user_region_mapping
        WHERE username = CURRENT_USER
    )
);
```
> 🖥️ `CREATE POLICY`

**Test — da_north INSERT miền Nam → LỖI ❌:**
```sql
SET ROLE da_north;

INSERT INTO linh_lab.customer_profiles (full_name, email, phone_number, region)
VALUES ('Hacker Test', 'hack@test.com', '0900-000-000', 'SOUTH');
```
> 🖥️ **DBeaver hiển thị LỖI:**
> ```
> SQL Error [42501]: ERROR: new row violates row-level security policy for table "customer_profiles"
> ```
>
> 💡 `WITH CHECK` kiểm tra: region='SOUTH' nhưng da_north quản lý 'NORTH' → **vi phạm** → từ chối!

**Test — da_north INSERT miền Bắc → THÀNH CÔNG ✅:**
```sql
INSERT INTO linh_lab.customer_profiles (full_name, email, phone_number, region)
VALUES ('Nguyễn Test Bắc', 'test.bac@email.com', '0901-000-999', 'NORTH');
```
> 🖥️ `INSERT 0 1`

```sql
RESET ROLE;
```

### 📝 Kết luận Step 3

**RLS hoạt động như thế nào?**
1. `ENABLE ROW LEVEL SECURITY` → Bật tính năng
2. `CREATE POLICY ... USING (điều kiện)` → Định nghĩa filter
3. PostgreSQL **tự động** filter mỗi dòng trước khi trả kết quả
4. Dòng không thỏa điều kiện → **biến mất** (không lỗi)

**Dynamic RLS (bảng mapping) tốt hơn Static:**

| Tiêu chí | Static (hardcode) | Dynamic (mapping table) |
|----------|-------------------|-------------------------|
| Thêm user mới | Phải tạo Policy mới | Chỉ INSERT vào mapping |
| Số lượng Policy | Nhiều (1 per role) | CHỈ 1 |
| Bảo trì | Khó | Dễ |

### 🐛 Debug

| Vấn đề | Nguyên nhân | Cách sửa |
|--------|-------------|----------|
| da_north thấy cả 45 dòng | RLS chưa bật | Chạy `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` |
| Superuser thấy hết | Đúng hành vi — superuser bypass RLS | Dùng `SET ROLE da_north` để test |
| 0 dòng khi dùng Admin | `FORCE ROW LEVEL SECURITY` + Admin không có trong mapping | Thêm admin vào mapping hoặc bỏ FORCE |

---

## 🔬 STEP 4 — SECURITY DEFINER vs SECURITY INVOKER

**Mục tiêu:** Hiểu tại sao Function có thể **xuyên thủng** RLS — và cách phòng tránh.

### Khái niệm: Effective User ID

Khi gọi một function, PostgreSQL cần biết: **"Dùng quyền của AI để chạy?"**

| Cấu hình | Effective User ID | RLS kiểm tra ai? |
|----------|-------------------|-------------------|
| `SECURITY DEFINER` | **Người TẠO** function (Admin) | Admin → bypass RLS! |
| `SECURITY INVOKER` | **Người GỌI** function (da_north) | da_north → RLS hoạt động! |

### Bước làm

**1️⃣ Tạo function SECURITY DEFINER (NGUY HIỂM ⚠️):**
```sql
RESET ROLE;

CREATE OR REPLACE FUNCTION linh_lab.fn_get_customer_profiles(p_region VARCHAR)
RETURNS TABLE (profile_id INT, full_name VARCHAR, region VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER  -- ⚠️ Chạy với quyền NGƯỜI TẠO
AS $$
BEGIN
    RETURN QUERY
    SELECT cp.profile_id, cp.full_name, cp.region
    FROM linh_lab.customer_profiles cp
    WHERE cp.region = p_region;
END;
$$;
```
> 🖥️ `CREATE FUNCTION`

**2️⃣ Cấp quyền EXECUTE:**
```sql
GRANT EXECUTE ON FUNCTION linh_lab.fn_get_customer_profiles(VARCHAR) TO da_north;
```
> 🖥️ `GRANT`

**3️⃣ Test — da_north gọi hàm xem miền Nam:**
```sql
SET ROLE da_north;

SELECT * FROM linh_lab.fn_get_customer_profiles('SOUTH');
```
> 🖥️ **DBeaver hiển thị:** **15 dòng miền NAM!** ⚠️ RLS BỊ XUYÊN THỦNG!
>
> 💡 **Tại sao?**
> - Function dùng `SECURITY DEFINER` → Effective User ID = **Admin** (người tạo)
> - Admin là superuser → **bypass RLS**
> - da_north "mượn quyền" Admin → xem được dữ liệu miền Nam
> - → **Lỗ hổng bảo mật nghiêm trọng!**

```sql
RESET ROLE;
```

**4️⃣ Sửa thành SECURITY INVOKER (AN TOÀN ✅):**
```sql
CREATE OR REPLACE FUNCTION linh_lab.fn_get_customer_profiles(p_region VARCHAR)
RETURNS TABLE (profile_id INT, full_name VARCHAR, region VARCHAR)
LANGUAGE plpgsql
SECURITY INVOKER  -- ✅ Chạy với quyền NGƯỜI GỌI
AS $$
BEGIN
    RETURN QUERY
    SELECT cp.profile_id, cp.full_name, cp.region
    FROM linh_lab.customer_profiles cp
    WHERE cp.region = p_region;
END;
$$;
```
> 🖥️ `CREATE FUNCTION`

**5️⃣ Test lại — da_north gọi hàm xem miền Nam:**
```sql
SET ROLE da_north;

SELECT * FROM linh_lab.fn_get_customer_profiles('SOUTH');
```
> 🖥️ **DBeaver hiển thị:** **0 dòng!** ✅ RLS ĐƯỢC TÔN TRỌNG!
>
> 💡 **Tại sao?**
> - Function dùng `SECURITY INVOKER` → Effective User ID = **da_north** (người gọi)
> - RLS kiểm tra: da_north quản lý 'NORTH'
> - Tham số 'SOUTH' ≠ 'NORTH' → Policy chặn → 0 kết quả

**6️⃣ Test — da_north gọi hàm xem miền Bắc:**
```sql
SELECT * FROM linh_lab.fn_get_customer_profiles('NORTH');
```
> 🖥️ **DBeaver hiển thị:** **15 dòng miền BẮC** ✅

```sql
RESET ROLE;
```

### 📝 Kết luận Step 4

**SECURITY DEFINER vs INVOKER:**

| Tiêu chí | DEFINER | INVOKER |
|----------|---------|---------|
| Effective User ID | Người TẠO (Admin) | Người GỌI (User) |
| RLS được tôn trọng? | ❌ KHÔNG (bypass!) | ✅ CÓ |
| Khi nào dùng? | Function hệ thống (logging, audit) | Function truy cập dữ liệu |
| Rủi ro | Lỗ hổng bảo mật | An toàn |

> ⚠️ **Quy tắc vàng:** KHÔNG BAO GIỜ dùng `SECURITY DEFINER` cho function truy cập dữ liệu nhạy cảm!

---

## 🤔 Reflection: View + SECURITY_BARRIER

**Câu hỏi:** "Nếu dùng View thay cho function, liệu có an toàn hơn?"

**Trả lời:** **CÓ**, nhưng cần dùng `SECURITY_BARRIER`.

### View thường (không có SECURITY_BARRIER) — NGUY HIỂM:
```sql
CREATE VIEW linh_lab.v_profiles AS
SELECT profile_id, full_name, region FROM linh_lab.customer_profiles;
```
- PostgreSQL có thể **đẩy** điều kiện WHERE của user **VÀO bên trong** View
- Attacker có thể viết function tùy chỉnh trong WHERE để **"leak"** dữ liệu trước khi RLS filter kịp chạy

### View có SECURITY_BARRIER — AN TOÀN:
```sql
CREATE VIEW linh_lab.v_safe_profiles
WITH (security_barrier = true) AS
SELECT profile_id, full_name, region FROM linh_lab.customer_profiles;
```
- PostgreSQL **ÉP** chạy filter của View **TRƯỚC** → rồi mới chạy WHERE của user
- Ngăn attacker "nhìn lén" dữ liệu qua side-channel

### So sánh tổng hợp

| Tiêu chí | Function (INVOKER) | View (SECURITY_BARRIER) |
|----------|-------------------|------------------------|
| RLS được tôn trọng | ✅ Có | ✅ Có |
| Chống side-channel | ❌ Không | ✅ Có |
| Linh hoạt (tham số) | ✅ Có | ❌ Không (cố định) |
| Performance | Tốt | Có thể chậm hơn 1 chút |

**Kết luận:**
- Truy vấn đơn giản → Dùng **View + SECURITY_BARRIER** (an toàn nhất)
- Cần tham số/logic phức tạp → Dùng **Function + SECURITY INVOKER**
- **KHÔNG BAO GIỜ** dùng `SECURITY DEFINER` cho function truy cập dữ liệu nhạy cảm

---

## 📊 Tổng Kết

| Tính năng | Cách dùng | Hiệu ứng |
|-----------|-----------|-----------|
| **CLS** (Column-Level) | `GRANT SELECT (col1, col2)` | Query cột bị cấm → **LỖI** |
| **RLS** (Row-Level) | `CREATE POLICY ... USING (...)` | Dòng bị cấm → **Tàng hình** |
| **Dynamic RLS** | Bảng mapping + `CURRENT_USER` | 1 Policy cho tất cả role |
| **SECURITY DEFINER** | Function chạy quyền Admin | ⚠️ Bypass RLS |
| **SECURITY INVOKER** | Function chạy quyền User | ✅ Tôn trọng RLS |
| **SECURITY_BARRIER** | View chống side-channel | ✅ An toàn nhất |

### 💡 Tóm tắt dễ nhớ

- **CLS:** Ẩn cột → `GRANT SELECT` chỉ trên cột an toàn
- **RLS:** Ẩn dòng → `CREATE POLICY` với `USING` clause
- **Dynamic RLS:** 1 Policy + bảng mapping → dễ mở rộng
- **Function:** Luôn dùng `SECURITY INVOKER` (trừ khi có lý do đặc biệt)
- **View:** Thêm `SECURITY_BARRIER` khi cần an toàn tối đa
