# 📘 Task 08 — Isolation Levels & Read Phenomena

## 🎯 Mục đích

Hiểu 4 hiện tượng đọc sai lệch (Read Phenomena) khi nhiều Transaction chạy song song, và cách PostgreSQL MVCC xử lý chúng qua 4 mức Isolation Level.

---

## 📂 Cấu trúc thư mục

```
task_08_isolation_levels/
├── isolation_levels.sql     # SQL scripts cho 4 kịch bản (chạy trên 2 Terminal)
├── read_phenomena.md        # 4 bảng Timeline + phân tích chi tiết
└── README.md                # Hướng dẫn (file này)
```

---

## 🔬 Các kịch bản thực hành

| Step | Hiện tượng | Isolation Level | Kết quả PostgreSQL |
|------|-----------|----------------|-------------------|
| 1 | **Dirty Read** — Đọc dữ liệu rác (uncommitted) | `READ UNCOMMITTED` | ❌ PostgreSQL **chặn** (MVCC tự nâng lên READ COMMITTED) |
| 2 | **Non-Repeatable Read** — SELECT 2 lần ra kết quả khác | `READ COMMITTED` vs `REPEATABLE READ` | ⚠️ Xảy ra ở RC / ❌ Chặn ở RR |
| 3 | **Phantom Read** — Dòng mới "xuất hiện như bóng ma" | `REPEATABLE READ` | ❌ PostgreSQL **chặn** (mạnh hơn chuẩn SQL) |
| 4 | **Lost Update** — Ghi đè dữ liệu, mất 1 giao dịch | `READ COMMITTED` vs `SERIALIZABLE` | ⚠️ Xảy ra ở RC / ❌ Chặn ở SERIALIZABLE |

---

## 🛠️ Cách chạy

### Yêu cầu
- **2 Terminal** (hoặc 2 tab DBeaver) kết nối cùng database
- Chạy lệnh **theo đúng thứ tự** trong timeline (t0 → t1 → t2 → ...)

### Thứ tự thực hành

```
1. Mở file isolation_levels.sql
2. Mở 2 Terminal (T1, T2) kết nối cùng database
3. Chạy từng Step theo thứ tự t0 → t1 → ...
4. Ghi nhận kết quả vào read_phenomena.md
5. Reset dữ liệu trước mỗi Step (script có sẵn trong SQL)
```

---

## 📖 Kiến thức nền

### MVCC (Multi-Version Concurrency Control)

PostgreSQL dùng MVCC thay vì Lock-based concurrency:
- Mỗi `UPDATE` tạo **bản sao mới** của dòng dữ liệu, không ghi đè bản cũ
- Mỗi transaction nhìn thấy **snapshot** riêng tại thời điểm phù hợp
- Readers **không block** Writers, Writers **không block** Readers
- → Hiệu năng cao hơn lock-based (SQL Server, MySQL InnoDB)

### 4 Isolation Levels (thấp → cao)

| Level | Snapshot khi nào? | Trade-off |
|-------|------------------|-----------|
| `READ UNCOMMITTED` | Mỗi câu lệnh * | * PostgreSQL = READ COMMITTED |
| `READ COMMITTED` | Mỗi câu lệnh (statement) | Nhanh, nhưng SELECT 2 lần có thể khác |
| `REPEATABLE READ` | Đầu transaction (BEGIN) | Nhất quán, nhưng có thể bị serialization error |
| `SERIALIZABLE` | Đầu transaction + conflict detection | An toàn nhất, nhưng chậm + cần retry logic |

---

## 🗂️ Bảng sử dụng

| Bảng | Cột theo dõi | Mục đích |
|------|-------------|----------|
| `linh_lab.promotion_program` | `budget_limit` | Dirty Read, Non-Repeatable Read, Lost Update |
| `linh_lab.customer_voucher` | `COUNT(*)` | Phantom Read |

---

## 🔬 Hướng dẫn chi tiết từng Step

> **⚠️ Lưu ý khi chạy trên DBeaver:**
> - Mỗi tab DBeaver = 1 connection riêng = 1 transaction riêng
> - Chạy **TỪNG LỆNH MỘT** (bôi đen 1 lệnh → Ctrl+Enter). KHÔNG bôi đen nhiều lệnh cùng lúc
> - Nếu gặp lỗi `SET TRANSACTION ISOLATION LEVEL must be called before any query`:
>   → Chạy `ROLLBACK;` trước để clear transaction cũ, rồi chạy lại `BEGIN ...`

---

### 🔬 STEP 1 — Dirty Read

**Câu hỏi cần trả lời:** TX1 UPDATE nhưng chưa COMMIT. TX2 có nhìn thấy dữ liệu "rác" đó không?

#### Bước làm

**Tab T1:**
```sql
-- 1️⃣ Xem giá trị gốc (ghi nhớ con số này)
SELECT program_id, program_name, budget_limit
FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ **DBeaver hiển thị:** Bảng kết quả 1 dòng, cột `budget_limit` = `50000000.00`

```sql
-- 2️⃣ Chạy ROLLBACK trước để clear transaction cũ (nếu có)
ROLLBACK;
```
> 🖥️ **DBeaver sẽ hiển thị:** `ROLLBACK` (hoặc `WARNING: there is no transaction in progress` → bỏ qua, không sao)

```sql
-- 3️⃣ Bắt đầu transaction mức thấp nhất
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
```
> 🖥️ **DBeaver sẽ hiển thị:** `BEGIN` — transaction đã mở

```sql
-- 4️⃣ Sửa budget thành 999M nhưng KHÔNG COMMIT
UPDATE linh_lab.promotion_program
SET budget_limit = 999999999 WHERE program_id = 1;
```
> 🖥️ **DBeaver sẽ hiển thị:** `UPDATE 1` — đã update 1 dòng (nhưng CHƯA COMMIT!)
>
> ⚠️ **KHÔNG gõ COMMIT!** Dừng lại đây.

⏸️ **DỪNG T1 — Chuyển sang tab T2**

**Tab T2:**
```sql
-- 5️⃣ T2 cũng dùng mức thấp nhất
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
```
> 🖥️ **DBeaver sẽ hiển thị:** `BEGIN`

```sql
-- 6️⃣ T2 đọc budget — liệu có thấy 999M?
SELECT program_id, program_name, budget_limit
FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ **DBeaver hiển thị:** Bảng kết quả 1 dòng, cột `budget_limit` = **`50000000.00`** (giá trị GỐC, KHÔNG phải 999M!)

```sql
-- 7️⃣ Kết thúc T2
COMMIT;
```
> 🖥️ **DBeaver sẽ hiển thị:** `COMMIT`

⏸️ **Quay lại tab T1**

**Tab T1:**
```sql
-- 8️⃣ Hủy thay đổi
ROLLBACK;
```
> 🖥️ **DBeaver sẽ hiển thị:** `ROLLBACK` — budget trở về 50M

#### 📝 Kết luận Step 1

**Nội dung chính:**
PostgreSQL **KHÔNG CHO PHÉP** đọc dữ liệu đang thay đổi (dirty read) dù bạn set isolation level là `READ UNCOMMITTED`.

**Giải thích từng ý:**

**Dirty Read là gì?**
- Khi transaction A đang UPDATE dữ liệu (chưa commit)
- Transaction B đọc được dữ liệu chưa commit đó (dữ liệu "bẩn")
- Nếu A rollback → B thấy dữ liệu sai

**PostgreSQL làm gì?**
- Dù bạn set `READ UNCOMMITTED`, PostgreSQL vẫn **không cho phép** Dirty Read
- Nó luôn nâng cấp lên `READ COMMITTED` (chỉ đọc dữ liệu đã commit)

**MVCC là gì?**
- PostgreSQL dùng công nghệ **MVCC** (Multi-Version Concurrency Control)
- Mỗi transaction thấy một "bản snapshot" (ảnh chụp) của database tại thời điểm bắt đầu
- Dữ liệu chưa commit thì **không tồn tại** trong snapshot → không nhìn thấy

**Ví dụ dễ hình dung:**
- Transaction A: Đang thay đổi ngân sách từ 50 triệu → 500 triệu (chưa commit)
- Transaction B: Đọc bảng → Chỉ thấy **50 triệu** (dữ liệu cũ, đã commit)
- Transaction A commit → Transaction B **lần sau** mới thấy 500 triệu
- → Không bao giờ thấy dữ liệu "đang thay đổi giữa chừng"

> **Tóm tắt dễ nhớ:**
> PostgreSQL rất "cẩn thận":
> - Dù bạn yêu cầu đọc dữ liệu bẩn (`READ UNCOMMITTED`) → Nó vẫn chỉ cho đọc dữ liệu đã commit (`READ COMMITTED`)
> - Nhờ MVCC, mỗi transaction thấy một "ảnh chụp" riêng → an toàn, không loạn
>
> Đây là lý do PostgreSQL rất đáng tin cậy trong môi trường nhiều người dùng cùng lúc.

#### 🐛 Debug nếu kết quả sai

| Vấn đề | Nguyên nhân | Cách sửa |
|--------|-------------|----------|
| T2 thấy 999M | Có thể T1 đã COMMIT thay vì để chờ | Chạy lại — đảm bảo KHÔNG gõ COMMIT ở T1 |
| Lỗi `SET TRANSACTION ISOLATION LEVEL...` | Đã có transaction đang mở | Gõ `ROLLBACK;` trước rồi chạy lại `BEGIN` |
| Budget không phải 50M | Đã bị thay đổi từ step trước | Chạy reset: `UPDATE ... SET budget_limit = 50000000` |

---

### 🔬 STEP 2 — Non-Repeatable Read

**Câu hỏi cần trả lời:** Trong cùng 1 transaction, chạy SELECT 2 lần có ra kết quả khác nhau không?

#### Kịch bản A: READ COMMITTED (sẽ bị lỗi ⚠️)

**Tab T1:**
```sql
-- 1️⃣ Bắt đầu transaction (mặc định READ COMMITTED)
BEGIN;
```
> 🖥️ **DBeaver hiển thị:** `BEGIN`

```sql
-- 2️⃣ Đọc budget LẦN 1
SELECT program_id, budget_limit
FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ **DBeaver hiển thị:** Bảng 1 dòng → `budget_limit` = **`50000000.00`** → Ghi nhớ con số này!

⏸️ **DỪNG T1 — Chuyển sang T2**

**Tab T2:**
```sql
-- 3️⃣ T2 trừ 5 triệu rồi COMMIT (chạy từng lệnh)
BEGIN;
```
> 🖥️ `BEGIN`

```sql
UPDATE linh_lab.promotion_program
SET budget_limit = budget_limit - 5000000 WHERE program_id = 1;
```
> 🖥️ `UPDATE 1`

```sql
COMMIT;
```
> 🖥️ `COMMIT`

⏸️ **Quay lại tab T1**

**Tab T1:**
```sql
-- 4️⃣ Đọc budget LẦN 2 (vẫn trong cùng transaction!)
SELECT program_id, budget_limit
FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ **DBeaver hiển thị:** Bảng 1 dòng → `budget_limit` = **`45000000.00`** ⚠️ (đã thay đổi!)

```sql
-- 5️⃣ Kết thúc
COMMIT;
```
> 🖥️ `COMMIT`

#### ✅ Check kết quả Kịch bản A

| Câu hỏi | Kết quả | Ý nghĩa |
|----------|---------|---------|
| SELECT lần 1 = ? | **50,000,000** | Giá trị ban đầu |
| SELECT lần 2 = ? | **45,000,000** ⚠️ | Đã thay đổi dù T1 chưa làm gì! |
| 2 lần khác nhau? | **CÓ** | → **Non-Repeatable Read xảy ra!** |

**Điều đó nghĩa là:** Ở `READ COMMITTED`, mỗi câu SELECT lấy snapshot **MỚI NHẤT**. Khi T2 COMMIT → snapshot mới → T1 thấy giá trị khác.

---

#### Kịch bản B: REPEATABLE READ (sẽ sửa được ✅)

**Tab T1 — Reset trước:**
```sql
ROLLBACK;
```
> 🖥️ `ROLLBACK`

```sql
UPDATE linh_lab.promotion_program SET budget_limit = 50000000 WHERE program_id = 1;
```
> 🖥️ `UPDATE 1`

```sql
COMMIT;
```
> 🖥️ `COMMIT` — Quan trọng! Phải COMMIT để reset thật sự lưu vào DB

```sql
-- Kiểm tra reset thành công
SELECT budget_limit FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ `budget_limit` = **`50000000.00`** ← Nếu thấy 50M mới tiếp tục bước tiếp!

---

**Tab T1 — Bắt đầu thí nghiệm:**
```sql
-- 1️⃣ Bắt đầu với REPEATABLE READ
BEGIN ISOLATION LEVEL REPEATABLE READ;
```
> 🖥️ `BEGIN`

```sql
-- 2️⃣ Đọc budget LẦN 1
SELECT program_id, budget_limit
FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ Bảng 1 dòng → `budget_limit` = **`50000000.00`** → Ghi nhớ con số này!

⏸️ **DỪNG T1 — Chuyển sang tab T2**

**Tab T2 — Thay đổi dữ liệu:**
```sql
BEGIN;
```
> 🖥️ `BEGIN`

```sql
UPDATE linh_lab.promotion_program
SET budget_limit = budget_limit - 5000000 WHERE program_id = 1;
```
> 🖥️ `UPDATE 1`

```sql
COMMIT;
```
> 🖥️ `COMMIT` — T2 đã trừ 5M và commit thành công

⏸️ **Quay lại tab T1**

**Tab T1 — Đọc lại:**
```sql
-- 3️⃣ Đọc budget LẦN 2 (vẫn trong REPEATABLE READ!)
SELECT program_id, budget_limit
FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ **DBeaver hiển thị:** `budget_limit` = **`50000000.00`** ✅ (KHÔNG đổi! Vẫn 50M dù T2 đã trừ 5M!)

```sql
COMMIT;
```
> 🖥️ `COMMIT`

#### ✅ Check kết quả Kịch bản B

| Câu hỏi | Kết quả | Ý nghĩa |
|----------|---------|---------|
| SELECT lần 1 = ? | **50,000,000** | Giá trị ban đầu |
| SELECT lần 2 = ? | **50,000,000** ✅ | KHÔNG đổi! |
| 2 lần khác nhau? | **KHÔNG** | → **REPEATABLE READ chặn được!** |

#### Nội dung chính

PostgreSQL **KHÔNG CHO PHÉP** đọc dữ liệu đang thay đổi (**Dirty Read**) dù bạn set isolation level là **READ UNCOMMITTED**.

---

#### Giải thích từng ý

#### Dirty Read là gì?

- Khi transaction A đang **UPDATE** dữ liệu (chưa commit).
- Transaction B đọc được dữ liệu chưa commit đó (dữ liệu "bẩn").
- Nếu A rollback → B thấy dữ liệu sai.

---

#### PostgreSQL làm gì?

- Dù bạn set **READ UNCOMMITTED**, PostgreSQL vẫn không cho phép Dirty Read.
- Nó luôn nâng cấp lên **READ COMMITTED** (chỉ đọc dữ liệu đã commit).

---

#### MVCC là gì?

PostgreSQL dùng công nghệ **MVCC (Multi-Version Concurrency Control)**.

- Mỗi transaction thấy một **"bản snapshot" (ảnh chụp)** của database tại thời điểm bắt đầu.
- Dữ liệu chưa commit thì không tồn tại trong snapshot → không nhìn thấy.

---

#### Ví dụ dễ hình dung

Transaction A: Đang thay đổi ngân sách từ **50 triệu → 500 triệu** (chưa commit).

Transaction B: Đọc bảng → Chỉ thấy **50 triệu** (dữ liệu cũ, đã commit).

Transaction A commit → Transaction B lần sau mới thấy **500 triệu**.

→ Không bao giờ thấy dữ liệu **"đang thay đổi giữa chừng"**.

---

#### Tóm tắt dễ nhớ

PostgreSQL rất **"cẩn thận"**:

- Dù bạn yêu cầu đọc dữ liệu bẩn (**READ UNCOMMITTED**) → Nó vẫn chỉ cho đọc dữ liệu đã commit (**READ COMMITTED**).
- Nhờ **MVCC**, mỗi transaction thấy một **"ảnh chụp"** riêng → an toàn, không loạn.

Đây là lý do PostgreSQL rất đáng tin cậy trong môi trường nhiều người dùng cùng lúc.

---

### 🔬 STEP 3 — Phantom Read

**Câu hỏi cần trả lời:** Sau khi T2 thêm dòng mới và commit, liệu T1 (đang trong transaction) có thấy dòng mới đó khi đếm lại hay không?
Đây là cách kiểm tra transaction có bị "bóng ma" (dòng mới xuất hiện bất ngờ) hay không.

**Reset trước:**
```sql
UPDATE linh_lab.promotion_program SET budget_limit = 50000000 WHERE program_id = 1;
```

**Tab T1:**
```sql
-- 1️⃣ Bắt đầu REPEATABLE READ
BEGIN ISOLATION LEVEL REPEATABLE READ;
```
> 🖥️ `BEGIN`

```sql
-- 2️⃣ Đếm voucher LẦN 1
SELECT COUNT(*) AS total_vouchers
FROM linh_lab.customer_voucher
WHERE voucher_id IN (
    SELECT voucher_id FROM linh_lab.voucher WHERE program_id = 1
);
```
> 🖥️ **DBeaver hiển thị:** Bảng 1 dòng → `total_vouchers` = **N** (VD: `3`) → Ghi nhớ con số này!

⏸️ **Chuyển T2**

**Tab T2:**
```sql
-- 3️⃣ INSERT voucher mới cho program 1 (chạy từng lệnh)
BEGIN;
```
> 🖥️ `BEGIN`

```sql
INSERT INTO linh_lab.customer_voucher
    (customer_id, voucher_id, status_id, saved_at, created_at, created_by)
VALUES
    (1, (SELECT voucher_id FROM linh_lab.voucher WHERE program_id = 1 LIMIT 1),
     1, NOW(), NOW(), 'PHANTOM_TEST');
```
> 🖥️ `INSERT 0 1` — đã insert 1 dòng mới

```sql
COMMIT;
```
> 🖥️ `COMMIT`

⏸️ **Quay lại T1**

**Tab T1:**
```sql
-- 4️⃣ Đếm voucher LẦN 2 (sau khi T2 đã INSERT + COMMIT)
SELECT COUNT(*) AS total_vouchers
FROM linh_lab.customer_voucher
WHERE voucher_id IN (
    SELECT voucher_id FROM linh_lab.voucher WHERE program_id = 1
);
```
> 🖥️ **DBeaver hiển thị:** `total_vouchers` = **N** ✅ (VẪN bằng lần 1, KHÔNG tăng! Bóng ma KHÔNG xuất hiện)

```sql
COMMIT;
```
> 🖥️ `COMMIT`

**Cleanup:**
```sql
DELETE FROM linh_lab.customer_voucher WHERE created_by = 'PHANTOM_TEST';
```
> 🖥️ `DELETE 1`

#### ✅ Check kết quả

| Câu hỏi | Kết quả | Ý nghĩa |
|----------|---------|---------|
| COUNT lần 1 = ? | **N** | Số voucher ban đầu |
| COUNT lần 2 = ? | **N** ✅ (KHÔNG TĂNG) | "Bóng ma" KHÔNG xuất hiện! |

**Điều đó nghĩa là:** Chuẩn SQL nói `REPEATABLE READ` **KHÔNG** chặn Phantom Read. Nhưng PostgreSQL MVCC **mạnh hơn chuẩn** — snapshot-based nên dòng mới từ T2 vô hình với T1.

#### 🐛 Debug

| Vấn đề | Cách sửa |
|--------|----------|
| COUNT lần 2 tăng lên | Bạn quên dùng `REPEATABLE READ` (mặc định là READ COMMITTED) |
| INSERT bị lỗi unique | Chạy cleanup DELETE trước rồi thử lại |

---

### 🔬 STEP 4 — Lost Update

**Câu hỏi cần trả lời:**
"Budget = 10M. TX1 tiêu 1M, TX2 tiêu 2M. Kết quả là 7M (đúng) hay bị mất 1 khoản?"
→ Đây là ví dụ kinh điển về vấn đề **Lost Update** (Mất cập nhật).

#### Tình huống dễ hình dung

- **Ban đầu:** Ngân sách còn **10 triệu**
- **TX1** (Transaction 1): Đọc 10M → Trừ 1M → Update thành **9M**
- **TX2** (Transaction 2): Đọc 10M (vì TX1 chưa commit) → Trừ 2M → Update thành **8M**

→ Kết quả cuối cùng chỉ còn **8M** thay vì **7M** (10M - 1M - 2M).
→ **1 triệu bị "mất"** vì TX2 ghi đè lên kết quả của TX1.

#### Lost Update là gì?

Lost Update xảy ra khi:
1. Hai transaction **cùng đọc giá trị cũ**
2. Cả hai **cùng tính toán** và update
3. Transaction sau **ghi đè** lên transaction trước → **Mất một phần thay đổi**

→ Đây là một trong những bất thường (anomaly) nghiêm trọng nhất trong transaction.

#### Cách khắc phục

Dùng mức isolation cao hơn:
- `REPEATABLE READ` hoặc `SERIALIZABLE`
- Hoặc dùng `SELECT ... FOR UPDATE` (khóa dòng khi đọc)
- Hoặc dùng **Atomic UPDATE**: `SET budget = budget - 1000000` (tốt nhất!)

---

#### Kịch bản A: READ COMMITTED (sẽ bị Lost Update ❌)

**Reset trước:**
```sql
UPDATE linh_lab.promotion_program SET budget_limit = 10000000 WHERE program_id = 1;
```

**Tab T1:**
```sql
-- 1️⃣ Đọc budget
BEGIN;
```
> 🖥️ `BEGIN`

```sql
SELECT budget_limit FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ Bảng 1 dòng → `budget_limit` = **`10000000.00`**
> → Giả lập App tính: 10M - 1M = **9M** (ghi nhớ con số 9M)

⏸️ **DỪNG T1 — Chuyển sang T2**

**Tab T2:**
```sql
-- 2️⃣ T2 cũng đọc budget (CÙNG THỜI ĐIỂM → cùng thấy 10M!)
BEGIN;
```
> 🖥️ `BEGIN`

```sql
SELECT budget_limit FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ Bảng 1 dòng → `budget_limit` = **`10000000.00`** (cùng giá trị với T1!)
> → Giả lập App tính: 10M - 2M = **8M**

```sql
-- 3️⃣ T2 ghi giá trị đã tính
UPDATE linh_lab.promotion_program SET budget_limit = 8000000 WHERE program_id = 1;
```
> 🖥️ `UPDATE 1`

```sql
COMMIT;
```
> 🖥️ `COMMIT`

⏸️ **Quay lại T1**

**Tab T1:**
```sql
-- 4️⃣ T1 ghi giá trị đã tính (DỰA TRÊN DỮ LIỆU CŨ!)
UPDATE linh_lab.promotion_program SET budget_limit = 9000000 WHERE program_id = 1;
```
> 🖥️ `UPDATE 1` — T1 ghi đè lên 8M của T2!

```sql
COMMIT;
```
> 🖥️ `COMMIT`

```sql
-- 5️⃣ Kiểm tra kết quả cuối cùng
SELECT budget_limit FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ `budget_limit` = **`9000000.00`** ❌ — Phải là 7M nhưng lại là 9M → Lost Update!

#### ✅ Check kết quả Kịch bản A

| Câu hỏi | Kết quả | Ý nghĩa |
|----------|---------|---------|
| Budget cuối cùng = ? | **9,000,000** ❌ | SAI! Phải là 7M |
| Khoản tiêu 2M của T2 | **BỊ GHI ĐÈ** | T1 ghi 9M → đè lên 8M của T2 |
| Đúng ra phải là | 10M - 1M - 2M = **7,000,000** | Lost Update! |

**Điều đó nghĩa là:** Pattern "Read → Tính ở App → Write back" tạo **race condition**. Cả 2 TX đọc cùng giá trị cũ (10M), tính toán độc lập, rồi TX sau ghi đè TX trước.

---

#### Kịch bản B: SERIALIZABLE (PostgreSQL sẽ chặn ✅)

**Reset trước:**
```sql
UPDATE linh_lab.promotion_program SET budget_limit = 10000000 WHERE program_id = 1;
```

Làm giống Kịch bản A, nhưng cả 2 tab dùng:
```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
```

**Tab T1:**
```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
```
> 🖥️ `BEGIN`

```sql
SELECT budget_limit FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ `budget_limit` = `10000000.00`

⏸️ **Chuyển T2**

**Tab T2:**
```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
```
> 🖥️ `BEGIN`

```sql
SELECT budget_limit FROM linh_lab.promotion_program WHERE program_id = 1;
```
> 🖥️ `budget_limit` = `10000000.00`

```sql
UPDATE linh_lab.promotion_program SET budget_limit = 8000000 WHERE program_id = 1;
```
> 🖥️ `UPDATE 1`

```sql
COMMIT;
```
> 🖥️ `COMMIT` ✅

⏸️ **Quay lại T1**

**Tab T1:**
```sql
UPDATE linh_lab.promotion_program SET budget_limit = 9000000 WHERE program_id = 1;
```
> 🖥️ ❌ **DBeaver hiển thị lỗi đỏ:**
> `SQL Error [40001]: ERROR: could not serialize access due to concurrent update`
> → Đây là PostgreSQL **chủ động chặn** Lost Update!

```sql
ROLLBACK;  -- Bắt buộc phải ROLLBACK rồi retry
```
> 🖥️ `ROLLBACK`

#### ✅ Check kết quả Kịch bản B

| Câu hỏi | Kết quả | Ý nghĩa |
|----------|---------|---------|
| T1 UPDATE bị lỗi? | **CÓ** — `could not serialize access` | PostgreSQL phát hiện conflict |
| T2 COMMIT thành công? | **CÓ** | Chỉ 1 TX được qua |
| Dữ liệu có bị mất? | **KHÔNG** | PostgreSQL bảo vệ dữ liệu! |

#### 💡 Cách sửa tốt nhất (không cần SERIALIZABLE)

```sql
-- Dùng Atomic UPDATE thay vì "Read → Tính → Write"
UPDATE linh_lab.promotion_program
SET budget_limit = budget_limit - 1000000  -- Atomic!
WHERE program_id = 1;
```

PostgreSQL tự xử lý concurrency ở tầng engine → KHÔNG BAO GIỜ bị Lost Update, dù ở READ COMMITTED.

#### 🐛 Debug

| Vấn đề | Cách sửa |
|--------|----------|
| T1 UPDATE không bị lỗi | Bạn quên dùng `SERIALIZABLE` ở 1 trong 2 tab |
| Budget không phải 10M | Chạy reset trước: `UPDATE ... SET budget_limit = 10000000` |
| T2 bị block (treo) | T1 chưa COMMIT/ROLLBACK → T2 đang chờ lock. Gõ COMMIT/ROLLBACK ở T1 |

---

## 📊 Tổng Kết

| Isolation Level | Dirty Read | Non-Repeatable Read | Phantom Read | Lost Update |
|---|---|---|---|---|
| **READ UNCOMMITTED** * | ❌ Chặn | ⚠️ Cho phép | ⚠️ Cho phép | ⚠️ Cho phép |
| **READ COMMITTED** | ❌ Chặn | ⚠️ Cho phép | ⚠️ Cho phép | ⚠️ Cho phép |
| **REPEATABLE READ** | ❌ Chặn | ❌ Chặn | ❌ Chặn ** | ⚠️ Cho phép |
| **SERIALIZABLE** | ❌ Chặn | ❌ Chặn | ❌ Chặn | ❌ Chặn |

**Ghi chú:**
- \* PostgreSQL tự nâng `READ UNCOMMITTED` lên `READ COMMITTED` (nhờ MVCC)
- \*\* PostgreSQL chặn Phantom Read ở `REPEATABLE READ` (mạnh hơn chuẩn SQL)

---

### Giải thích từng mức

**READ UNCOMMITTED (Thấp nhất)**
- Cho phép đọc tất cả, rất nguy hiểm
- PostgreSQL thực tế nâng lên `READ COMMITTED`

**READ COMMITTED (Mặc định)**
- Chỉ đọc dữ liệu đã commit
- Vẫn cho phép Non-Repeatable Read và Phantom Read

**REPEATABLE READ**
- Đảm bảo đọc nhiều lần cùng 1 dòng → kết quả giống nhau
- Chặn Phantom Read (nhờ snapshot)
- Vẫn có thể bị Lost Update

**SERIALIZABLE (Cao nhất)**
- Transaction chạy như thể tuần tự (không chồng chéo)
- Chặn tất cả bất thường
- Chậm hơn, dễ deadlock

---

## 💡 Tóm tắt dễ nhớ

- **`READ COMMITTED`**: Đủ dùng cho hầu hết trường hợp
- **`REPEATABLE READ`**: Tốt cho báo cáo, đếm số lượng
- **`SERIALIZABLE`**: Dùng khi cần độ chính xác cao (tài chính, đặt vé...)
