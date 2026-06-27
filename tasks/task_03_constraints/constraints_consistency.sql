 /*

DDID12_03 - CONSTRAINTS & CONSISTENCY
ACID - Consistency via Database Constraints
===========================================

## OBJECTIVE

Validate database-level consistency protections:

1. UNIQUE Constraint

   * Prevent duplicate customer registrations.

2. CHECK Constraint

   * Prevent invalid business data from being persisted.

3. Trigger Automation

   * Automatically maintain audit timestamps.

===============================================================================
STEP 0-A : TEST DATA DISCOVERY
==============================

*/

SELECT
v.voucher_id,
v.program_id,
v.issuance_limit,
v.total_issued
FROM linh_lab.voucher v
LIMIT 5;

/*
TEST DATA SELECTED
------------------

voucher_id      = 1
program_id      = 1
issuance_limit  = 1000
total_issued    = 125
*/

-- =============================================================================
-- STEP 0-B : AUDIT EXISTING CONSTRAINTS
-- =============================================================================

SELECT
conname AS constraint_name
FROM pg_constraint
WHERE conrelid = 'linh_lab.customer'::regclass
AND contype = 'u';

SELECT
conname AS constraint_name
FROM pg_constraint
WHERE conrelid = 'linh_lab.voucher'::regclass
AND contype = 'c';

/*
CONSTRAINTS VERIFIED
--------------------

Customer UNIQUE Constraints

* customer_phone_number_key
* customer_email_key

Voucher CHECK Constraints

* chk_issuance_limit
* chk_total_issued
* chk_voucher_date

Expected Scenario A Constraint

* customer_phone_number_key

Expected Scenario B Constraint

* chk_total_issued
  */

-- =============================================================================
-- STEP 0-C : CREATE / REFRESH UPDATED_AT TRIGGER
-- =============================================================================

CREATE OR REPLACE FUNCTION linh_lab.fn_set_updated_at()
RETURNS TRIGGER AS
$$
BEGIN
NEW.updated_at = NOW();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_promotion_program_updated_at
ON linh_lab.promotion_program;

CREATE TRIGGER trg_promotion_program_updated_at
BEFORE UPDATE
ON linh_lab.promotion_program
FOR EACH ROW
EXECUTE FUNCTION linh_lab.fn_set_updated_at();

/*

SCENARIO A : UNIQUE CONSTRAINT
Prevent Duplicate Customer Registration
=======================================

## EXPECTED RESULT

Insert succeeds.

## PURPOSE

Create a valid customer record.
*/

INSERT INTO linh_lab.customer
(
first_name,
last_name,
phone_number,
email,
status_id,
created_by
)
VALUES
(
'Duplicate',
'Tester',
'0999888777',
'[dup.test@demo.com](mailto:dup.test@demo.com)',
(
SELECT status_id
FROM linh_lab.status_master
WHERE status_code = 'ACTIVE'
AND entity_type = 'CUSTOMER'
),
'TEST_USER'
)
RETURNING
customer_id,
first_name,
last_name,
phone_number,
email;

/*
RESULT
------

SUCCESS

phone_number = 0999888777
email        = [dup.test@demo.com](mailto:dup.test@demo.com)

Customer record successfully created.
*/

/*
EXPECTED RESULT
---------------

ERROR

duplicate key value violates unique constraint
customer_phone_number_key

## PURPOSE

Verify database rejects duplicate phone numbers.
*/

INSERT INTO linh_lab.customer
(
first_name,
last_name,
phone_number,
email,
status_id,
created_by
)
VALUES
(
'Hacker',
'Man',
'0999888777',
'[hacker.man@demo.com](mailto:hacker.man@demo.com)',
(
SELECT status_id
FROM linh_lab.status_master
WHERE status_code = 'ACTIVE'
AND entity_type = 'CUSTOMER'
),
'TEST_USER'
);

/*
RESULT
------

FAILED AS EXPECTED

Constraint Triggered:
customer_phone_number_key

Business Rule:
One phone number can belong to only one customer.

Conclusion:
Database successfully prevented duplicate
customer registration.
*/

/*

SCENARIO B : CHECK CONSTRAINT
Prevent Invalid Voucher Issuance
================================

## EXPECTED RESULT

ERROR

chk_total_issued

## PURPOSE

Verify total_issued cannot exceed issuance_limit.
*/

UPDATE linh_lab.voucher
SET total_issued = issuance_limit + 10
WHERE voucher_id = 1;

/*
RESULT
------

FAILED AS EXPECTED

Constraint Triggered:
chk_total_issued

Attempted Values:
issuance_limit = 1000
total_issued   = 1010

Business Rule:
total_issued must never exceed issuance_limit.

Conclusion:
Database successfully prevented invalid
voucher issuance updates.
*/

/*

SCENARIO C : DATABASE TRIGGER
Automatic updated_at Maintenance
================================

*/

SELECT
program_id,
program_name,
updated_at
FROM linh_lab.promotion_program
WHERE program_id = 1;

/*
BASELINE
--------

program_id   = 1
program_name = Tết 2026

updated_at
= 2026-06-22 15:34:11.876
*/

UPDATE linh_lab.promotion_program
SET program_name =
program_name || ' (Updated)'
WHERE program_id = 1;

SELECT
program_id,
program_name,
updated_at
FROM linh_lab.promotion_program
WHERE program_id = 1;

/*
RESULT
------

SUCCESS

Trigger:
trg_promotion_program_updated_at

Before Update:
2026-06-22 15:34:11.876

After Update:
2026-06-24 15:14:27.364

Observation:
updated_at changed automatically without
explicitly executing:

updated_at = NOW()

Conclusion:
Database trigger successfully maintained
audit information.
*/

/*

# REFLECTION QUESTION 1

Even if application code validates data before
executing UPDATE statements, database constraints
are still required.

Application validation can fail because of:

* Bugs
* Race conditions
* Concurrent requests
* Direct database access

Database constraints act as the final line of
defense and guarantee invalid data cannot be
persisted.

===============================================================================
REFLECTION QUESTION 2
=====================

Without the trigger, developers would need to
manually update updated_at in every UPDATE
statement.

If a developer forgets to do so or performs
manual updates through DBeaver, the data would
change while updated_at remains unchanged.

This would reduce audit accuracy and make
troubleshooting more difficult.

===============================================================================
FINAL SUMMARY
=============

Scenario A
Verified UNIQUE constraint prevents duplicate
customer phone numbers.

Scenario B
Verified CHECK constraint prevents total_issued
from exceeding issuance_limit.

Scenario C
Verified trigger automatically updates
updated_at timestamps.

Result:
Database constraints and triggers successfully
enforced ACID Consistency requirements.

===============================================================================
*/
