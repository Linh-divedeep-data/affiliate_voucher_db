# 🎫 Affiliate Voucher Database System

Hệ thống cơ sở dữ liệu quản lý chiến dịch tiếp thị liên kết (Affiliate Marketing) và cấp phát mã giảm giá (Voucher Program), được phát triển trên hệ quản trị cơ sở dữ liệu PostgreSQL.

---

## 🏗️ Kiến trúc dự án (Project Architecture)

Thư mục dự án được cấu trúc như sau:

```text
├── database/
│   ├── DDL.sql        # Định nghĩa cấu trúc bảng (Schema: linh_lab) và các ràng buộc vật lý
│   └── seed.sql       # Dữ liệu thử nghiệm ban đầu (Seed data)
└── tasks/
    ├── ddid10_crud_autocommit/
    │   ├── DDID10_01_crud_operations.sql    # Thao tác CRUD cơ bản và cơ chế Autocommit
    │   └── README.md                        # Tài liệu hướng dẫn & giải thích chi tiết
    ├── ddid11_transactions/
    │   ├── DDID11_02_transaction_blocks.sql # Khối giao dịch đa bước (COMMIT, ROLLBACK, SAVEPOINT)
    │   └── README.md                        # Hướng dẫn chi tiết luồng kiểm thử giao dịch
    ├── ddid12_constraints/
    │   ├── DDID12_03_constraints_consistency.sql # Kiểm chứng ràng buộc & tính toàn vẹn dữ liệu
    │   └── README.md                             # Giải thích và bài học thực tiễn về ràng buộc
    └── ddid13_concurrency/
        ├── DDID13_04_concurrency_control.sql # Script kiểm soát tranh chấp và race conditions
        └── README.md                         # Tài liệu hướng dẫn về Concurrency Control
```

---

## 🚀 Hướng dẫn khởi tạo và thiết lập nhanh (Quick Start Guide)

Để khởi tạo lại toàn bộ cơ sở dữ liệu và dữ liệu thử nghiệm, hãy chạy các lệnh sau trong Terminal (đảm bảo đã cài đặt PostgreSQL client `psql`):

### 1. Tạo Schema và các bảng vật lý
```bash
psql -d postgres -f database/DDL.sql
```

### 2. Nạp dữ liệu thử nghiệm (Seed Data)
```bash
psql -d postgres -f database/seed.sql
```

---

## 🔬 Chi tiết các bài thực hành (Tasks & Labs)

### 1. [Task 10: Thao tác CRUD & Autocommit](file:///Users/anhtran/Desktop/Affiliate_voucher_db/affiliate_voucher_db/tasks/ddid10_crud_autocommit/README.md)
* **Khái niệm cốt lõi:** Cách hoạt động của chế độ Autocommit mặc định trong SQL client.
* **Hoạt động thực tế:** `INSERT`, `UPDATE`, `DELETE` và `SELECT` các thông tin khách hàng, đối tác, chương trình khuyến mãi.

### 2. [Task 11: Giao dịch đa bước (COMMIT, ROLLBACK, SAVEPOINT)](file:///Users/anhtran/Desktop/Affiliate_voucher_db/affiliate_voucher_db/tasks/ddid11_transactions/README.md)
* **Khái niệm cốt lõi:** Tính nguyên tử (Atomicity), kỹ thuật xâu chuỗi ID thông qua `RETURNING`, xử lý khôi phục từng phần bằng `SAVEPOINT`.
* **Kịch bản kiểm thử:**
  * **Kịch bản A:** Chuỗi đăng ký tài khoản ➡️ gán voucher ➡️ trừ ngân sách thành công (`COMMIT`).
  * **Kịch bản B:** Lỗi vi phạm ràng buộc số tiền ở bước cuối ➡️ tự động hoàn trả toàn bộ (`ROLLBACK`).
  * **Kịch bản C:** Nhập sai mã voucher ➡️ rollback về savepoint trước đó ➡️ nhập lại voucher đúng và lưu thành công.

### 3. [Task 12: Ràng buộc & Tính toàn vẹn dữ liệu](file:///Users/anhtran/Desktop/Affiliate_voucher_db/affiliate_voucher_db/tasks/ddid12_constraints/README.md)
* **Khái niệm cốt lõi:** Thiết lập `CHECK constraints`, `FOREIGN KEY` cascade actions, `UNIQUE constraints` phục vụ nghiệp vụ tiếp thị và chống gian lận (fraud-detection).

### 4. [Task 13: Concurrency Control & Race Conditions](file:///Users/anhtran/Desktop/Affiliate_voucher_db/affiliate_voucher_db/tasks/ddid13_concurrency/README.md)
* **Khái niệm cốt lõi:** Kiểm soát tranh chấp (Concurrency Control), hiện tượng Lost Update, Pessimistic Locking (`SELECT ... FOR UPDATE`), cơ chế hàng đợi khóa của PostgreSQL, Deadlock và xử lý quá tải hàng đợi khóa (`NOWAIT`).
