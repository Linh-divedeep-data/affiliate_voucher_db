# 📝 Task: DDID-13 · Concurrency Control & Race Conditions (Kiểm soát Tranh chấp & Race Conditions)

## 🎯 Nội dung học tập & Bài học rút ra (Key Learnings)

Khi có hàng ngàn người dùng tương tác đồng thời với cơ sở dữ liệu của bạn, **Bất thường về Tranh chấp (Concurrency Anomalies)** sẽ xảy ra. Hiện tượng phổ biến nhất là **Cập nhật bị mất (Lost Update)** - một dạng Race Condition kinh điển.
Nếu Người dùng A và Người dùng B đều đọc giá trị `total_issued = 100` cùng một lúc và sau đó cả hai cùng cố gắng cộng thêm `1`, cả hai đều tính toán ra kết quả là `101`. Trạng thái cuối cùng của cơ sở dữ liệu sẽ bị ghi nhận là `101` thay vị `102`!

Trong bài thực hành này, bạn sẽ học cách:
1. Mô phỏng Race Condition trong thực tế bằng cách sử dụng hai terminal (SQL session) độc lập.
2. Khắc phục Race Condition bằng cách sử dụng kỹ thuật **Pessimistic Locking (Khóa bi quan)** thông qua câu lệnh `SELECT ... FOR UPDATE`.
3. Hiểu rõ cách PostgreSQL xếp hàng các transaction đang cố gắng truy cập và chỉnh sửa cùng một hàng dữ liệu.

---

## 🗂️ Các bảng Cơ sở dữ liệu liên quan (Tables in Scope)

| Bảng (Table) | Thao tác thực thi (Operation) | Mục tiêu chính (Target Goal) |
|---|---|---|
| `linh_lab.voucher` | `SELECT` và `UPDATE` | Ngăn chặn các transaction đồng thời ghi đè và làm sai lệch kết quả tính toán của nhau |

---

## 🔑 Ngữ cảnh (Context)

Bảng `linh_lab.voucher` của chúng ta có cột `total_issued` ghi nhận số lượng voucher đã được cấp phát. Khi khách hàng nhận voucher, ứng dụng sẽ đọc giá trị `total_issued` hiện tại, cộng thêm `1`, và lưu lại vào database.
Trong một chương trình Flash Sale, hàng trăm khách hàng sẽ nhận voucher trong cùng một mili-giây. Nếu chúng ta không khóa (lock) hàng dữ liệu một cách hợp lý, chúng ta sẽ phát hành nhiều voucher hơn giới hạn cho phép (`issuance_limit`), vượt qua cả ràng buộc check constraint của database do logic tính toán ban đầu đã bị sai lệch!

---

## ✅ BƯỚC 0 — Chuẩn bị (Thiết lập 2 Terminals)

Để mô phỏng môi trường đồng thời (concurrency), bạn phải mở **HAI SQL session độc lập** (Terminal A và Terminal B).
Nếu bạn sử dụng DBeaver hoặc DataGrip, hãy mở hai tab SQL Editor riêng biệt, nhấp chuột phải và đảm bảo chúng đang sử dụng **Isolated Connections** (hoặc chạy client `psql` trên hai cửa sổ terminal riêng biệt).

**Lấy voucher mục tiêu để thử nghiệm:**
```sql
SELECT voucher_id, voucher_code, total_issued 
FROM linh_lab.voucher 
LIMIT 1;
```
> Ghi lại `voucher_id` và giá trị `total_issued` hiện tại. Sử dụng `voucher_id` này cho cả hai terminal dưới đây.

---

## 🔬 Chi tiết các Kịch bản Thực hành (Scenarios)

### Kịch bản A — Thảm họa "Lost Update" (Không sử dụng Khóa)

**Terminal A:**
```sql
BEGIN;
-- Terminal A đọc giá trị hiện tại (ví dụ: 50)
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = :voucher_id;
-- CHƯA commit vội!
```

**Terminal B:**
```sql
BEGIN;
-- Terminal B đọc cùng giá trị hiện tại (vẫn thấy là 50)
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = :voucher_id;
-- CHƯA commit vội!
```

**Terminal A:**
```sql
-- Terminal A nghĩ giá trị là 50, nên tính toán 50 + 10 = 60
UPDATE linh_lab.voucher SET total_issued = 60 WHERE voucher_id = :voucher_id;
COMMIT;
```

**Terminal B:**
```sql
-- Terminal B vẫn nghĩ giá trị là 50, nên cũng tính toán 50 + 10 = 60 và cập nhật
UPDATE linh_lab.voucher SET total_issued = 60 WHERE voucher_id = :voucher_id;
COMMIT;
```

**Xác minh kết quả (Chạy ở bất kỳ terminal nào):**
```sql
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = :voucher_id;
```
> **Vấn đề xảy ra:** Chúng ta đã cộng thêm 10 hai lần, do đó kết quả đúng phải là `50 + 20 = 70`. Tuy nhiên cơ sở dữ liệu chỉ hiển thị `60`! Lệnh cập nhật của Terminal B đã hoàn toàn ghi đè và làm mất công sức của Terminal A. Đây chính là lỗi **Lost Update** (Cập nhật bị mất).

---

### Kịch bản B — Giải pháp Khắc phục (`SELECT ... FOR UPDATE`)

Chúng ta sẽ sử dụng một cơ chế khóa dòng **Row-Level Mutex (Mutual Exclusion)**. Transaction đầu tiên đọc dòng dữ liệu sẽ khóa (lock) nó lại. Bất kỳ transaction nào khác cố gắng đọc dòng dữ liệu đó *để cập nhật* sẽ phải xếp hàng chờ đợi.

**Terminal A:**
```sql
BEGIN;
-- Terminal A đọc VÀ KHÓA hàng dữ liệu này lại
SELECT total_issued FROM linh_lab.voucher 
WHERE voucher_id = :voucher_id 
FOR UPDATE;
-- CHƯA commit vội!
```

**Terminal B:**
```sql
BEGIN;
-- Terminal B cố gắng đọc và khóa hàng dữ liệu đó
SELECT total_issued FROM linh_lab.voucher 
WHERE voucher_id = :voucher_id 
FOR UPDATE;
-- ⏳ QUAN SÁT: Terminal B bị "treo" (hang). Session này bị block và phải chờ Terminal A giải phóng khóa!
```

**Terminal A:**
```sql
-- Terminal A thực hiện cập nhật (ví dụ: 60 + 10 = 70)
UPDATE linh_lab.voucher SET total_issued = total_issued + 10 WHERE voucher_id = :voucher_id;
COMMIT;
-- ⚡ QUAN SÁT: Ngay khi Terminal A COMMIT, Terminal B lập tức được giải phóng (unblocked)!
```

**Terminal B:**
```sql
-- Terminal B được giải phóng. Nó tự động đọc lại dòng và thấy giá trị mới nhất là 70!
-- Lúc này Terminal B thực hiện cập nhật an toàn dựa trên dữ liệu mới (70 + 10 = 80).
UPDATE linh_lab.voucher SET total_issued = total_issued + 10 WHERE voucher_id = :voucher_id;
COMMIT;
```

**Xác minh kết quả:**
```sql
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = :voucher_id;
```
> **Kết quả:** Trạng thái cuối cùng là `80`. Không có bản cập nhật nào bị mất! Từ khóa `FOR UPDATE` đã bắt Terminal B phải đợi cho đến khi Terminal A hoàn tất công việc của mình.

---

### Kịch bản C — Khóa chết (Deadlock - Voucher Exchange)

**Khái niệm:** Hai khách hàng muốn trao đổi voucher cho nhau. Hệ thống cố gắng khóa cả hai hàng dữ liệu. Nếu hệ thống thực hiện khóa theo các thứ tự trái ngược nhau, toàn bộ database engine có thể bị đóng băng trong trạng thái "Deadlock" (Khóa chết). Hãy xem cách PostgreSQL phát hiện và xử lý lỗi này một cách mạnh mẽ.

*Chuẩn bị: Chọn HAI `voucher_id` khác nhau (ví dụ: ID 1 và ID 2).*

**Terminal A:**
```sql
BEGIN;
-- Khóa Voucher 1
SELECT * FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;
```

**Terminal B:**
```sql
BEGIN;
-- Khóa Voucher 2
SELECT * FROM linh_lab.voucher WHERE voucher_id = 2 FOR UPDATE;
```

**Terminal A:**
```sql
-- Bây giờ Terminal A cố gắng khóa Voucher 2 (Sẽ bị treo vì chờ B giải phóng)
SELECT * FROM linh_lab.voucher WHERE voucher_id = 2 FOR UPDATE;
```

**Terminal B:**
```sql
-- Terminal B cố gắng khóa Voucher 1
SELECT * FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;
```

> **⚡ KẾT QUẢ:** PostgreSQL ngay lập tức phát hiện ra sự phụ thuộc vòng lặp (circular dependency)! Nó sẽ chấm dứt (abort) một trong hai transaction và trả về lỗi: `ERROR: deadlock detected`.

---

### Kịch bản D — Phá vỡ Hàng đợi khóa (`NOWAIT`)

**Khái niệm:** Trong một chương trình Flash Sale lớn, nếu 10,000 người dùng cố gắng khóa cùng một voucher, 9,999 người sẽ bị đưa vào hàng đợi và bị treo session. Điều này làm cạn kiệt Connection Pool của database và có thể làm sập toàn bộ Web Server!
Thay vì chờ đợi vô hạn, chúng ta muốn "Thất bại nhanh" (Fail Fast) để ứng dụng có thể hiển thị thông báo: *"Hệ thống đang bận, vui lòng thử lại sau."*

**Terminal A:**
```sql
BEGIN;
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;
-- Terminal A đang giữ khóa.
```

**Terminal B:**
```sql
BEGIN;
-- Thay vì bị treo chờ đợi, Terminal B yêu cầu lấy khóa NGAY LẬP TỨC hoặc bỏ qua!
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE NOWAIT;
```

> **Kết quả:** Thay vì treo vô hạn, Terminal B lập tức báo lỗi: `ERROR: could not obtain lock on row in relation "voucher"`. Đây chính xác là những gì một hệ thống có tính chịu tải cao (High-Scalability) cần!

---

### Kịch bản E — Flash Sale 500-Request (Kiểm thử hiệu năng bằng pgbench)

**Khái niệm:** Việc kiểm thử bằng 2 Terminal rất tốt để học tập, nhưng điều gì xảy ra khi có **500 request đồng thời** đổ bộ vào database? Chúng ta sẽ sử dụng công cụ kiểm thử hiệu năng tích hợp sẵn của PostgreSQL là `pgbench` để giả lập một đợt Flash Sale lớn và chứng minh rằng cơ chế khóa `FOR UPDATE` có thể chịu tải thành công.

**Bước 1:** Tạo một file chứa logic khóa bảo mật tại đầu đường dẫn: `sql/marketing/flash_sale_test.sql` (và sao chép vào `tasks/ddid13_concurrency/flash_sale_test.sql`):
```sql
BEGIN;
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;
UPDATE linh_lab.voucher SET total_issued = total_issued + 1 WHERE voucher_id = 1;
COMMIT;
```

**Bước 2:** Đặt lại (Reset) giá trị `total_issued` của voucher về `0` trong SQL Editor:
```sql
UPDATE linh_lab.voucher SET total_issued = 0 WHERE voucher_id = 1;
```

**Bước 3:** Mở Terminal hệ thống của bạn (Bash / Zsh / Command Prompt) và chạy lệnh `pgbench` dưới đây để giả lập 100 người dùng đồng thời, mỗi người nhấn "Nhận voucher" 5 lần (tổng cộng 500 request):
```bash
pgbench -U postgres -d postgres -c 100 -t 5 -f tasks/ddid13_concurrency/flash_sale_test.sql
```
*(Lưu ý: Thay đổi `-U postgres -d postgres` bằng thông tin tài khoản và database thực tế của bạn nếu cần, ví dụ: `-d ecommerce_db`).*

**Bước 4:** Kiểm tra lại database.
Nhờ việc sử dụng khóa `FOR UPDATE`, giá trị `total_issued` cuối cùng sẽ là **chính xác 500**. Không có cập nhật nào bị mất, không bị crash! (Nếu bạn thử bỏ dòng `FOR UPDATE` trong script và chạy lại, giá trị cuối cùng sẽ bị sai lệch hoàn toàn và không thể dự đoán trước).

---

### Kịch bản F — Tấm khiên tối thượng (Mức cô lập SERIALIZABLE)

**Khái niệm:** Cho đến nay, chúng ta đã dùng `FOR UPDATE` (Khóa bi quan) để khắc phục Race Condition. Nhưng PostgreSQL cung cấp một "tấm khiên" tích hợp sẵn giúp ngăn chặn các bất thường này mà không cần sử dụng khóa rõ ràng: **Mức cô lập giao dịch (Isolation Levels)**.
Mức cô lập mặc định là `READ COMMITTED` (gây ra lỗi Lost Update trong Kịch bản A). Bây giờ, hãy thử nâng lên mức nghiêm ngặt nhất: `SERIALIZABLE`.

**Terminal A:**
```sql
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Một câu lệnh SELECT bình thường, KHÔNG dùng khóa "FOR UPDATE"!
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;
-- Giả sử trả về 500
```

**Terminal B:**
```sql
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- SELECT bình thường
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;
-- Cũng trả về 500
```

**Terminal A:**
```sql
-- Ứng dụng tính toán 500 + 10 = 510
UPDATE linh_lab.voucher SET total_issued = 510 WHERE voucher_id = 1;
COMMIT;
-- Thành công!
```

**Terminal B:**
```sql
-- Ứng dụng cũng tính toán 500 + 10 = 510 và chạy lệnh update
UPDATE linh_lab.voucher SET total_issued = 510 WHERE voucher_id = 1;
-- ⚡ BÙNG NỔ: Terminal B lập tức gặp lỗi và bị hủy bỏ!
-- ERROR: could not serialize access due to concurrent update
```

> **Bài học rút ra:** Mức cô lập `SERIALIZABLE` hoạt động như một cơ chế **Khóa lạc quan (Optimistic Lock)**. Nó cho phép mọi người đọc dữ liệu tự do, nhưng ngay khi một transaction cố gắng commit một bản cập nhật xung đột với transaction đã commit trước đó, PostgreSQL sẽ lập tức hủy bỏ (abort) transaction đi sau! Điều này giúp ngăn chặn hoàn toàn lỗi Lost Update mà không cần viết lệnh khóa `FOR UPDATE` thủ công.

---

## 💬 Câu hỏi Phản tư & Trả lời (Reflection Q&A)

### Câu hỏi 1:
> Trong Kịch bản B, điều gì xảy ra nếu Terminal A thực hiện `SELECT FOR UPDATE` nhưng sau đó máy tính của lập trình viên bị sập nguồn (crash) trước khi chạy lệnh `COMMIT;`? Terminal B có bị treo vĩnh viễn không? PostgreSQL xử lý tình huống này thế nào?

* **Trả lời:**
  * **Không bị treo vĩnh viễn:** Terminal B sẽ không bị treo mãi mãi.
  * **Cơ chế phát hiện mất kết nối:** PostgreSQL server quản lý kết nối client rất chặt chẽ. Khi laptop client bị sập hoặc mất mạng, PostgreSQL sẽ phát hiện ra kết nối TCP bị ngắt (thông qua cơ chế TCP Keepalive).
  * **Dọn dẹp tài nguyên:** PostgreSQL sẽ tự động hủy session backend tương ứng với Terminal A, thực hiện `ROLLBACK` các thay đổi chưa commit của transaction đó và giải phóng toàn bộ các lock (khóa dòng) đang giữ.
  * **Giải phóng hàng đợi:** Ngay khi khóa của Terminal A được giải phóng, Terminal B đang đợi trong hàng sẽ được unblocked và tiếp tục thực thi.
  * **Cấu hình bổ sung:** Lập trình viên cũng có thể cấu hình thông số `idle_in_transaction_session_timeout` của PostgreSQL để tự động ngắt các transaction bị treo quá lâu mà không có câu lệnh mới, ngăn chặn việc giữ lock vô hạn.

### Câu hỏi 2:
> Trong Kịch bản C (Deadlock), các nhà phát triển nên cấu trúc các câu lệnh SQL của họ như thế nào trong mã nguồn ứng dụng để đảm bảo deadlock KHÔNG BAO GIỜ xảy ra, ngay cả khi cập nhật nhiều hàng dữ liệu?

* **Trả lời:**
  * **Quy tắc sắp xếp thứ tự khóa (Strict Resource Ordering):** Cách tối ưu nhất để loại bỏ hoàn toàn khả năng xảy ra deadlock là đảm bảo mọi transaction luôn yêu cầu khóa các tài nguyên theo một **thứ tự nhất quán duy nhất** (ví dụ: sắp xếp tăng dần theo cột khóa chính `voucher_id`).
    Ví dụ, thay vì lock lộn xộn, hãy luôn chạy:
    `SELECT * FROM linh_lab.voucher WHERE voucher_id IN (1, 2) ORDER BY voucher_id ASC FOR UPDATE;`
  * **Thứ tự khóa giữa các bảng:** Nếu transaction tác động lên nhiều bảng, tất cả các luồng xử lý/API trong ứng dụng phải truy cập và khóa các bảng đó theo đúng một trình tự cố định (ví dụ: luôn là bảng `promotion_program` trước ➡️ `voucher` ➡️ `customer_voucher`).
  * **Thu hẹp phạm vi transaction:** Giữ transaction ngắn nhất có thể để giảm thiểu thời gian chiếm giữ khóa.
  * **Cơ chế Retry (Thử lại):** Ứng dụng nên cài đặt khối mã bắt lỗi ngoại lệ (exception handling) để tự động thực hiện lại transaction với thuật toán exponential backoff nếu gặp lỗi deadlock hoặc serialization.

### Câu hỏi 3:
> Trong một sự kiện Flash Sale cực kỳ lớn (1 triệu người mua 1000 món hàng trong 1 giây), ngay cả tùy chọn `NOWAIT` cũng có thể làm quá tải database với hàng loạt log lỗi. Các kỹ sư dữ liệu thường sử dụng công nghệ bộ nhớ đệm (caching) bên ngoài nào trước database để xử lý Flash Sales?

* **Trả lời:**
  * **In-Memory Caching (Redis / KeyDB / Dragonfly):** 
    - Đặt Redis làm lá chắn phía trước database chính để quản lý và kiểm tra số lượng tồn kho (hoặc lượt cấp phát voucher) với hiệu năng cực cao (hàng chục/trăm ngàn request mỗi giây).
    - Sử dụng các lệnh nguyên tử (Atomic operations) của Redis như `DECR` hoặc viết script Lua để kiểm tra và trừ kho một cách an sau mà không cần khóa ở mức database.
    - Sử dụng Redis Distributed Lock (như thuật toán Redlock) khi cần khóa phân tán.
  * **Hàng đợi thông điệp (Message Queues - Kafka / RabbitMQ / AWS SQS):**
    - Khi Redis xác nhận yêu cầu claim hợp lệ, yêu cầu đó sẽ được ném vào hàng đợi (Queue).
    - Các worker phía sau sẽ tiêu thụ hàng đợi và ghi nhận thông tin mua hàng vào PostgreSQL một cách bất đồng bộ (Write-Behind pattern) với tốc độ được kiểm soát, tránh làm nghẽn hoặc sập database.
  * **Bộ giới hạn tần suất (Rate Limiters):**
    - Áp dụng các thuật toán như Leaky Bucket hay Token Bucket tại tầng API Gateway để lọc bớt và loại bỏ các request vượt ngưỡng chịu tải trước khi chúng chạm đến database.

---

## 📦 File Deliverable

Sản phẩm của bài tập được lưu trữ tại:
```
tasks/ddid13_concurrency/DDID13_04_concurrency_control.sql
```
