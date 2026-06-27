-- ============================================================================
-- TASK: DDID-13 · Concurrency Control & Race Conditions (Kiểm soát Tranh chấp & Race Conditions)
-- DELIVERABLE: tasks/ddid13_concurrency/DDID13_04_concurrency_control.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ✅ BƯỚC 0 — Chuẩn bị (Thiết lập 2 Terminals)
-- Chạy câu lệnh dưới đây để chọn một voucher_id làm mục tiêu thử nghiệm.
-- ----------------------------------------------------------------------------
-- SELECT voucher_id, voucher_code, total_issued 
-- FROM linh_lab.voucher 
-- LIMIT 1;
-- Giả sử chúng ta chọn được voucher_id = 1 và sẽ sử dụng nó cho các kịch bản dưới đây.


-- ============================================================================
-- 🔬 Kịch bản A — Thảm họa "Lost Update" (Không sử dụng khóa)
-- Mô tả: Minh họa việc các bản cập nhật đồng thời ghi đè và làm mất dữ liệu của nhau.
-- ============================================================================

-- ------------------
-- [TERMINAL A - Bước 1]
-- ------------------
-- Bắt đầu transaction và đọc giá trị hiện tại (ví dụ: total_issued đang là 50)
BEGIN;
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;

-- ------------------
-- [TERMINAL B - Bước 2]
-- ------------------
-- Bắt đầu transaction và đọc cùng giá trị hiện tại (vẫn thấy là 50)
BEGIN;
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;

-- ------------------
-- [TERMINAL A - Bước 3]
-- ------------------
-- Cập nhật giá trị dựa trên số đã đọc được (50 + 10 = 60) và commit
UPDATE linh_lab.voucher SET total_issued = 60 WHERE voucher_id = 1;
COMMIT;

-- ------------------
-- [TERMINAL B - Bước 4]
-- ------------------
-- Cập nhật giá trị dựa trên số cũ đã đọc từ trước (vẫn lấy 50 + 10 = 60) và commit.
-- Hành động này hoàn toàn ghi đè và làm mất thay đổi của Terminal A!
UPDATE linh_lab.voucher SET total_issued = 60 WHERE voucher_id = 1;
COMMIT;

-- ------------------
-- [XÁC MINH]
-- ------------------
-- Kiểm tra giá trị cuối cùng. Kết quả kỳ vọng là 70 (50 + 10 + 10), nhưng thực tế chỉ là 60.
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;


-- ============================================================================
-- 🔬 Kịch bản B — Giải pháp Khắc phục (SELECT ... FOR UPDATE)
-- Mô tả: Sử dụng Khóa bi quan ở mức dòng (Pessimistic Locking) để bắt các transaction xếp hàng.
-- ============================================================================

-- ------------------
-- [TERMINAL A - Bước 1]
-- ------------------
-- Bắt đầu transaction và khóa dòng dữ liệu lại
BEGIN;
SELECT total_issued FROM linh_lab.voucher 
WHERE voucher_id = 1 
FOR UPDATE;

-- ------------------
-- [TERMINAL B - Bước 2]
-- ------------------
-- Bắt đầu transaction và cố gắng khóa cùng dòng dữ liệu đó.
-- QUAN SÁT: Terminal B sẽ bị TREO (block) để đợi Terminal A nhả khóa.
BEGIN;
SELECT total_issued FROM linh_lab.voucher 
WHERE voucher_id = 1 
FOR UPDATE;

-- ------------------
-- [TERMINAL A - Bước 3]
-- ------------------
-- Thực hiện cập nhật cộng dồn (ví dụ: 60 + 10 = 70) và commit.
-- QUAN SÁT: Ngay khi COMMIT được chạy, Terminal B lập tức được giải phóng!
UPDATE linh_lab.voucher SET total_issued = total_issued + 10 WHERE voucher_id = 1;
COMMIT;

-- ------------------
-- [TERMINAL B - Bước 4]
-- ------------------
-- Terminal B được giải phóng. Nó tự động đọc được giá trị mới nhất vừa commit là 70.
-- Thực hiện cập nhật cộng dồn một cách an toàn (70 + 10 = 80) và commit.
UPDATE linh_lab.voucher SET total_issued = total_issued + 10 WHERE voucher_id = 1;
COMMIT;

-- ------------------
-- [XÁC MINH]
-- ------------------
-- Kiểm tra giá trị cuối cùng. Kỳ vọng: 80. Không có bản cập nhật nào bị mất!
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;


-- ============================================================================
-- 🔬 Kịch bản C — Khóa chết (Deadlock - Voucher Exchange)
-- Mô tả: Minh họa việc khóa tài nguyên theo thứ tự ngược nhau dẫn đến deadlock.
-- ============================================================================

-- ------------------
-- [TERMINAL A - Bước 1]
-- ------------------
BEGIN;
-- Khóa Voucher 1 trước
SELECT * FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;

-- ------------------
-- [TERMINAL B - Bước 2]
-- ------------------
BEGIN;
-- Khóa Voucher 2 trước
SELECT * FROM linh_lab.voucher WHERE voucher_id = 2 FOR UPDATE;

-- ------------------
-- [TERMINAL A - Bước 3]
-- ------------------
-- Terminal A cố gắng khóa tiếp Voucher 2.
-- QUAN SÁT: Terminal A bị treo do Voucher 2 đang bị Terminal B khóa.
SELECT * FROM linh_lab.voucher WHERE voucher_id = 2 FOR UPDATE;

-- ------------------
-- [TERMINAL B - Bước 4]
-- ------------------
-- Terminal B cố gắng khóa tiếp Voucher 1.
-- KẾT QUẢ: PostgreSQL lập tức phát hiện vòng lặp chờ đợi (circular dependency) và ngắt transaction này.
-- Đầu ra: ERROR: deadlock detected
SELECT * FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;

-- Dọn dẹp
ROLLBACK; -- Chạy trên terminal bị báo lỗi để kết thúc transaction thất bại


-- ============================================================================
-- 🔬 Kịch bản D — Phá vỡ hàng đợi (NOWAIT)
-- Mô tả: Sử dụng NOWAIT để báo lỗi ngay lập tức thay vì đứng chờ và bị treo session.
-- ============================================================================

-- ------------------
-- [TERMINAL A - Bước 1]
-- ------------------
BEGIN;
-- Khóa Voucher 1
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;

-- ------------------
-- [TERMINAL B - Bước 2]
-- ------------------
BEGIN;
-- Đòi lấy khóa ngay lập tức hoặc hủy luôn
-- QUAN SÁT: Terminal B báo lỗi ngay lập tức mà không bị treo.
-- Đầu ra: ERROR: could not obtain lock on row in relation "voucher"
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE NOWAIT;

-- Dọn dẹp
ROLLBACK; -- Chạy trên Terminal B để đóng transaction lỗi
COMMIT;   -- Chạy trên Terminal A để giải phóng khóa cho Voucher 1


-- ============================================================================
-- 🔬 Kịch bản E — Flash Sale 500-Request (Kiểm thử hiệu năng bằng pgbench)
-- Mô tả: Giả lập 500 requests đồng thời sử dụng pgbench để kiểm tra tính toàn vẹn của FOR UPDATE.
-- ============================================================================

-- [Bước 1]: Tạo file sql/marketing/flash_sale_test.sql với logic khóa bảo mật:
-- BEGIN;
-- SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;
-- UPDATE linh_lab.voucher SET total_issued = total_issued + 1 WHERE voucher_id = 1;
-- COMMIT;

-- [Bước 2]: Reset số lượng phát hành của voucher về 0 trước khi test
UPDATE linh_lab.voucher SET total_issued = 0 WHERE voucher_id = 1;

-- [Bước 3]: Chạy pgbench để mô phỏng 100 users đồng thời, mỗi user click 5 lần (tổng 500 requests):
-- Lệnh shell (chạy trên Terminal máy tính):
-- pgbench -U postgres -d postgres -c 100 -t 5 -f tasks/ddid13_concurrency/flash_sale_test.sql

-- [Bước 4]: Xác minh kết quả trên Database
-- Kết quả total_issued phải đạt đúng 500. Không có cập nhật nào bị ghi đè hay mất!
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;


-- ============================================================================
-- 🔬 Kịch bản F — Tấm khiên tối thượng (Mức cô lập SERIALIZABLE)
-- Mô tả: Sử dụng Transaction Isolation Level SERIALIZABLE thay vì khóa FOR UPDATE.
-- ============================================================================

-- ------------------
-- [TERMINAL A - Bước 1]
-- ------------------
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Dùng SELECT bình thường, hoàn toàn không sử dụng khóa FOR UPDATE
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;

-- ------------------
-- [TERMINAL B - Bước 2]
-- ------------------
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- SELECT bình thường
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1;

-- ------------------
-- [TERMINAL A - Bước 3]
-- ------------------
-- Giả sử đọc được 500, ứng dụng tính toán 500 + 10 = 510 và chạy cập nhật
UPDATE linh_lab.voucher SET total_issued = 510 WHERE voucher_id = 1;
COMMIT;
-- Kết quả: Thành công lưu giá trị 510!

-- ------------------
-- [TERMINAL B - Bước 4]
-- ------------------
-- Ứng dụng B vẫn nghĩ giá trị là 500, nên tính toán 500 + 10 = 510 và chạy cập nhật
UPDATE linh_lab.voucher SET total_issued = 510 WHERE voucher_id = 1;
-- KẾT QUẢ: PostgreSQL lập tức chặn và báo lỗi serialize access
-- Đầu ra: ERROR: could not serialize access due to concurrent update
ROLLBACK; -- Đóng giao dịch lỗi


-- ============================================================================
-- 💬 Trả lời Câu hỏi Phản tư (Reflection Answers)
-- ============================================================================
/*
Câu hỏi 1:
"In Scenario B, what happens if Terminal A runs `SELECT FOR UPDATE` but then the developer's laptop crashes before running `COMMIT;`? Will Terminal B hang forever? How does PostgreSQL handle this?"

Trả lời 1:
Không, Terminal B sẽ không bị treo vĩnh viễn.
Cơ chế xử lý của PostgreSQL:
1. Phát hiện mất kết nối: Khi máy tính của lập trình viên bị sập nguồn hoặc mất mạng, hệ điều hành hoặc PostgreSQL server sẽ phát hiện ra kết nối TCP đã chết (nhờ cơ chế TCP Keepalives).
2. Dọn dẹp backend: PostgreSQL giải phóng và tắt tiến trình (backend process) đang phục vụ cho kết nối bị ngắt đó.
3. Tự động Rollback: Mọi transaction đang dang dở của session đó sẽ bị rollback tự động.
4. Giải phóng Lock: Khi rollback, toàn bộ các khóa hàng dữ liệu (chứa bởi lệnh SELECT FOR UPDATE) được nhả ra. Kết quả là Terminal B (hoặc các session đang chờ khác) sẽ lập tức được giải phóng và tiếp tục chạy.
5. Cấu hình Timeout: Để an toàn hơn, ta có thể cài đặt `idle_in_transaction_session_timeout` để tự động ngắt transaction bị bỏ trống quá lâu, tránh chiếm giữ khóa dài hạn.

Câu hỏi 2:
"In Scenario C (Deadlock), how should developers structure their SQL queries in the application code to guarantee a deadlock NEVER happens, even when updating multiple rows?"

Trả lời 2:
Để đảm bảo về mặt toán học rằng deadlock không bao giờ xảy ra, lập trình viên phải thực thi quy tắc **sắp xếp thứ tự khóa tài nguyên nhất quán** trên toàn bộ hệ thống:
1. Sắp xếp thứ tự dòng khóa: Khi cập nhật hoặc khóa nhiều dòng dữ liệu trong cùng một bảng, luôn phải sắp xếp các dòng đó theo một trật tự cố định (ví dụ: sắp xếp tăng dần theo Primary Key `voucher_id`).
   Ví dụ, thay vị lock lộn xộn, hãy luôn chạy:
   SELECT * FROM linh_lab.voucher WHERE voucher_id IN (1, 2) ORDER BY voucher_id ASC FOR UPDATE;
2. Thứ tự thao tác giữa các bảng: Khi cập nhật trên nhiều bảng khác nhau trong cùng một transaction, toàn bộ các luồng logic trong code ứng dụng phải truy vấn/khóa các bảng theo cùng một trình tự (ví dụ: bảng `promotion_program` trước rồi mới đến `voucher`).
3. Rút ngắn thời gian lock: Giữ transaction ngắn nhất có thể, chỉ lock khi thực sự cần và giải phóng sớm nhất.
4. Cơ chế Retry: Ứng dụng luôn cần có cơ chế tự động thử lại (retry) với exponential backoff khi bắt được lỗi deadlock hoặc serialization từ database.

Câu hỏi 3:
"In an extreme Flash Sale (1 million users buying 1000 items in 1 second), even `NOWAIT` might overwhelm the database with error logs. What external caching technology do Data Engineers typically use in front of the database to handle Flash Sales?"

Trả lời 3:
Để xử lý tải cực lớn trong các sự kiện Flash Sale mà không gây nghẽn log hay sập database, các kỹ sư hệ thống sử dụng mô hình kết hợp bộ nhớ đệm và hàng đợi:
1. In-Memory Key-Value Stores (ví dụ: Redis, KeyDB, Dragonfly):
   - Đặt Redis phía trước làm lá chắn chịu tải chính cho việc trừ kho/cấp phát voucher.
   - Sử dụng các câu lệnh nguyên tử (Atomic Operations) như `DECRBY` hoặc chạy Lua Script trực tiếp trên Redis để kiểm tra số lượng tồn và trừ kho một cách an toàn mà không cần lock database.
2. Hàng đợi thông điệp (Message Queues - ví dụ: Apache Kafka, RabbitMQ, AWS SQS):
   - Sau khi yêu cầu mua hàng được xác nhận thành công tại Redis, thông tin đơn hàng được đẩy vào queue.
   - Các dịch vụ worker ở phía sau sẽ tiêu thụ queue này và lưu dữ liệu vào PostgreSQL một cách bất đồng bộ (Write-Behind) với tốc độ vừa phải mà database chịu được.
3. Rate Limiter (Bộ giới hạn tần suất):
   - Sử dụng các thuật toán giới hạn (Token Bucket/Leaky Bucket) ở tầng API Gateway để loại bỏ các request vượt ngưỡng chịu tải ngay lập tức, ngăn chúng tiếp cận database.
*/
