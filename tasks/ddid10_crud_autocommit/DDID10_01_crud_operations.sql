-- ============================================================================
-- SQL FILE: DDID10_01_crud_operations.sql
-- TASK: Practice Targeted CRUD & Observe the Auto-Commit Trap
-- ============================================================================

SET search_path = linh_lab, public;

-- ----------------------------------------------------------------------------
-- 🛠️ Setup Helper
-- ----------------------------------------------------------------------------
-- The seed data only includes customer vouchers in 'APPLIED' status.
-- We insert a test customer voucher with status 'SAVED' (status_id = 6)
-- to make sure Step 0-B and Action 2 can execute correctly.
INSERT INTO customer_voucher (customer_voucher_id, customer_id, voucher_id, status_id)
VALUES (6, 1, 1, 6)
ON CONFLICT (customer_voucher_id) DO UPDATE SET status_id = 6;

-- ============================================================================
-- ✅ STEP 0 — Prerequisites (Run First, Record the Results)
-- ============================================================================

-- Check 1 — What statuses exist in status_master?
SELECT status_id, entity_type, status_code, status_name, is_final
FROM status_master
WHERE is_deleted = FALSE
ORDER BY entity_type, status_id;

-- Check 2 — How many promotion_programs exist per status?
SELECT sm.status_code, COUNT(*) AS program_count
FROM promotion_program pp
JOIN status_master sm ON sm.status_id = pp.status_id
WHERE pp.is_deleted = FALSE
GROUP BY sm.status_code
ORDER BY sm.status_code;

-- Check 3 — What customer_voucher statuses exist in your data?
SELECT sm.status_code, COUNT(*) AS cv_count
FROM customer_voucher cv
JOIN status_master sm ON sm.status_id = cv.status_id
WHERE cv.is_deleted = FALSE
GROUP BY sm.status_code
ORDER BY sm.status_code;

-- Step 0-A · Find a promotion_program to work with
SELECT pp.program_id, pp.program_name, sm.status_code, pp.budget_limit
FROM promotion_program pp
JOIN status_master sm ON sm.status_id = pp.status_id
WHERE sm.status_code = 'ACTIVE'
  AND pp.is_deleted = FALSE
ORDER BY pp.program_id
LIMIT 3;

-- Step 0-B · Find a customer_voucher with status = ‘saved’
SELECT cv.customer_voucher_id AS cv_id, sm.status_code, v.program_id
FROM customer_voucher cv
JOIN voucher v          ON v.voucher_id  = cv.voucher_id
JOIN status_master sm   ON sm.status_id  = cv.status_id
WHERE v.program_id      = 1                  -- ← using program_id = 1
  AND sm.status_code    = 'SAVED'
  AND cv.is_deleted     = FALSE
ORDER BY cv.customer_voucher_id
LIMIT 5;

-- Step 0-C · Calculate remaining budget for your program
SELECT
    pp.program_id,
    pp.budget_limit,
    COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0)   AS total_spent,
    pp.budget_limit
      - COALESCE(SUM(bt.amount) FILTER (WHERE bt.entry_type = 'spend'), 0) AS remaining_budget
FROM promotion_program pp
LEFT JOIN budget_transaction bt ON bt.program_id = pp.program_id
WHERE pp.program_id = 1                      -- ← using program_id = 1
GROUP BY pp.program_id, pp.budget_limit;

-- Step 0-D · Collect the status_id values you need
SELECT status_id, entity_type, status_code
FROM status_master
WHERE entity_type IN ('PROMOTION_PROGRAM', 'CUSTOMER_VOUCHER')
  AND status_code  IN ('ACTIVE', 'PAUSED', 'SAVED', 'CANCELLED')
  AND is_deleted   = FALSE
ORDER BY entity_type, status_code;

-- 📋 Value mappings identified:
-- :program_id              = 1
-- :active_status_id        = 15   (PROMOTION_PROGRAM / ACTIVE)
-- :paused_status_id        = 16   (PROMOTION_PROGRAM / PAUSED)
-- :cv_id                   = 6
-- :cv_saved_status_id      = 6    (CUSTOMER_VOUCHER / SAVED)
-- :cv_cancelled_status_id  = 9    (CUSTOMER_VOUCHER / CANCELLED)
-- :remaining_budget        = 50000000
-- :balance_after_valid     = 49500000

-- Setting psql client variables:
\set program_id 1
\set active_status_id 15
\set paused_status_id 16
\set cv_id 6
\set cv_saved_status_id 6
\set cv_cancelled_status_id 9

-- ============================================================================
-- 🔬 Action Items
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Action 1 — The RETURNING Clause
-- ----------------------------------------------------------------------------
-- Change promotion_program from 'ACTIVE' → 'PAUSED'
UPDATE promotion_program
   SET status_id = :paused_status_id,
       updated_by = CURRENT_USER
 WHERE program_id = :program_id
   AND status_id  = :active_status_id
RETURNING
    program_id,
    status_id,
    updated_at;


-- ----------------------------------------------------------------------------
-- Action 2 — Foreign Key Protection (RESTRICT)
-- ----------------------------------------------------------------------------

-- Step 2-A · Verify current status of your customer_voucher
SELECT cv.customer_voucher_id, sm.status_code
FROM customer_voucher cv
JOIN status_master sm ON sm.status_id = cv.status_id
WHERE cv.customer_voucher_id = :cv_id;

-- Step 2-B · Update customer_voucher status (with RETURNING)
UPDATE customer_voucher
   SET status_id  = :cv_cancelled_status_id,
       updated_by = CURRENT_USER
 WHERE customer_voucher_id = :cv_id
   AND status_id = :cv_saved_status_id
RETURNING
    customer_voucher_id AS cv_id,
    status_id;

-- Step 2-C · Attempt to delete the parent program — watch FK block it
-- This is expected to FAIL due to ON DELETE RESTRICT on the child tables.
DELETE FROM promotion_program
WHERE program_id = :program_id;


-- ----------------------------------------------------------------------------
-- Action 3 — The Auto-Commit Trap ⚠️
-- ----------------------------------------------------------------------------

-- Statement 1 — Valid INSERT (no BEGIN → commits on its own)
INSERT INTO budget_transaction (program_id, entry_type, amount, description, reference_id)
VALUES (
    :program_id,
    'spend',
    500000,
    'DDID10-Action3: valid spend',
    'DEMO-001'
);

-- Ensure the check constraint exists before running statement 2
ALTER TABLE budget_transaction DROP CONSTRAINT IF EXISTS chk_bt_amount_positive;
ALTER TABLE budget_transaction ADD CONSTRAINT chk_bt_amount_positive CHECK (amount >= 0);

-- Statement 2 — Invalid INSERT (violates amount constraint)
-- This is expected to FAIL.
INSERT INTO budget_transaction (program_id, entry_type, amount, description, reference_id)
VALUES (
    :program_id,
    'spend',
    -9999999,
    'DDID10-Action3: INVALID',
    'DEMO-002'
);

-- Verify — observe the orphaned record
SELECT transaction_id, entry_type, amount, description, created_at
FROM budget_transaction
WHERE program_id  = :program_id
  AND description LIKE 'DDID10-Action3%'
ORDER BY transaction_id DESC;


-- ----------------------------------------------------------------------------
-- Action 4 — The Fix: Explicit Transaction Block
-- ----------------------------------------------------------------------------

BEGIN;

    -- Statement 1 (same valid INSERT)
    INSERT INTO budget_transaction (program_id, entry_type, amount, description, reference_id)
    VALUES (
        :program_id,
        'spend',
        500000,
        'DDID10-Action4: inside transaction',
        'DEMO-003'
    );

    -- Statement 2 (same invalid INSERT)
    -- This violates chk_bt_amount_positive and aborts the transaction
    INSERT INTO budget_transaction (program_id, entry_type, amount, description, reference_id)
    VALUES (
        :program_id,
        'spend',
        -9999999,
        'DDID10-Action4: INVALID inside transaction',
        'DEMO-004'
    );

ROLLBACK;

-- Verify — check that neither row was committed
SELECT transaction_id, amount, description
FROM budget_transaction
WHERE program_id  = :program_id
  AND description LIKE 'DDID10-Action4%';


-- ----------------------------------------------------------------------------
-- 🧹 Cleanup
-- ----------------------------------------------------------------------------
-- Remove the orphaned record left by Action 3
DELETE FROM budget_transaction
WHERE program_id  = :program_id
  AND description LIKE 'DDID10-Action3%'
RETURNING transaction_id, description;


-- ============================================================================
-- 💬 REFLECTION QUESTIONS & ANSWERS
-- ============================================================================
/*
Question:
“In Action 3, Statement 1 committed a budget spend record while Statement 2 failed — but Statement 1 could not be undone automatically.
In a real production system, what business consequence does this create?
Who is responsible for cleaning up the orphaned record — the database or the application?”

Answer:
1. Business Consequences:
- Financial Mismatches: The finance team will see a recorded expense of 500,000đ in budget reports without any corresponding order or coupon redemption in customer reports, resulting in reconciliation discrepancies.
- False Campaign Exhaustion: The campaign's remaining budget will be reduced falsely. Under high traffic, multiple orphaned records could add up to reach the program's budget limit, causing the system to automatically pause active campaigns prematurely.
- Data Mismatch and Loss of Trust: Marketing reports (showing count of coupons used) will not align with financial ledger reports, leading to auditing issues.

2. Cleanup Responsibility:
- The Database is NOT responsible: The database performed exactly as designed. Under auto-commit, each SQL statement is treated as a separate, independent transaction that commits on success. The database cannot automatically infer business relationships between distinct statements.
- The Application / Developer is responsible:
  - Immediate fix: A developer must write a cleanup script to manually delete the orphaned row (similar to the Cleanup step in this lab).
  - Prevention: Developers must wrap multi-step business transactions in explicit transaction blocks (BEGIN...COMMIT/ROLLBACK) so that the engine handles them as a single atomic unit.
*/
