BEGIN;

CREATE TYPE user_status AS ENUM (
  'ACTIVE',
  'SUSPENDED',
  'CLOSED'
);

CREATE TYPE merchant_status AS ENUM (
  'ACTIVE',
  'STOPPED'
);

CREATE TYPE credit_account_status AS ENUM (
  'ACTIVE',
  'SUSPENDED'
);

CREATE TYPE transaction_status AS ENUM (
  'AUTHORIZED',
  'CAPTURED',
  'VOIDED',
  'REFUNDED'
);

CREATE TYPE invoice_status AS ENUM (
  'DRAFT',
  'ISSUED',
  'PAID',
  'OVERDUE',
  'CANCELED'
);

CREATE TYPE payment_status AS ENUM (
  'SUCCEEDED',
  'FAILED',
  'PENDING'
);

CREATE TYPE ledger_entry_type AS ENUM (
  'AUTH_HOLD',
  'CAPTURE',
  'VOID',
  'REFUND',
  'PAYMENT'
);

CREATE TYPE audit_actor_type AS ENUM (
  'USER',
  'ADMIN',
  'SYSTEM'
);

COMMIT;
