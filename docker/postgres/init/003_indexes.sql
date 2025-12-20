BEGIN;

-- transactions
CREATE INDEX idx_transactions_user_id
  ON transactions(user_id);

CREATE INDEX idx_transactions_invoice_id
  ON transactions(invoice_id);

-- invoices
CREATE INDEX idx_invoices_user_id
  ON invoices(user_id);

CREATE INDEX idx_invoices_status
  ON invoices(status);

-- invoice_items
CREATE INDEX idx_invoice_items_invoice_id
  ON invoice_items(invoice_id);

-- ledger_entries
CREATE INDEX idx_ledger_user_created
  ON ledger_entries(user_id, created_at);

CREATE INDEX idx_ledger_transaction_id
  ON ledger_entries(transaction_id);

-- audit_logs
CREATE INDEX idx_audit_logs_created_at
  ON audit_logs(created_at);

COMMIT;
