-- ==================================================
-- DDL - AFFILIATE VOUCHER DATABASE
-- PostgreSQL - Physical Model + Constraints
-- SCHEMA: linh_lab
-- ==================================================

DROP SCHEMA IF EXISTS linh_lab CASCADE;
CREATE SCHEMA IF NOT EXISTS linh_lab;

-- 1. STATUS_MASTER
CREATE TABLE linh_lab.status_master (
    status_id BIGSERIAL PRIMARY KEY,
    status_code VARCHAR(50) NOT NULL,
    status_name VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    is_final BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100),
    
    CONSTRAINT uq_status UNIQUE (entity_type, status_code)
);

-- 2. STATUS_TRANSITION (Missing in original DDL, added for state machine synchronization)
CREATE TABLE linh_lab.status_transition (
    transition_id BIGSERIAL PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    from_status_id BIGINT NOT NULL,
    to_status_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    
    CONSTRAINT fk_transition_from FOREIGN KEY (from_status_id) REFERENCES linh_lab.status_master(status_id),
    CONSTRAINT fk_transition_to FOREIGN KEY (to_status_id) REFERENCES linh_lab.status_master(status_id)
);

-- 3. COMMISSION_RULE
CREATE TABLE linh_lab.commission_rule (
    commission_rule_id BIGSERIAL PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL,
    payout_rate DECIMAL(10,2) NOT NULL,
    conditions TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100),
    
    CONSTRAINT chk_payout_rate CHECK (payout_rate > 0)
);

-- 4. PARTNER
CREATE TABLE linh_lab.partner (
    partner_id BIGSERIAL PRIMARY KEY,
    partner_code VARCHAR(50) NOT NULL UNIQUE,
    partner_name VARCHAR(200) NOT NULL,
    commission_rule_id BIGINT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100)
);

ALTER TABLE linh_lab.partner 
ADD CONSTRAINT fk_partner_commission_rule 
FOREIGN KEY (commission_rule_id) REFERENCES linh_lab.commission_rule(commission_rule_id);

-- 5. PROMOTION_PROGRAM
CREATE TABLE linh_lab.promotion_program (
    program_id BIGSERIAL PRIMARY KEY,
    program_name VARCHAR(200) NOT NULL,
    budget_limit NUMERIC(18,2) NOT NULL,
    start_at TIMESTAMP NOT NULL,
    end_at TIMESTAMP NOT NULL,
    status_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100),
    
    CONSTRAINT chk_budget_limit CHECK (budget_limit >= 0),
    CONSTRAINT chk_program_date CHECK (end_at > start_at)
);

ALTER TABLE linh_lab.promotion_program 
ADD CONSTRAINT fk_program_status 
FOREIGN KEY (status_id) REFERENCES linh_lab.status_master(status_id);

-- 6. VOUCHER
CREATE TABLE linh_lab.voucher (
    voucher_id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL,
    status_id BIGINT NOT NULL,
    voucher_code VARCHAR(100) NOT NULL UNIQUE,
    discount_type VARCHAR(20) NOT NULL,
    discount_amount NUMERIC(18,2) NOT NULL,
    issuance_limit INT NOT NULL,
    total_issued INT NOT NULL DEFAULT 0,
    valid_from TIMESTAMP NOT NULL,
    expired_at TIMESTAMP NOT NULL, -- Keep expired_at to match DDL design
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100),
    
    CONSTRAINT chk_issuance_limit CHECK (issuance_limit > 0),
    CONSTRAINT chk_total_issued CHECK (total_issued <= issuance_limit),
    CONSTRAINT chk_voucher_date CHECK (expired_at > valid_from)
);

ALTER TABLE linh_lab.voucher 
ADD CONSTRAINT fk_voucher_program 
FOREIGN KEY (program_id) REFERENCES linh_lab.promotion_program(program_id);

ALTER TABLE linh_lab.voucher 
ADD CONSTRAINT fk_voucher_status 
FOREIGN KEY (status_id) REFERENCES linh_lab.status_master(status_id);

-- 7. CUSTOMER
CREATE TABLE linh_lab.customer (
    customer_id BIGSERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(30) NOT NULL UNIQUE,
    email VARCHAR(255) UNIQUE,
    date_of_birth DATE,
    gender VARCHAR(10),
    address TEXT,
    province VARCHAR(100),
    district VARCHAR(100),
    ward VARCHAR(100),
    status_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100)
);

ALTER TABLE linh_lab.customer 
ADD CONSTRAINT fk_customer_status 
FOREIGN KEY (status_id) REFERENCES linh_lab.status_master(status_id);

-- 8. PARTNER_CLICK
CREATE TABLE linh_lab.partner_click (
    click_id VARCHAR(100) PRIMARY KEY, -- Changed from BIGSERIAL to VARCHAR(100) to match string CLICK001 in seed
    partner_id BIGINT NOT NULL,
    partner_code VARCHAR(50) NOT NULL,
    ip_address VARCHAR(100),
    clicked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_suspicious BOOLEAN NOT NULL DEFAULT FALSE,
    is_orphaned BOOLEAN NOT NULL DEFAULT FALSE,
    reconciliation_status_id BIGINT,
    reconciled_at TIMESTAMP,
    reconciled_by VARCHAR(100),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100)
);

ALTER TABLE linh_lab.partner_click 
ADD CONSTRAINT fk_click_partner 
FOREIGN KEY (partner_id) REFERENCES linh_lab.partner(partner_id);

-- 9. CUSTOMER_VOUCHER
CREATE TABLE linh_lab.customer_voucher (
    customer_voucher_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    voucher_id BIGINT NOT NULL,
    click_id VARCHAR(100), -- Changed from BIGINT to VARCHAR(100) to reference VARCHAR click_id
    partner_id BIGINT,
    order_id BIGINT,
    order_external_code VARCHAR(100),
    status_id BIGINT NOT NULL,
    saved_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    applied_at TIMESTAMP,
    refunded_at TIMESTAMP,
    cancelled_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100)
);

ALTER TABLE linh_lab.customer_voucher 
ADD CONSTRAINT fk_cv_customer FOREIGN KEY (customer_id) REFERENCES linh_lab.customer(customer_id);

ALTER TABLE linh_lab.customer_voucher 
ADD CONSTRAINT fk_cv_voucher FOREIGN KEY (voucher_id) REFERENCES linh_lab.voucher(voucher_id);

ALTER TABLE linh_lab.customer_voucher 
ADD CONSTRAINT fk_cv_click FOREIGN KEY (click_id) REFERENCES linh_lab.partner_click(click_id);

ALTER TABLE linh_lab.customer_voucher 
ADD CONSTRAINT fk_cv_partner FOREIGN KEY (partner_id) REFERENCES linh_lab.partner(partner_id);

ALTER TABLE linh_lab.customer_voucher 
ADD CONSTRAINT fk_cv_status FOREIGN KEY (status_id) REFERENCES linh_lab.status_master(status_id);

-- 10. AFFILIATE_COMMISSION
CREATE TABLE linh_lab.affiliate_commission (
    commission_id BIGSERIAL PRIMARY KEY, -- Changed from affiliate_commission_id to commission_id
    customer_voucher_id BIGINT NOT NULL,
    commission_rule_id BIGINT NOT NULL,
    status_id BIGINT NOT NULL,
    payout_rate NUMERIC(10,2) NOT NULL,
    commission_amount NUMERIC(18,2) NOT NULL, -- Changed from amount to commission_amount
    approved_at TIMESTAMP,
    paid_at TIMESTAMP, -- Added missing paid_at column
    rejection_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100)
);

ALTER TABLE linh_lab.affiliate_commission 
ADD CONSTRAINT fk_commission_cv FOREIGN KEY (customer_voucher_id) REFERENCES linh_lab.customer_voucher(customer_voucher_id);

ALTER TABLE linh_lab.affiliate_commission 
ADD CONSTRAINT fk_commission_rule FOREIGN KEY (commission_rule_id) REFERENCES linh_lab.commission_rule(commission_rule_id);

ALTER TABLE linh_lab.affiliate_commission 
ADD CONSTRAINT fk_commission_status FOREIGN KEY (status_id) REFERENCES linh_lab.status_master(status_id);

-- 11. COMMISSION_ADJUSTMENT (Missing in original DDL, added for seed synchronization)
CREATE TABLE linh_lab.commission_adjustment (
    adjustment_id BIGSERIAL PRIMARY KEY,
    commission_id BIGINT NOT NULL,
    amount NUMERIC(18,2) NOT NULL,
    reason TEXT,
    status_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    
    CONSTRAINT fk_adjustment_commission FOREIGN KEY (commission_id) REFERENCES linh_lab.affiliate_commission(commission_id),
    CONSTRAINT fk_adjustment_status FOREIGN KEY (status_id) REFERENCES linh_lab.status_master(status_id)
);

-- 12. BUDGET_TRANSACTION
CREATE TABLE linh_lab.budget_transaction (
    transaction_id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL,
    entry_type VARCHAR(20) NOT NULL, -- 'income', 'spend', 'adjustment'
    amount NUMERIC(18,2) NOT NULL,
    description TEXT,
    reference_id VARCHAR(100),
    reference_type VARCHAR(50),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    updated_at TIMESTAMP,
    updated_by VARCHAR(100),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by VARCHAR(100),
    
    CONSTRAINT chk_entry_type CHECK (entry_type IN ('income', 'spend', 'adjustment')),
    CONSTRAINT chk_amount CHECK (amount != 0)
);

ALTER TABLE linh_lab.budget_transaction 
ADD CONSTRAINT fk_bt_program 
FOREIGN KEY (program_id) REFERENCES linh_lab.promotion_program(program_id);

-- ==================================================
-- INDEXES (Performance)
-- ==================================================
CREATE INDEX idx_promotion_status ON linh_lab.promotion_program(status_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_voucher_program ON linh_lab.voucher(program_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_customer_voucher_status ON linh_lab.customer_voucher(status_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_budget_transaction_program ON linh_lab.budget_transaction(program_id) WHERE is_deleted = FALSE;
