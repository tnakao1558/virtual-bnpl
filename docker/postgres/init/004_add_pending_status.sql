BEGIN;

-- Add PENDING status to transaction_status enum
-- This is used for temporary transaction state before credit verification
ALTER TYPE transaction_status ADD VALUE IF NOT EXISTS 'PENDING';

COMMIT;

