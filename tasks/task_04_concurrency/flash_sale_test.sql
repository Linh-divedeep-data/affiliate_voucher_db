BEGIN;
SELECT total_issued FROM linh_lab.voucher WHERE voucher_id = 1 FOR UPDATE;
UPDATE linh_lab.voucher SET total_issued = total_issued + 1 WHERE voucher_id = 1;
COMMIT;
