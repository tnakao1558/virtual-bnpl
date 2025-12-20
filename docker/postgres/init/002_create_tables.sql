BEGIN;

-- =========================
-- users
-- =========================
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  status user_status NOT NULL DEFAULT 'ACTIVE',
  mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================
-- merchants
-- =========================
CREATE TABLE merchants (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  status merchant_status NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================
-- credit_accounts
-- =========================
CREATE TABLE credit_accounts (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE
    REFERENCES users(id) ON DELETE RESTRICT,
  credit_limit INTEGER NOT NULL CHECK (credit_limit >= 0),
  available_credit INTEGER NOT NULL
    CHECK (
      available_credit >= 0
      AND available_credit <= credit_limit
    ),
  status credit_account_status NOT NULL DEFAULT 'ACTIVE',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================
-- invoices
-- =========================
CREATE TABLE invoices (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL
    REFERENCES users(id) ON DELETE RESTRICT,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  due_date DATE NOT NULL,
  subtotal_amount INTEGER NOT NULL CHECK (subtotal_amount >= 0),
  adjustment_amount INTEGER NOT NULL DEFAULT 0,
  total_amount INTEGER NOT NULL CHECK (total_amount >= 0),
  status invoice_status NOT NULL,
  issued_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT unique_user_period
    UNIQUE (user_id, period_start, period_end),

  CONSTRAINT check_total_amount
    CHECK (total_amount = subtotal_amount + adjustment_amount)
);

-- =========================
-- transactions
-- =========================
CREATE TABLE transactions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL
    REFERENCES users(id) ON DELETE RESTRICT,
  merchant_id UUID NOT NULL
    REFERENCES merchants(id) ON DELETE RESTRICT,
  amount INTEGER NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL DEFAULT 'JPY'
    CHECK (currency = 'JPY'),
  status transaction_status NOT NULL DEFAULT 'AUTHORIZED',
  invoice_id UUID
    REFERENCES invoices(id) ON DELETE SET NULL,
  idempotency_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT unique_transaction_idempotency
    UNIQUE (user_id, idempotency_key)
);

-- =========================
-- invoice_items
-- =========================
CREATE TABLE invoice_items (
  id UUID PRIMARY KEY,
  invoice_id UUID NOT NULL
    REFERENCES invoices(id) ON DELETE CASCADE,
  transaction_id UUID NOT NULL
    REFERENCES transactions(id) ON DELETE RESTRICT,
  amount INTEGER NOT NULL CHECK (amount > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT unique_transaction_invoice
    UNIQUE (transaction_id)
);

-- =========================
-- payments
-- =========================
CREATE TABLE payments (
  id UUID PRIMARY KEY,
  invoice_id UUID NOT NULL
    REFERENCES invoices(id) ON DELETE RESTRICT,
  provider TEXT NOT NULL,
  provider_payment_id TEXT,
  amount INTEGER NOT NULL CHECK (amount > 0),
  status payment_status NOT NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================
-- ledger_entries
-- =========================
CREATE TABLE ledger_entries (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL
    REFERENCES users(id) ON DELETE RESTRICT,
  type ledger_entry_type NOT NULL,
  amount_delta INTEGER NOT NULL,
  transaction_id UUID
    REFERENCES transactions(id) ON DELETE RESTRICT,
  invoice_id UUID
    REFERENCES invoices(id) ON DELETE RESTRICT,
  payment_id UUID
    REFERENCES payments(id) ON DELETE RESTRICT,
  balance_after INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================
-- audit_logs
-- =========================
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  actor_type audit_actor_type NOT NULL,
  actor_id UUID NOT NULL,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id UUID NOT NULL,
  ip INET,
  user_agent TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
