SET search_path = linh_lab, public;

BEGIN;

-- =====================================================
-- STATUS_MASTER
-- =====================================================

INSERT INTO linh_lab.status_master
(
    status_id,
    status_code,
    status_name,
    entity_type,
    is_final,
    created_at,
    created_by
)
VALUES

-- CUSTOMER
(1,'ACTIVE','Đang hoạt động','CUSTOMER',FALSE,NOW(),'SYSTEM'),
(2,'INACTIVE','Ngưng hoạt động','CUSTOMER',TRUE,NOW(),'SYSTEM'),

-- VOUCHER
(3,'ACTIVE','Khả dụng','VOUCHER',FALSE,NOW(),'SYSTEM'),
(4,'USED','Đã sử dụng','VOUCHER',FALSE,NOW(),'SYSTEM'),
(5,'EXPIRED','Hết hạn','VOUCHER',TRUE,NOW(),'SYSTEM'),

-- CUSTOMER_VOUCHER
(6,'SAVED','Đã lưu','CUSTOMER_VOUCHER',FALSE,NOW(),'SYSTEM'),
(7,'APPLIED','Đã áp dụng','CUSTOMER_VOUCHER',FALSE,NOW(),'SYSTEM'),
(8,'REFUNDED','Đã hoàn tiền','CUSTOMER_VOUCHER',TRUE,NOW(),'SYSTEM'),
(9,'CANCELLED','Đã hủy','CUSTOMER_VOUCHER',TRUE,NOW(),'SYSTEM'),

-- AFFILIATE_COMMISSION
(10,'PENDING','Chờ duyệt','AFFILIATE_COMMISSION',FALSE,NOW(),'SYSTEM'),
(11,'APPROVED','Đã duyệt','AFFILIATE_COMMISSION',FALSE,NOW(),'SYSTEM'),
(12,'PAID','Đã thanh toán','AFFILIATE_COMMISSION',TRUE,NOW(),'SYSTEM'),
(13,'REJECTED','Từ chối','AFFILIATE_COMMISSION',TRUE,NOW(),'SYSTEM'),

-- PROMOTION_PROGRAM
(14,'DRAFT','Bản nháp','PROMOTION_PROGRAM',FALSE,NOW(),'SYSTEM'),
(15,'ACTIVE','Đang hoạt động','PROMOTION_PROGRAM',FALSE,NOW(),'SYSTEM'),
(16,'PAUSED','Tạm dừng','PROMOTION_PROGRAM',FALSE,NOW(),'SYSTEM'),
(17,'ENDED','Đã kết thúc','PROMOTION_PROGRAM',TRUE,NOW(),'SYSTEM'),

-- COMMISSION_ADJUSTMENT
(18,'PENDING','Chờ xử lý','COMMISSION_ADJUSTMENT',FALSE,NOW(),'SYSTEM'),
(19,'APPROVED','Đã duyệt','COMMISSION_ADJUSTMENT',TRUE,NOW(),'SYSTEM'),
(20,'REJECTED','Từ chối','COMMISSION_ADJUSTMENT',TRUE,NOW(),'SYSTEM');

-- =====================================================
-- COMMISSION_RULE
-- =====================================================

INSERT INTO linh_lab.commission_rule
(
    commission_rule_id,
    rule_name,
    payout_rate,
    conditions,
    created_at,
    created_by
)
VALUES
(1,'TikTok KOL',5,'TikTok Creator',NOW(),'ADMIN'),
(2,'Facebook KOL',7,'Facebook Creator',NOW(),'ADMIN'),
(3,'Affiliate Network',10,'Affiliate Platform',NOW(),'ADMIN'),
(4,'Google Ads',3,'Ads Campaign',NOW(),'ADMIN'),
(5,'Shopee KOL',8,'Shopee Influencer',NOW(),'ADMIN');

-- =====================================================
-- PARTNER
-- =====================================================

INSERT INTO linh_lab.partner
(
    partner_id,
    partner_code,
    partner_name,
    commission_rule_id,
    created_at,
    created_by
)
VALUES
(1,'KOL001','Nguyễn Minh Duy',1,NOW(),'ADMIN'),
(2,'KOL002','Trần Hoàng Linh',2,NOW(),'ADMIN'),
(3,'AFF001','Accesstrade Việt Nam',3,NOW(),'ADMIN'),
(4,'ADS001','Google Ads Campaign',4,NOW(),'ADMIN'),
(5,'KOL003','Lê Quốc Minh',5,NOW(),'ADMIN');

-- =====================================================
-- PROMOTION_PROGRAM
-- =====================================================

INSERT INTO linh_lab.promotion_program
(
    program_id,
    program_name,
    budget_limit,
    start_at,
    end_at,
    status_id,
    created_at,
    created_by
)
VALUES
(1,'Tết 2026',50000000,'2026-01-01','2026-02-28',15,NOW(),'MARKETING'),
(2,'Summer Sale 2026',70000000,'2026-06-01','2026-08-31',15,NOW(),'MARKETING'),
(3,'Black Friday 2026',100000000,'2026-11-01','2026-11-30',15,NOW(),'MARKETING');

-- =====================================================
-- CUSTOMER
-- =====================================================

INSERT INTO linh_lab.customer
(
    customer_id,
    first_name,
    middle_name,
    last_name,
    phone_number,
    email,
    status_id,
    created_at,
    created_by
)
VALUES
(1,'Nguyễn','','Linh','0901234567','linh.nguyen@gmail.com',1,NOW(),'SYSTEM'),
(2,'Trần','','Duy','0901234568','duy.tran@gmail.com',1,NOW(),'SYSTEM'),
(3,'Lê','','Minh','0901234569','minh.le@gmail.com',1,NOW(),'SYSTEM'),
(4,'Phạm','','Anh','0901234570','anh.pham@gmail.com',1,NOW(),'SYSTEM'),
(5,'Võ','','Huy','0901234571','huy.vo@gmail.com',1,NOW(),'SYSTEM');

-- =====================================================
-- VOUCHER
-- =====================================================

INSERT INTO linh_lab.voucher
(
    voucher_id,
    program_id,
    status_id,
    voucher_code,
    discount_type,
    discount_amount,
    issuance_limit,
    total_issued,
    valid_from,
    expired_at,
    created_at,
    created_by
)
VALUES
(1,1,3,'TET50K','AMOUNT',50000,1000,125,'2026-01-01','2026-02-28',NOW(),'ADMIN'),
(2,1,3,'TET10P','PERCENT',10,5000,350,'2026-01-01','2026-02-28',NOW(),'ADMIN'),
(3,2,3,'SUMMER15P','PERCENT',15,3000,500,'2026-06-01','2026-08-31',NOW(),'ADMIN'),
(4,3,3,'BLACK100K','AMOUNT',100000,500,50,'2026-11-01','2026-11-30',NOW(),'ADMIN');

-- =====================================================
-- PARTNER_CLICK
-- =====================================================

INSERT INTO linh_lab.partner_click
(
    click_id,
    partner_code,
    partner_id,
    ip_address,
    clicked_at,
    created_at,
    created_by
)
VALUES
('CLICK001','KOL001',1,'14.161.10.1',NOW(),NOW(),'SYSTEM'),
('CLICK002','KOL002',2,'14.161.10.2',NOW(),NOW(),'SYSTEM'),
('CLICK003','AFF001',3,'14.161.10.3',NOW(),NOW(),'SYSTEM'),
('CLICK004','ADS001',4,'14.161.10.4',NOW(),NOW(),'SYSTEM'),
('CLICK005','KOL003',5,'14.161.10.5',NOW(),NOW(),'SYSTEM');

-- =====================================================
-- CUSTOMER_VOUCHER
-- =====================================================

INSERT INTO linh_lab.customer_voucher
(
    customer_voucher_id,
    customer_id,
    voucher_id,
    click_id,
    partner_id,
    order_external_code,
    status_id,
    saved_at,
    applied_at,
    created_at,
    created_by
)
VALUES
(1,1,1,'CLICK001',1,'ORD00001',7,NOW(),NOW(),NOW(),'SYSTEM'),
(2,2,2,'CLICK002',2,'ORD00002',7,NOW(),NOW(),NOW(),'SYSTEM'),
(3,3,3,'CLICK003',3,'ORD00003',7,NOW(),NOW(),NOW(),'SYSTEM'),
(4,4,1,'CLICK004',4,'ORD00004',7,NOW(),NOW(),NOW(),'SYSTEM'),
(5,5,4,'CLICK005',5,'ORD00005',7,NOW(),NOW(),NOW(),'SYSTEM');

-- =====================================================
-- AFFILIATE_COMMISSION
-- =====================================================

INSERT INTO linh_lab.affiliate_commission
(
    commission_id,
    customer_voucher_id,
    commission_rule_id,
    status_id,
    commission_amount,
    payout_rate,
    paid_at,
    created_at,
    created_by
)
VALUES
(1,1,1,12,5000,5,NOW(),NOW(),'SYSTEM'),
(2,2,2,12,7000,7,NOW(),NOW(),'SYSTEM'),
(3,3,3,10,10000,10,NULL,NOW(),'SYSTEM'),
(4,4,4,11,3000,3,NULL,NOW(),'SYSTEM'),
(5,5,5,13,8000,8,NULL,NOW(),'SYSTEM');

-- =====================================================
-- COMMISSION_ADJUSTMENT
-- =====================================================

INSERT INTO linh_lab.commission_adjustment
(
    adjustment_id,
    commission_id,
    amount,
    reason,
    status_id,
    created_at,
    created_by
)
VALUES
(1,3,-10000,'Khách hàng hoàn tiền',19,NOW(),'SYSTEM');

-- =====================================================
-- RESET SEQUENCES (Đồng bộ lại các Sequence)
-- =====================================================
SELECT setval(pg_get_serial_sequence('linh_lab.status_master', 'status_id'), COALESCE(MAX(status_id), 1)) FROM linh_lab.status_master;
SELECT setval(pg_get_serial_sequence('linh_lab.status_transition', 'transition_id'), COALESCE(MAX(transition_id), 1)) FROM linh_lab.status_transition;
SELECT setval(pg_get_serial_sequence('linh_lab.commission_rule', 'commission_rule_id'), COALESCE(MAX(commission_rule_id), 1)) FROM linh_lab.commission_rule;
SELECT setval(pg_get_serial_sequence('linh_lab.partner', 'partner_id'), COALESCE(MAX(partner_id), 1)) FROM linh_lab.partner;
SELECT setval(pg_get_serial_sequence('linh_lab.promotion_program', 'program_id'), COALESCE(MAX(program_id), 1)) FROM linh_lab.promotion_program;
SELECT setval(pg_get_serial_sequence('linh_lab.voucher', 'voucher_id'), COALESCE(MAX(voucher_id), 1)) FROM linh_lab.voucher;
SELECT setval(pg_get_serial_sequence('linh_lab.customer', 'customer_id'), COALESCE(MAX(customer_id), 1)) FROM linh_lab.customer;
SELECT setval(pg_get_serial_sequence('linh_lab.customer_voucher', 'customer_voucher_id'), COALESCE(MAX(customer_voucher_id), 1)) FROM linh_lab.customer_voucher;
SELECT setval(pg_get_serial_sequence('linh_lab.affiliate_commission', 'commission_id'), COALESCE(MAX(commission_id), 1)) FROM linh_lab.affiliate_commission;
SELECT setval(pg_get_serial_sequence('linh_lab.commission_adjustment', 'adjustment_id'), COALESCE(MAX(adjustment_id), 1)) FROM linh_lab.commission_adjustment;
SELECT setval(pg_get_serial_sequence('linh_lab.budget_transaction', 'transaction_id'), COALESCE(MAX(transaction_id), 1)) FROM linh_lab.budget_transaction;

COMMIT;
