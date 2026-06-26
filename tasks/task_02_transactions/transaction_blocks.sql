-- ============================================================================
-- SQL FILE: DDID11_02_transaction_blocks.sql
-- TASK: Write Multi-Step Transactions with COMMIT, ROLLBACK, and SAVEPOINT
-- ============================================================================

SET search_path = linh_lab, public;

-- ============================================================================
-- ✅ STEP 0 — Prerequisites (Simple Data Discovery)
-- ============================================================================

-- Step 0-A: Get status IDs
-- To keep things simple, let's just grab the IDs we need by looking directly at the tables.
SELECT status_id, entity_type, status_code
FROM status_master
WHERE status_code IN ('ACTIVE', 'SAVED');

-- Step 0-B: Get a program and voucher
SELECT voucher_id, program_id
FROM voucher
LIMIT 5;

-- 📋 Your values discovered from Step 0:
-- :program_id              = 1
-- :voucher_id              = 1
-- :cust_active_status_id   = 1
-- :cv_saved_status_id      = 6

-- Setting psql variables for automated execution:
\set program_id 1
\set voucher_id 1
\set cust_active_status_id 1
\set cv_saved_status_id 6

-- ============================================================================
-- 🔬 Action Items
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Scenario A — Happy Path with RETURNING Chaining
-- ----------------------------------------------------------------------------

-- Step 1 — Start the transaction
BEGIN;

-- Step 2 — INSERT a new customer, capture the ID via RETURNING
-- Note: DDL defines created_by DEFAULT CURRENT_USER, so we don't need to specify it.
INSERT INTO customer (first_name, last_name, phone_number, email, province, status_id)
VALUES (
    'Test',
    'Customer A',
    '0911000001',               -- unique phone
    'test.scenarioA@demo.com',  -- unique email
    'TP. Hồ Chí Minh',
    :cust_active_status_id      -- ← from Step 0-C
)
RETURNING customer_id \gset new_
-- \gset is a psql command that captures the returning customer_id and stores it in :new_customer_id

-- Step 3 — Use :new_customer_id to INSERT into customer_voucher
INSERT INTO customer_voucher (customer_id, voucher_id, status_id, saved_at)
VALUES (
    :new_customer_id,           -- ← value from Step 2 RETURNING
    :voucher_id,                -- ← your value from Step 0-B
    :cv_saved_status_id,        -- ← from Step 0-C
    NOW()
)
RETURNING customer_voucher_id;

-- Step 4 — INSERT a budget spend record
INSERT INTO budget_transaction
    (program_id, entry_type, amount, description, reference_id)
VALUES (
    :program_id,                -- ← your value
    'spend',
    500000,
    'DDID11-ScenarioA: new customer voucher spend',
    'VOUCHER-001'
);

-- Step 5 — COMMIT
COMMIT;

-- Step 6 — Verify all 3 rows exist
-- Customer exists?
SELECT customer_id, first_name, last_name
FROM customer
WHERE phone_number = '0911000001';

-- Voucher assigned?
SELECT customer_voucher_id, customer_id, voucher_id
FROM customer_voucher
WHERE customer_id = :new_customer_id;

-- Budget recorded?
SELECT transaction_id, entry_type, amount, description
FROM budget_transaction
WHERE program_id = :program_id
  AND description LIKE 'DDID11-ScenarioA%';


-- ----------------------------------------------------------------------------
-- Scenario B — Mid-transaction Rollback
-- ----------------------------------------------------------------------------

-- Prerequisite for Scenario B: Ensure the database actually blocks negative amounts.
-- We drop constraint first to allow re-runnability of this script.
ALTER TABLE budget_transaction DROP CONSTRAINT IF EXISTS chk_bt_amount_positive;
ALTER TABLE budget_transaction ADD CONSTRAINT chk_bt_amount_positive CHECK (amount >= 0);

-- Count rows before starting (baseline):
SELECT
    (SELECT COUNT(*) FROM customer WHERE first_name = 'Test') AS customers_count,
    (SELECT COUNT(*) FROM budget_transaction WHERE description LIKE 'DDID11-ScenarioB%') AS bt_count;

-- Run the transaction (it will fail at Step 3):
BEGIN;

-- Step 1: INSERT customer (will succeed)
INSERT INTO customer (first_name, last_name, phone_number, email, status_id)
VALUES (
    'Test',
    'Customer B',
    '0911000002',
    'test.scenarioB@demo.com',
    :cust_active_status_id
)
RETURNING customer_id \gset new_
-- → Succeeds. Captured as :new_customer_id.

-- Step 2: INSERT customer_voucher (will succeed)
INSERT INTO customer_voucher (customer_id, voucher_id, status_id, saved_at)
VALUES (
    :new_customer_id,
    :voucher_id,
    :cv_saved_status_id,
    NOW()
);

-- Step 3: INSERT budget_transaction with invalid amount (will FAIL)
-- This simulates a logic error or constraint violation.
INSERT INTO budget_transaction
    (program_id, entry_type, amount, description)
VALUES (
    :program_id,
    'spend',
    -9999999,           -- intentionally invalid: negative amount violates chk_bt_amount_positive
    'DDID11-ScenarioB: INVALID overspend'
);
-- → Expected ERROR: new row for relation "budget_transaction" violates check constraint "chk_bt_amount_positive"

ROLLBACK;
-- Cancels ALL of the above — customer, voucher assignment, and budget record.

-- Verify — same count query as baseline:
SELECT
    (SELECT COUNT(*) FROM customer WHERE first_name = 'Test') AS customers_count,
    (SELECT COUNT(*) FROM budget_transaction WHERE description LIKE 'DDID11-ScenarioB%') AS bt_count;


-- ----------------------------------------------------------------------------
-- Scenario C — SAVEPOINT: Undo One Step, Keep the Rest
-- ----------------------------------------------------------------------------

BEGIN;

-- Step 1: INSERT customer (valid)
INSERT INTO customer (first_name, last_name, phone_number, email, status_id)
VALUES (
    'Test',
    'Customer C',
    '0911000003',
    'test.scenarioC@demo.com',
    :cust_active_status_id
)
RETURNING customer_id \gset new_
-- → Capture :new_customer_id from the result.

SAVEPOINT after_customer;
-- ↑ Checkpoint: everything up to here is safe.

-- Step 2: Attempt to assign a NON-EXISTENT voucher → FK violation
INSERT INTO customer_voucher (customer_id, voucher_id, status_id, saved_at)
VALUES (
    :new_customer_id,
    99999999,              -- deliberately invalid voucher_id (does not exist)
    :cv_saved_status_id,
    NOW()
);
-- → Expected ERROR: insert or update on table "customer_voucher" violates foreign key constraint "fk_cv_voucher"

ROLLBACK TO SAVEPOINT after_customer;
-- Undoes only Step 2. Step 1 (customer INSERT) is still alive.

-- Step 3: Retry with the correct voucher_id
INSERT INTO customer_voucher (customer_id, voucher_id, status_id, saved_at)
VALUES (
    :new_customer_id,
    :voucher_id,        -- correct voucher_id
    :cv_saved_status_id,
    NOW()
);
-- → Succeeds.

COMMIT;

-- Verify:
-- Customer exists?
SELECT customer_id, last_name FROM customer WHERE phone_number = '0911000003';

-- Voucher correctly assigned?
SELECT customer_voucher_id, customer_id, voucher_id
FROM customer_voucher
WHERE customer_id = :new_customer_id;

-- No orphaned data from the failed attempt?
SELECT COUNT(*) FROM customer_voucher WHERE voucher_id = 99999999;
-- Expected: 0


-- ============================================================================
-- 💬 REFLECTION QUESTIONS & ANSWERS
-- ============================================================================
/*
Question 1 — RETURNING chaining:
“In Scenario A, you used RETURNING to pass the customer_id directly into the next INSERT without a separate SELECT. What would happen if two users ran Scenario A simultaneously without RETURNING — both selecting the ID by phone number after the INSERT?”

Answer:
If two users execute Scenario A simultaneously without RETURNING and try to retrieve the customer_id using a separate SELECT (e.g., by filtering on a phone number or email):
1. Race Condition: Under high concurrency, there is a risk that one user's session selects the ID of the other user's record if the unique constraints are not properly checked or if there is a delay between insertion and retrieval.
2. Unnecessary Round-trips: Omitting RETURNING requires the application to perform an additional database round-trip (SELECT query) right after the INSERT, increasing network latency and database resource consumption.
3. Transaction Complexity: RETURNING chaining allows the entire multi-table insertion to occur atomically in a single network round-trip, guaranteeing that the returned ID is scoped exactly to that specific connection/statement.

Question 2 — SAVEPOINT:
“In Scenario C, SAVEPOINT let you recover from a bad row without aborting the whole transaction. Name one concrete situation in this marketing system where SAVEPOINT would be valuable in production.”

Answer:
A concrete situation is a "Multi-Voucher Package Claim Flow" during new customer signup.
When a customer registers, the system tries to assign three welcome vouchers: a Free Shipping voucher, a 10% Discount voucher, and a Partner affiliate voucher.
If the Partner voucher fails to assign (e.g. because it has reached its issuance limit and violates a constraint), we do not want to abort the customer's entire account creation and other voucher assignments.
By using SAVEPOINTs:
1. Create customer account.
2. Set SAVEPOINT after_signup.
3. Try to insert Partner voucher -> fails -> ROLLBACK TO SAVEPOINT -> continue.
4. Try to insert Free Shipping voucher -> succeeds.
5. Try to insert 10% Discount voucher -> succeeds.
6. COMMIT the transaction.
The customer's account and the valid vouchers are successfully saved, while the single failure is handled gracefully without blocking the entire transaction.
*/
