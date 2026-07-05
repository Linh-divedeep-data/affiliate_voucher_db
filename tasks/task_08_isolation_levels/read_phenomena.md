# 📊 Bài 8 — Read Phenomena Timeline

Tài liệu này chứa **4 bảng Timeline** mô phỏng chính xác thứ tự thời gian của các hiện tượng đọc sai lệch (Read Phenomena) khi 2 Transaction chạy song song.

> **Cách đọc Timeline:** Mỗi dòng là một mốc thời gian (t0, t1, ...). Đọc từ trên xuống dưới để hiểu thứ tự chạy lệnh giữa Terminal 1 (TX1) và Terminal 2 (TX2).

---

## Step 1 — Dirty Read Timeline

🎯 **Câu hỏi:** PostgreSQL có bị Dirty Read ở `READ UNCOMMITTED` không?

| Time | Terminal 1 (TX1) | Terminal 2 (TX2) |
|------|-----------------|-----------------|
| **t0** | `SELECT budget_limit WHERE program_id=1;` → **50,000,000** | |
| **t1** | `BEGIN ISOLATION LEVEL READ UNCOMMITTED;` | |
| **t2** | `UPDATE budget_limit = 999,999,999 WHERE program_id=1;` *(chưa COMMIT)* | |
| **t3** | | `BEGIN ISOLATION LEVEL READ UNCOMMITTED;` |
| **t4** | | `SELECT budget_limit WHERE program_id=1;` → **50,000,000** ✅ |
| **t5** | `ROLLBACK;` *(hủy bỏ 999,999,999)* | |
| **t6** | | `COMMIT;` |

### 📝 Nhận xét

**Kết quả:** TX2 **KHÔNG** thấy dữ liệu rác (999,999,999). Vẫn thấy giá trị gốc 50,000,000.

**Tại sao?** PostgreSQL sử dụng kiến trúc **MVCC (Multi-Version Concurrency Control)**:
- Mỗi transaction nhìn thấy một **snapshot** riêng của dữ liệu
- Dù set `READ UNCOMMITTED`, PostgreSQL **tự động nâng lên `READ COMMITTED`**
- Dữ liệu uncommitted của TX1 **không bao giờ** hiển thị cho TX2

> **Kết luận:** PostgreSQL **miễn nhiễm** với Dirty Read ở **MỌI** isolation level. Đây là điểm mạnh so với MySQL (InnoDB có thể bị Dirty Read ở READ UNCOMMITTED).

---

## Step 2 — Non-Repeatable Read Timeline

🎯 **Câu hỏi:** Cùng 1 SELECT chạy 2 lần trong 1 transaction có trả kết quả khác nhau không?

### Kịch bản A: `READ COMMITTED` (BỊ LỖI ⚠️)

| Time | Terminal 1 (TX1) — READ COMMITTED | Terminal 2 (TX2) |
|------|----------------------------------|-----------------|
| **t0** | `BEGIN;` | |
| **t1** | `SELECT budget_limit WHERE program_id=1;` → **50,000,000** ✅ | |
| **t2** | | `BEGIN;` |
| **t3** | | `UPDATE budget_limit = budget_limit - 5,000,000 WHERE program_id=1;` |
| **t4** | | `COMMIT;` *(thay đổi chính thức: 45,000,000)* |
| **t5** | `SELECT budget_limit WHERE program_id=1;` → **45,000,000** ⚠️ | |
| **t6** | `COMMIT;` | |

**Phân tích:**
- t1: TX1 đọc = 50M ✅
- t4: TX2 COMMIT thay đổi
- t5: TX1 đọc lại = **45M** ⚠️ — giá trị bị thay đổi dù TX1 chưa làm gì!
- → **Non-Repeatable Read xảy ra!**

**Nguyên nhân:** `READ COMMITTED` lấy snapshot **MỚI NHẤT** mỗi lần SELECT. Khi TX2 đã COMMIT, SELECT tiếp theo của TX1 sẽ thấy giá trị mới.

---

### Kịch bản B: `REPEATABLE READ` (ĐÃ SỬA ✅)

| Time | Terminal 1 (TX1) — REPEATABLE READ | Terminal 2 (TX2) |
|------|-----------------------------------|-----------------|
| **t0** | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | |
| **t1** | `SELECT budget_limit WHERE program_id=1;` → **50,000,000** ✅ | |
| **t2** | | `BEGIN;` |
| **t3** | | `UPDATE budget_limit = budget_limit - 5,000,000 WHERE program_id=1;` |
| **t4** | | `COMMIT;` *(thay đổi chính thức: 45,000,000)* |
| **t5** | `SELECT budget_limit WHERE program_id=1;` → **50,000,000** ✅ | |
| **t6** | `COMMIT;` | |

**Phân tích:**
- t1: TX1 đọc = 50M ✅
- t4: TX2 COMMIT thay đổi
- t5: TX1 đọc lại = **50M** ✅ — giá trị KHÔNG ĐỔI!
- → **REPEATABLE READ chặn được Non-Repeatable Read!**

**Nguyên nhân:** `REPEATABLE READ` dùng **snapshot cố định** tại thời điểm BEGIN (t0). Mọi SELECT trong transaction đều nhìn cùng 1 snapshot → kết quả luôn nhất quán.

---

## Step 3 — Phantom Read Timeline

🎯 **Câu hỏi:** TX2 INSERT dòng mới + COMMIT, TX1 đếm lại có thấy "bóng ma" không?

| Time | Terminal 1 (TX1) — REPEATABLE READ | Terminal 2 (TX2) |
|------|-----------------------------------|-----------------|
| **t0** | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | |
| **t1** | `SELECT COUNT(*) FROM customer_voucher WHERE voucher_id IN (SELECT voucher_id FROM voucher WHERE program_id=1);` → **N** (ví dụ: 3) | |
| **t2** | | `BEGIN;` |
| **t3** | | `INSERT INTO customer_voucher (...) VALUES (...);` *(thêm voucher cho program 1)* |
| **t4** | | `COMMIT;` *(dòng mới chính thức tồn tại)* |
| **t5** | `SELECT COUNT(*) FROM customer_voucher WHERE voucher_id IN (SELECT voucher_id FROM voucher WHERE program_id=1);` → **N** ✅ *(KHÔNG TĂNG!)* | |
| **t6** | `COMMIT;` | |

**Phân tích:**
- t1: TX1 đếm = N ✅
- t4: TX2 INSERT + COMMIT (dòng mới tồn tại trong DB)
- t5: TX1 đếm lại = **N** ✅ — "bóng ma" KHÔNG xuất hiện!
- → **PostgreSQL MVCC chặn được Phantom Read ở REPEATABLE READ!**

**Nguyên nhân:** Snapshot của TX1 được tạo tại t0. Dòng mới INSERT bởi TX2 ở t3 **KHÔNG NẰM TRONG snapshot** của TX1 → TX1 không nhìn thấy.

> **Đặc biệt:** Chuẩn SQL (ANSI SQL) nói `REPEATABLE READ` **KHÔNG** chặn Phantom Read. Nhưng PostgreSQL MVCC **mạnh hơn chuẩn** — chặn được! Đây là ưu điểm kiến trúc snapshot-based so với lock-based (SQL Server, MySQL).

### Bonus: Nếu TX1 chạy UPDATE trên tất cả voucher?

```sql
-- Trong TX1 (sau t5):
UPDATE linh_lab.customer_voucher
SET    status_id = 2
WHERE  voucher_id IN (
    SELECT voucher_id FROM linh_lab.voucher WHERE program_id = 1
);
```

PostgreSQL sẽ phát hiện **write conflict** với dòng mới của TX2 → `ERROR: could not serialize access due to concurrent update`. TX1 phải ROLLBACK và retry.

---

## Step 4 — Lost Update Timeline

🎯 **Câu hỏi:** 2 TX cùng đọc, cùng tính, cùng ghi → khoản tiêu nào bị "bốc hơi"?

### Kịch bản A: `READ COMMITTED` (BỊ LOST UPDATE ❌)

**Điều kiện:** `budget_limit = 10,000,000`. TX1 tiêu 1M. TX2 tiêu 2M. Đúng ra phải còn 7M.

| Time | Terminal 1 (TX1) | Terminal 2 (TX2) |
|------|-----------------|-----------------|
| **t0** | `BEGIN;` | |
| **t1** | `SELECT budget_limit WHERE program_id=1;` → **10,000,000** | |
| **t2** | *App tính: 10M - 1M = 9M* | |
| **t3** | | `BEGIN;` |
| **t4** | | `SELECT budget_limit WHERE program_id=1;` → **10,000,000** |
| **t5** | | *App tính: 10M - 2M = 8M* |
| **t6** | | `UPDATE budget_limit = 8,000,000 WHERE program_id=1;` |
| **t7** | | `COMMIT;` |
| **t8** | `UPDATE budget_limit = 9,000,000 WHERE program_id=1;` | |
| **t9** | `COMMIT;` | |
| **t10** | **Database: budget_limit = 9,000,000** ❌ | |

**Phân tích:**
- t1: TX1 đọc 10M → tính 10M - 1M = 9M
- t4: TX2 đọc 10M (cùng giá trị!) → tính 10M - 2M = 8M
- t7: TX2 ghi 8M → COMMIT
- t8: TX1 ghi 9M → **GHI ĐÈ** lên 8M của TX2!
- **Kết quả:** 9,000,000 thay vì 7,000,000
- → **Khoản tiêu 2,000,000 của TX2 bị BỐC HƠI (Lost Update)!**

**Nguyên nhân:** Pattern "Read → Calculate at App → Write back" (đọc → tính ở ứng dụng → ghi lại) tạo **race condition**. Cả 2 TX đọc cùng giá trị cũ, tính toán độc lập, rồi ghi đè lên nhau.

---

### Kịch bản B: `SERIALIZABLE` (PostgreSQL CHẶN ✅)

| Time | Terminal 1 (TX1) — SERIALIZABLE | Terminal 2 (TX2) — SERIALIZABLE |
|------|-------------------------------|-------------------------------|
| **t0** | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | |
| **t1** | `SELECT budget_limit WHERE program_id=1;` → **10,000,000** | |
| **t2** | | `BEGIN ISOLATION LEVEL SERIALIZABLE;` |
| **t3** | | `SELECT budget_limit WHERE program_id=1;` → **10,000,000** |
| **t4** | | `UPDATE budget_limit = 8,000,000 WHERE program_id=1;` |
| **t5** | | `COMMIT;` ✅ |
| **t6** | `UPDATE budget_limit = 9,000,000 WHERE program_id=1;` | |
| **t7** | ❌ `ERROR: could not serialize access due to concurrent update` | |
| **t8** | `ROLLBACK;` *(phải retry transaction)* | |

**Phân tích:**
- t5: TX2 COMMIT thành công
- t6: TX1 cố UPDATE → PostgreSQL phát hiện **conflict** (cùng dòng đã bị TX2 thay đổi)
- t7: **BẮN LỖI** → TX1 phải ROLLBACK và retry
- → **SERIALIZABLE chặn được Lost Update!**

---

### Cách sửa đúng: Atomic UPDATE (Best Practice)

Thay vì "Read → Calculate → Write", dùng **atomic UPDATE**:

```sql
-- TX1:
UPDATE linh_lab.promotion_program
SET    budget_limit = budget_limit - 1000000   -- Atomic!
WHERE  program_id = 1;

-- TX2:
UPDATE linh_lab.promotion_program
SET    budget_limit = budget_limit - 2000000   -- Atomic!
WHERE  program_id = 1;
```

PostgreSQL tự xử lý concurrency ở tầng engine → **KHÔNG BAO GIỜ** bị Lost Update, dù ở `READ COMMITTED`.

---

## 📊 Tổng Kết: Isolation Levels trong PostgreSQL

| Isolation Level | Dirty Read | Non-Repeatable Read | Phantom Read | Lost Update |
|---|---|---|---|---|
| **READ UNCOMMITTED** * | ❌ Chặn | ⚠️ Cho phép | ⚠️ Cho phép | ⚠️ Cho phép |
| **READ COMMITTED** | ❌ Chặn | ⚠️ Cho phép | ⚠️ Cho phép | ⚠️ Cho phép |
| **REPEATABLE READ** | ❌ Chặn | ❌ Chặn | ❌ Chặn ** | ⚠️ Cho phép |
| **SERIALIZABLE** | ❌ Chặn | ❌ Chặn | ❌ Chặn | ❌ Chặn |

> \* PostgreSQL tự nâng `READ UNCOMMITTED` → `READ COMMITTED` (nhờ MVCC)
> \*\* PostgreSQL chặn Phantom Read ở `REPEATABLE READ` nhờ snapshot MVCC (mạnh hơn chuẩn SQL yêu cầu)

### Best Practice

| Tình huống | Isolation Level khuyến nghị | Lý do |
|---|---|---|
| Hầu hết trường hợp | `READ COMMITTED` (mặc định) + Atomic UPDATE | Đơn giản, hiệu năng cao |
| Báo cáo tài chính cần consistency | `REPEATABLE READ` | Snapshot cố định trong suốt transaction |
| Quy trình nghiệp vụ quan trọng | `SERIALIZABLE` + retry logic | Chống Lost Update, nhưng cần handle serialization error |
