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

## 💡 Bài học rút ra

1. **PostgreSQL an toàn hơn chuẩn SQL:** MVCC chặn Dirty Read ở mọi level, chặn Phantom Read ở REPEATABLE READ
2. **Atomic UPDATE tốt hơn Read-Calculate-Write:** `SET budget = budget - 1000` tốt hơn `SELECT → App tính → UPDATE`
3. **SERIALIZABLE cần retry:** Khi bị `serialization error`, ứng dụng phải retry transaction
4. **Mặc định là đủ:** `READ COMMITTED` + Atomic UPDATE giải quyết 90% trường hợp
