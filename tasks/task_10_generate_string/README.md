# 📘 Task 10 — Generate WHERE Clause String

**Ticket:** DDID-19

## 📋 Mục tiêu

Viết một **SQL Function** nhận vào `(UserID, TableName)` → trả về **chuỗi WHERE** tương ứng.

## 🎯 Task này sẽ học được gì?

### 1. Dynamic SQL — Sinh câu lệnh SQL từ dữ liệu

Thay vì viết WHERE cứng cho từng user trong code ứng dụng, ta lưu **quy tắc vào bảng** → function tự sinh WHERE.

**Ví dụ thực tế:**

Công ty có 100 nhân viên, mỗi người được xem dữ liệu khác nhau.

```
❌ KHÔNG NÊN — Viết cứng trong code:

if (user == "U03") {
    query = "SELECT * FROM PurchaseOrder WHERE VendorId IN ('VS04','UK8A')";
} else if (user == "U05") {
    query = "SELECT * FROM PurchaseOrder";
} else if (user == "U09") {
    query = "SELECT * FROM Customer WHERE PostalCityID IN (1,6,7,3)";
}
// ... viết 100 cái IF → mệt mỏi, dễ sai

✅ NÊN — Lưu quy tắc vào bảng, function tự sinh:

INSERT INTO config (user_id, table_name, field_name, value)
VALUES ('U03', 'PurchaseOrder', 'VendorId', 'VS04,UK8A');
-- Thêm user mới = INSERT 1 dòng → XONG. Không sửa code!

SELECT fn_generate_where_clause('U03', 'PurchaseOrder');
-- → Tự sinh: "VendorId IN ('VS04','UK8A')"
```

### 2. Xử lý chuỗi trong PostgreSQL

Học cách tách chuỗi `'VS04,UK8A'` thành mảng `['VS04', 'UK8A']`, rồi ghép lại thành `IN ('VS04','UK8A')`.

**Ví dụ:**
```
Input:  'VS04,UK8A'
                │
  Tách theo dấu phẩy → ['VS04', 'UK8A']
                │
  Thêm dấu nháy    → ["'VS04'", "'UK8A'"]
                │
  Ghép lại          → "VendorId IN ('VS04','UK8A')"
```

### 3. Tự động chọn LIKE hay IN

Function phải **nhìn giá trị** rồi tự quyết:

| Giá trị trong bảng config | Có dấu `%` không? | Function sinh ra |
|--------------------------|-------------------|-----------------|
| `VS04,UK8A` | ❌ Không | `VendorId IN ('VS04','UK8A')` |
| `%sea%,air%` | ✅ Có | `LIKE '%sea%' OR LIKE 'air%'` |
| `OLED` | ❌ Không, 1 giá trị | `CategoryName = 'OLED'` |

### 4. Kiểm tra cột có tồn tại không (Advanced)

Dùng `information_schema.columns` để hỏi: "Bảng Product có cột VendorId không?"

```
Bảng Product có cột: ProductID, ProductName, Price
→ Không có VendorId → Bỏ qua → return '1=0'
```

### 5. Xử lý dấu `*` (wildcard)

```
Config ghi *  →  Nghĩa là "xem hết, không giới hạn"  →  return '1=1'
Không có config  →  Nghĩa là "không có quyền"  →  return '1=0'
```

---

## 📂 File

- [`10_generate_string.sql`](./10_generate_string.sql) — Toàn bộ script SQL

## ⚙️ Chuẩn bị

1. Mở DBeaver → kết nối PostgreSQL
2. Mở file `10_generate_string.sql`
3. Chạy **TỪNG LỆNH MỘT** (bôi đen → Ctrl+Enter)

> ⚠️ Chạy lại từ đầu? → Bỏ comment phần CLEANUP ở đầu file SQL rồi chạy trước.

---

## 📊 Bảng cấu hình — "Bộ não" của hệ thống

Bảng `T_CONFIG_RLS` chứa quy tắc: "User nào được xem gì?"

| UserID | TableName | FieldName | Value | **Nghĩa là** |
|--------|-----------|-----------|-------|---------------|
| U03 | PurchaseOrder | VendorId | VS04,UK8A | U03 chỉ xem vendor VS04 và UK8A |
| U03 | PurchaseOrder | PlantID | W1,W4 | U03 chỉ xem plant W1 và W4 |
| U03 | PurchaseOrder | DeliveryMethodName | %sea%,air% | U03 xem delivery chứa "sea" hoặc bắt đầu bằng "air" |
| U03 | ProductCategory | CategoryName | OLED | U03 chỉ xem category OLED |
| **U31** | **\*** | **\*** | **\*** | **U31 xem TẤT CẢ mọi thứ** |
| **U05** | PurchaseOrder | **\*** | **\*** | **U05 xem hết bảng PurchaseOrder** |
| U09 | Customer | PostalCityID | 1,6,7,3 | U09 chỉ xem 4 thành phố |
| U09 | Customer | CustomerCategoryName | %Suspects%,Loyal%,%Referral | U09 xem category chứa từ khóa |
| U09 | Customer | DeliveryCityID | **\*** | **U09 xem hết DeliveryCityID → cả bảng = 1=1** |
| U15 | Invoice | CustomerCategoryName | %boxes | U15 chỉ xem category kết thúc bằng "boxes" |
| UE1 | SaleOrder | CustomerID | %123 | UE1 xem customer kết thúc bằng "123" |
| UE1 | SaleOrderDetail | ProductID | 143,F35 | UE1 chỉ xem product 143 và F35 |
| **ADV** | **\*** | DeliveryMethodName | Road%,%Rail | **ADV: áp dụng cho MỌI bảng CÓ cột này** |
| **ADV** | **\*** | VendorId | VP19,UB55 | **ADV: áp dụng cho MỌI bảng CÓ cột này** |

---

## 🧠 Function xử lý theo 5 bước (thứ tự ưu tiên)

```
Nhận input: (UserID, TableName)
        │
        ▼
Bước 1: User có config (Table='*', Field='*') ?
        → CÓ: return '1=1' (xem hết)               Ví dụ: U31
        │
        ▼
Bước 2: User có config (Field='*' hoặc Value='*') cho bảng này?
        → CÓ: return '1=1' (xem hết bảng này)       Ví dụ: U05, U09
        │
        ▼
Bước 3: Lặp qua từng dòng config phù hợp:
        ├─ Config có Table='*'? → Kiểm tra cột có tồn tại không (ADV)
        ├─ Value có dấu % ? → Sinh LIKE
        ├─ Value không có % ? → Sinh IN hoặc =
        └─ Nhiều field? → Nối bằng AND
        │
        ▼
Bước 4: Không match gì cả?
        → return '1=0' (không có quyền)              Ví dụ: User không tồn tại
```

### Cách chọn LIKE hay IN

| Giá trị | Có `%`? | Kết quả |
|---------|---------|---------|
| `VS04,UK8A` | ❌ | `VendorId IN ('VS04','UK8A')` |
| `%sea%,air%` | ✅ | `(LIKE '%sea%' OR LIKE 'air%')` |
| `OLED` | ❌ (1 giá trị) | `CategoryName = 'OLED'` |
| Nhiều field cùng bảng | — | Nối bằng `AND` |

## 🔬 STEP 1 — Tạo bảng cấu hình + Dữ liệu

🎯 **Mục đích:** Tạo bảng `T_CONFIG_RLS` — nơi lưu tất cả quy tắc phân quyền, quy định "user nào được xem dữ liệu gì". Sau đó INSERT 16 dòng cấu hình cho 7 user khác nhau. Đây là bước bắt buộc đầu tiên vì function ở Step 3 sẽ đọc dữ liệu từ bảng này để sinh WHERE.

**Tương tự thực tế:** Giống như bảng phân công trong công ty:
```
Bảng phân công:
  Nhân viên An  → phụ trách miền Bắc     → chỉ xem dữ liệu Bắc
  Nhân viên Bình → phụ trách miền Nam     → chỉ xem dữ liệu Nam
  Giám đốc      → phụ trách tất cả       → xem hết

Nếu KHÔNG có bảng này → function không có dữ liệu để đọc
→ Gọi function sẽ luôn trả '1=0' → tất cả user đều bị chặn!
```

### Bước 1.1: Tạo bảng

```sql
CREATE TABLE IF NOT EXISTS linh_lab.t_config_rls (
    user_id    VARCHAR(30),   -- User nào?
    table_name VARCHAR(50),   -- Được xem bảng nào?
    field_name VARCHAR(50),   -- Lọc theo cột nào?
    value      VARCHAR(255)   -- Giá trị cho phép là gì?
);
```
> 🖥️ **Kết quả:** `CREATE TABLE`
>
> 📝 **4 cột** = 4 câu hỏi: **AI** được xem **BẢNG NÀO**, lọc theo **CỘT NÀO**, với **GIÁ TRỊ GÌ**?

### Bước 1.2: INSERT 16 dòng cấu hình

Chạy toàn bộ lệnh INSERT trong file SQL.

> 🖥️ **Kết quả:** `INSERT 0 16`
>
> 📝 **16 dòng** = 16 quy tắc phân quyền cho 7 user khác nhau (U03, U05, U09, U15, U31, UE1, ADV)

### Bước 1.3: Kiểm tra dữ liệu vừa INSERT

🎯 **Mục đích:** Đảm bảo 16 dòng config đã vào đúng. Nếu INSERT sai (thiếu dòng, sai value) → function sẽ trả kết quả sai ở các bước sau → debug rất khó.

```sql
SELECT * FROM linh_lab.t_config_rls ORDER BY user_id, table_name;
```
> 🖥️ **Kết quả:** Bảng 16 dòng
>
> 📝 **Tại sao kiểm tra?** Vì nếu INSERT sai → function sẽ trả kết quả sai. Phải đảm bảo dữ liệu đúng trước khi tạo function.



### 🐛 Lỗi thường gặp

| Lỗi | Nguyên nhân | Cách sửa |
|-----|-------------|----------|
| `already exists` | Chạy lại lần 2 | Chạy CLEANUP ở đầu file trước |
| `schema does not exist` | Schema chưa tạo | Chạy `CREATE SCHEMA IF NOT EXISTS linh_lab;` |
| `INSERT 0 0` | Câu INSERT bị lỗi syntax | Kiểm tra lại dấu phẩy cuối mỗi dòng |

---

## 🔬 STEP 2 — Tạo 3 bảng phụ cho ADV User

🎯 **Mục đích:** Tạo 3 bảng thật (`"Product"`, `"Vendor"`, `"DeliveryMethod"`) để test tính năng Advanced của user ADV. ADV có config `TableName='*'` (áp dụng cho mọi bảng), nhưng function phải **kiểm tra xem bảng thật có cột đó không** trước khi sinh điều kiện. Nếu không tạo 3 bảng này → không có bảng nào trong `information_schema` → test ADV luôn trả `1=0`.

> ⚠️ **Lưu ý:** Dùng dấu ngoặc kép `""` để PostgreSQL giữ tên CamelCase. Nếu không dùng `""`, PostgreSQL tự động lowercase → `product` thay vì `Product` → column name không match với config.

**Vấn đề cần giải quyết:** ADV config ghi `Field='VendorId'` cho TẤT CẢ bảng. Nhưng:
```
Bảng "Product" có cột: ProductID, ProductName, Price
→ KHÔNG CÓ cột VendorId → lọc theo VendorId vô nghĩa → bỏ qua

Bảng "Vendor" có cột: VendorID, VendorName, Address
→ CÓ cột VendorID (match case-insensitive) → lọc được → sinh "VendorId IN ('VP19','UB55')"
```
→ Function phải hỏi `information_schema`: "bảng này có cột đó không?" → cần bảng thật để hỏi.

### Bước 2.1: Tạo bảng Product

```sql
CREATE TABLE IF NOT EXISTS linh_lab."Product" (
    "ProductID"   VARCHAR(30) PRIMARY KEY,
    "ProductName" VARCHAR(255),
    "Price"       DECIMAL(10, 2)
);
```
> 🖥️ **Kết quả:** `CREATE TABLE`
>
> 📝 Bảng này có 3 cột: `ProductID`, `ProductName`, `Price`
> → **KHÔNG CÓ** cột `VendorId`, **KHÔNG CÓ** `DeliveryMethodName`
> → ADV sẽ nhận `1=0` khi query bảng này (vì không match cột nào)

### Bước 2.2: Tạo bảng Vendor

```sql
CREATE TABLE IF NOT EXISTS linh_lab."Vendor" (
    "VendorID"   VARCHAR(10) PRIMARY KEY,
    "VendorName" VARCHAR(255),
    "Address"    VARCHAR(500)
);
```
> 🖥️ **Kết quả:** `CREATE TABLE`
>
> 📝 Bảng này có 3 cột: `VendorID`, `VendorName`, `Address`
> → **CÓ** cột `VendorID` (match case-insensitive với config `VendorId`)
> → ADV sẽ nhận `VendorId IN ('VP19','UB55')` khi query bảng này

### Bước 2.3: Tạo bảng DeliveryMethod

```sql
CREATE TABLE IF NOT EXISTS linh_lab."DeliveryMethod" (
    "DeliveryMethodID"   VARCHAR(10) PRIMARY KEY,
    "DeliveryMethodName" VARCHAR(255)
);
```
> 🖥️ **Kết quả:** `CREATE TABLE`
>
> 📝 Bảng này có 2 cột: `DeliveryMethodID`, `DeliveryMethodName`
> → **CÓ** cột `DeliveryMethodName` → match với config ADV
> → ADV sẽ nhận `LIKE 'Road%' OR LIKE '%Rail'` khi query bảng này

### Tóm tắt: ADV query 3 bảng → 3 kết quả khác nhau

```
ADV config: 2 field = DeliveryMethodName + VendorId

Bảng "Product":         Có DeliveryMethodName? ❌  Có VendorId? ❌  → 1=0
Bảng "Vendor":          Có DeliveryMethodName? ❌  Có VendorID? ✅  → IN (...)
Bảng "DeliveryMethod":  Có DeliveryMethodName? ✅  Có VendorId? ❌  → LIKE ...
```



---

## 🔬 STEP 3 — Tạo Function `fn_generate_where_clause`

🎯 **Mục đích:** Tạo function chính của bài — nhận `(UserID, TableName)` → đọc bảng config ở Step 1 → tự động sinh chuỗi WHERE phù hợp. Function xử lý 5 trường hợp: wildcard toàn bộ (`1=1`), wildcard theo bảng (`1=1`), Advanced kiểm tra cột tồn tại, sinh `LIKE`/`IN` từ giá trị cụ thể, và không match (`1=0`). Nếu không tạo function → không có gì để gọi ở Step 4.

**Tương tự thực tế:** Function giống **nhân viên bảo vệ** ở cổng công ty:
```
Ai đến?        → Tra bảng phân công (config table từ Step 1)
Vào phòng nào? → Kiểm tra quyền (table_name)
Kết quả:
  - "Anh/chị được vào tất cả" → return '1=1'
  - "Anh/chị chỉ vào phòng A, B" → return 'WHERE ...'
  - "Anh/chị không có tên trong danh sách" → return '1=0'
```

### Bước 3.1: Tạo function

Bôi đen **TOÀN BỘ** block function trong file SQL (từ `CREATE OR REPLACE FUNCTION` đến `$$;`) → Ctrl+Enter.

> 🖥️ **Kết quả:** `CREATE FUNCTION`
>
> ⚠️ **Quan trọng:** Phải bôi đen TOÀN BỘ. Nếu chỉ bôi 1 phần → lỗi syntax!

### Function xử lý theo thứ tự nào?

```
Nhận input: (UserID, TableName)
        │
        ▼
Bước A: Kiểm tra "User này có xem tất cả không?"
        Config: Table='*' AND Field='*' ?
        → CÓ → return '1=1' → DỪNG
        → KHÔNG → tiếp tục ↓
        │
        ▼
Bước B: Kiểm tra "User này xem hết bảng này không?"
        Config: Field='*' hoặc Value='*' cho bảng này?
        → CÓ → return '1=1' → DỪNG
        → KHÔNG → tiếp tục ↓
        │
        ▼
Bước C: Lặp qua từng dòng config phù hợp
        Với mỗi dòng:
        │
        ├─ Config có Table='*'?
        │  → CÓ → Hỏi: "Bảng thật có cột này không?"
        │         → KHÔNG CÓ → Bỏ qua dòng này
        │         → CÓ → Tiếp tục xử lý ↓
        │
        ├─ Tách value theo dấu phẩy
        │  'VS04,UK8A' → ['VS04', 'UK8A']
        │
        ├─ Với mỗi giá trị:
        │  - Có dấu % ? → Thêm vào nhóm LIKE
        │  - Không có % ? → Thêm vào nhóm IN
        │
        └─ Ghép thành chuỗi:
           LIKE: "Field LIKE 'a%' OR Field LIKE '%b'"
           IN:   "Field IN ('v1','v2')"
        │
        ▼
Bước D: Ghép các field bằng AND
        "(LIKE ...) AND (IN ...) AND ..."
        │
        ▼
Bước E: Không match gì cả?
        → return '1=0' (không có quyền)
```

### Ví dụ chi tiết: Function xử lý U03 + PurchaseOrder

```
Input: ('U03', 'PurchaseOrder')

Bước A: U03 có config (*, *, *)? → KHÔNG → tiếp
Bước B: U03 có Field='*' cho PurchaseOrder? → KHÔNG → tiếp
Bước C: Lặp qua 3 dòng config:

  Dòng 1: Field=DeliveryMethodName, Value='%sea%,air%'
    → Tách: ['%sea%', 'air%']
    → '%sea%' có % → LIKE → "DeliveryMethodName LIKE '%sea%'"
    → 'air%'  có % → LIKE → "DeliveryMethodName LIKE 'air%'"
    → Ghép:  "(DeliveryMethodName LIKE '%sea%' OR DeliveryMethodName LIKE 'air%')"

  Dòng 2: Field=PlantID, Value='W1,W4'
    → Tách: ['W1', 'W4']
    → 'W1' không % → IN
    → 'W4' không % → IN
    → Ghép: "PlantID IN ('W1','W4')"

  Dòng 3: Field=VendorId, Value='VS04,UK8A'
    → Tách: ['VS04', 'UK8A']
    → 'VS04' không % → IN
    → 'UK8A' không % → IN
    → Ghép: "VendorId IN ('VS04','UK8A')"

Bước D: Nối bằng AND:
  "(DeliveryMethodName LIKE '%sea%' OR ...) AND PlantID IN (...) AND VendorId IN (...)"

→ XONG! Trả về chuỗi WHERE hoàn chỉnh.
```

### Các hàm PostgreSQL quan trọng

| Hàm | Làm gì? | Ví dụ dễ hiểu |
|-----|---------|---------------|
| `string_to_array('A,B', ',')` | Cắt chuỗi thành mảng | `'VS04,UK8A'` → `['VS04','UK8A']` |
| `FOREACH x IN ARRAY arr` | Duyệt từng phần tử | Xử lý 'VS04' rồi 'UK8A' |
| `array_append(arr, val)` | Thêm phần tử vào mảng | Thêm `"LIKE '%sea%'"` vào danh sách |
| `array_to_string(arr, ' OR ')` | Ghép mảng lại | `['A','B']` → `'A OR B'` |
| `information_schema.columns` | Hỏi "bảng X có cột Y không?" | Kiểm tra cột tồn tại cho ADV |



### 🐛 Lỗi thường gặp

| Lỗi | Nguyên nhân | Cách sửa |
|-----|-------------|----------|
| `syntax error at or near "$$"` | Chỉ bôi đen 1 phần function | Bôi đen TOÀN BỘ từ CREATE đến `$$;` |
| `function already exists` | Chạy lại lần 2 | Không sao — `CREATE OR REPLACE` tự ghi đè |
| `unterminated string` | Copy thiếu dấu nháy | Kiểm tra lại dấu `'` trong function |

---

## 🔬 STEP 4 — Test từng case

🎯 **Mục đích:** Chạy từng test case để kiểm tra function hoạt động đúng. Mỗi test kiểm tra 1 quy tắc khác nhau: wildcard, LIKE, IN, nhiều field AND, user không tồn tại. Nếu kết quả không khớp với bảng mong đợi → function có bug → quay lại Step 3 kiểm tra logic.

### TEST 1: U31 — Wildcard toàn bộ (Quy tắc 1)

🎯 **Mục đích:** Kiểm tra quy tắc 1 — user có config `(*, *, *)` → được xem tất cả → function trả `1=1` cho BẤT KỲ bảng nào.

```sql
SELECT linh_lab.fn_generate_where_clause('U31', 'AnyTable') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | 1=1 |
>
> 💡 **Tại sao?** U31 có config `(*, *, *)` → xem tất cả → `1=1`

---

### TEST 2: U05 + PurchaseOrder — Wildcard theo bảng (Quy tắc 2)

🎯 **Mục đích:** Kiểm tra quy tắc 2 — user có `FieldName='*'` cho 1 bảng cụ thể → xem hết bảng đó. Khác với U31 (xem hết MỌI bảng), U05 chỉ xem hết PurchaseOrder.

```sql
SELECT linh_lab.fn_generate_where_clause('U05', 'PurchaseOrder') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | 1=1 |
>
> 💡 **Tại sao?** U05 có `FieldName='*'` cho PurchaseOrder → xem hết bảng này

---

### TEST 3: U05 + Invoice — Không có config (Quy tắc 5)

🎯 **Mục đích:** Kiểm tra quy tắc 5 — user KHÔNG CÓ config cho bảng này → không có quyền → function trả `1=0`. Chứng minh U05 chỉ có quyền cho PurchaseOrder, KHÔNG có quyền cho Invoice.

```sql
SELECT linh_lab.fn_generate_where_clause('U05', 'Invoice') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | 1=0 |
>
> 💡 **Tại sao?** U05 chỉ có config cho PurchaseOrder, không có Invoice → không có quyền → `1=0`

---

### TEST 4: U09 + Customer — Wildcard theo Value (Quy tắc 2)

🎯 **Mục đích:** Kiểm tra quy tắc 2 biến thể — U09 có 3 dòng config cho Customer, nhưng 1 trong đó có `Value='*'` (DeliveryCityID). Chỉ cần **1 field** có `Value='*'` → cả bảng trả `1=1`. Function phải nhận ra điều này trước khi xử lý các field khác.

```sql
SELECT linh_lab.fn_generate_where_clause('U09', 'Customer') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | 1=1 |
>
> 💡 **Tại sao?** U09 có dòng `DeliveryCityID = '*'` → chỉ cần **1 field** có `Value='*'` → cả bảng = `1=1`

---

### TEST 5: UE1 + SaleOrder — Value có `%` → Sinh LIKE (Quy tắc 4)

🎯 **Mục đích:** Kiểm tra logic sinh LIKE — khi value chứa dấu `%`, function phải dùng `LIKE` thay vì `IN`. Value `%123` nghĩa là "CustomerID kết thúc bằng 123".

```sql
SELECT linh_lab.fn_generate_where_clause('UE1', 'SaleOrder') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | CustomerID LIKE '%123' |
>
> 💡 **Tại sao?** Value là `%123` (có dấu %) → dùng LIKE

---

### TEST 6: UE1 + SaleOrderDetail — Value không có `%` → Sinh IN (Quy tắc 4)

🎯 **Mục đích:** Kiểm tra logic sinh IN — khi value KHÔNG chứa `%`, function phải dùng `IN`. Value `143,F35` nghĩa là "chỉ xem ProductID là 143 hoặc F35".

```sql
SELECT linh_lab.fn_generate_where_clause('UE1', 'SaleOrderDetail') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | ProductID IN ('143','F35') |
>
> 💡 **Tại sao?** Value là `143,F35` (không có %) → dùng IN

---

### TEST 7: U03 + PurchaseOrder — Nhiều field nối AND (Quy tắc 4)

🎯 **Mục đích:** Kiểm tra trường hợp phức tạp nhất — U03 có **3 field** cho PurchaseOrder. Function phải sinh điều kiện cho TỪNG field rồi nối bằng AND. Trong đó `DeliveryMethodName` dùng LIKE (vì có `%`), còn `PlantID` và `VendorId` dùng IN.

```sql
SELECT linh_lab.fn_generate_where_clause('U03', 'PurchaseOrder') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | (DeliveryMethodName LIKE '%sea%' OR DeliveryMethodName LIKE 'air%') AND PlantID IN ('W1','W4') AND VendorId IN ('VS04','UK8A') |
>
> 💡 **Tại sao?** U03 có 3 field cho PurchaseOrder:
> - `DeliveryMethodName`: có `%` → LIKE (2 pattern nối OR)
> - `PlantID`: không có `%` → IN
> - `VendorId`: không có `%` → IN
> - 3 field nối bằng AND

---

### TEST 8: U03 + ProductCategory — 1 giá trị dùng `=` (Quy tắc 4)

🎯 **Mục đích:** Kiểm tra tối ưu — khi chỉ có 1 giá trị và không có `%`, function dùng `=` thay vì `IN`. `CategoryName = 'OLED'` gọn hơn `CategoryName IN ('OLED')`.

```sql
SELECT linh_lab.fn_generate_where_clause('U03', 'ProductCategory') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | CategoryName = 'OLED' |
>
> 💡 **Tại sao?** Chỉ 1 giá trị `OLED`, không có `%` → dùng `=` (không cần IN)

---

### TEST 9: U15 + Invoice — LIKE

```sql
SELECT linh_lab.fn_generate_where_clause('U15', 'Invoice') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | CustomerCategoryName LIKE '%boxes' |

---

### TEST 10: User không tồn tại (Quy tắc 5)

🎯 **Mục đích:** Kiểm tra trường hợp user `XXX` không hề tồn tại trong bảng config → function PHẢI trả `1=0` (không có quyền). Đây là **bảo mật mặc định** — nếu không có quy tắc nào cho user → chặn hết.

```sql
SELECT linh_lab.fn_generate_where_clause('XXX', 'AnyTable') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | 1=0 |
>
> 💡 **Tại sao?** User `XXX` không có trong bảng config → không có quyền gì

---

## 🔬 STEP 5 — Test Advanced: ADV User (Quy tắc 3)

🎯 **Mục đích:** Kiểm tra quy tắc 3 — trường hợp nâng cao nhất. ADV có `TableName='*'` (áp dụng cho mọi bảng) nhưng `FieldName` cụ thể (DeliveryMethodName, VendorId). Function phải dùng `information_schema.columns` để **kiểm tra xem bảng thật có cột đó không** trước khi sinh điều kiện. Đây là lý do ta tạo 3 bảng ở Step 2.

**ADV đặc biệt ở chỗ:** Quy tắc áp dụng cho MỌI bảng, nhưng mỗi bảng có cấu trúc khác nhau → kết quả khác nhau.

```
ADV config:
  Field = DeliveryMethodName → Value = 'Road%,%Rail'
  Field = VendorId           → Value = 'VP19,UB55'

Khi gọi function cho bảng "DeliveryMethod":
  → Bảng có cột DeliveryMethodName? ✅ CÓ → sinh LIKE
  → Bảng có cột VendorId?           ❌ KHÔNG → bỏ qua

Khi gọi function cho bảng "Vendor":
  → Bảng có cột DeliveryMethodName? ❌ KHÔNG → bỏ qua
  → Bảng có cột VendorID?           ✅ CÓ (match case-insensitive) → sinh IN

Khi gọi function cho bảng "Product":
  → Không có cột nào match → return '1=0'
```

---

### TEST ADV-1: DeliveryMethod

```sql
SELECT linh_lab.fn_generate_where_clause('ADV', 'DeliveryMethod') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | (DeliveryMethodName LIKE 'Road%' OR DeliveryMethodName LIKE '%Rail') |
>
> 💡 Bảng `"DeliveryMethod"` có cột `DeliveryMethodName` → match → sinh LIKE

---

### TEST ADV-2: Vendor

```sql
SELECT linh_lab.fn_generate_where_clause('ADV', 'Vendor') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | VendorId IN ('VP19','UB55') |
>
> 💡 Bảng `"Vendor"` có cột `VendorID` (match case-insensitive với config `VendorId`) → sinh IN

---

### TEST ADV-3: Product

```sql
SELECT linh_lab.fn_generate_where_clause('ADV', 'Product') AS result;
```

> 🖥️ **Kết quả:**
>
> | result |
> |--------|
> | 1=0 |
>
> 💡 Bảng `"Product"` **KHÔNG CÓ** cả 2 cột (`VendorId`, `DeliveryMethodName`) → không match gì → `1=0`

---

## 📊 Bảng tổng hợp tất cả kết quả

Chạy câu query cuối cùng trong file SQL:

| # | Test | Kết quả | Giải thích |
|---|------|---------|------------|
| 1 | U31 + AnyTable | `1=1` | Wildcard toàn bộ |
| 2 | U05 + PurchaseOrder | `1=1` | Field='*' |
| 3 | U05 + Invoice | `1=0` | Không có config |
| 4 | U09 + Customer | `1=1` | Value='*' |
| 5 | UE1 + SaleOrder | `CustomerID LIKE '%123'` | Có % → LIKE |
| 6 | UE1 + SaleOrderDetail | `ProductID IN ('143','F35')` | Không % → IN |
| 7 | U03 + PurchaseOrder | `(...LIKE...) AND ...IN... AND ...IN...` | 3 field AND |
| 8 | U03 + ProductCategory | `CategoryName = 'OLED'` | 1 giá trị → = |
| 9 | U15 + Invoice | `...LIKE '%boxes'` | Có % → LIKE |
| 10 | XXX + AnyTable | `1=0` | User không tồn tại |
| 11 | ADV + DeliveryMethod | `(...LIKE 'Road%' OR ...)` | Cột tồn tại → LIKE |
| 12 | ADV + Vendor | `VendorId IN (...)` | Cột tồn tại → IN |
| 13 | ADV + Product | `1=0` | Cột không tồn tại |

---

## 📊 Tổng Kết

### 5 Quy tắc dễ nhớ

| Quy tắc | Config như nào? | Function trả về | User ví dụ |
|---------|----------------|-----------------|------------|
| 1 | `Table='*', Field='*'` | `1=1` luôn | U31 |
| 2 | `Field='*'` hoặc `Value='*'` | `1=1` cho bảng đó | U05, U09 |
| 3 | `Table='*', Field=cụ thể` | Kiểm tra cột → sinh điều kiện | ADV |
| 4 | Tất cả cụ thể | `IN` / `LIKE` / `=` | U03, UE1, U15 |
| 5 | Không có config | `1=0` | XXX |

### Khi nào LIKE, khi nào IN?

| Nhìn vào Value | Có `%` ? | Sinh ra |
|---------------|---------|---------|
| `VS04,UK8A` | ❌ | `IN ('VS04','UK8A')` |
| `%sea%,air%` | ✅ | `LIKE '%sea%' OR LIKE 'air%'` |
| `OLED` (1 cái) | ❌ | `= 'OLED'` |

### 💡 Tóm tắt

- **`*` trong config** = wildcard = xem hết = `1=1`
- **Không có config** = không có quyền = `1=0`
- **Value có `%`** = dùng `LIKE`
- **Value không có `%`** = dùng `IN` (nhiều giá trị) hoặc `=` (1 giá trị)
- **Nhiều field cùng bảng** = nối bằng `AND`
- **ADV (Table=\*)** = kiểm tra cột thật bằng `information_schema`
