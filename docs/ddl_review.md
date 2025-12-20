# DDL レビュー結果

## 1. 金融系として危険な点

### 🔴 重大: transactions.invoice_id に外部キー制約がない
```sql
-- 現在: 外部キー制約なし
invoice_id UUID NULL,

-- 修正案:
invoice_id UUID REFERENCES invoices(id),
```
**リスク**: 存在しない invoice_id を参照でき、データ整合性が破壊される可能性がある。

### 🔴 重大: currency が TEXT で CHECK 制約がない
```sql
-- 現在:
currency TEXT NOT NULL DEFAULT 'JPY',

-- 修正案:
currency TEXT NOT NULL DEFAULT 'JPY' CHECK (currency = 'JPY'),
```
**リスク**: architecture.md で「JPY固定」と明記されているが、DB層で強制されていない。誤って他の通貨が入る可能性がある。

### 🟡 中程度: credit_accounts.available_credit の上限チェックがない
```sql
-- 現在:
available_credit INTEGER NOT NULL CHECK (available_credit >= 0),

-- 修正案（推奨）:
available_credit INTEGER NOT NULL CHECK (available_credit >= 0 AND available_credit <= credit_limit),
```
**リスク**: available_credit が credit_limit を超える可能性がある。ただし、アプリ層で Ledger から再計算するため、DB層のチェックは補助的。

### 🟡 中程度: invoices.total_amount の整合性チェックがない
```sql
-- 現在: total_amount と subtotal_amount + adjustment_amount の整合性が保証されない

-- 修正案:
CONSTRAINT check_total_amount 
  CHECK (total_amount = subtotal_amount + adjustment_amount),
```
**リスク**: 請求書の金額計算が不整合になる可能性がある。

### 🟡 中程度: payments.amount の整合性チェックがない
**リスク**: invoice.total_amount と payments の合計が一致しない可能性がある。ただし、複数回支払いの可能性もあるため、アプリ層での制御が適切。

---

## 2. 整合性が壊れやすい箇所

### 🔴 重大: transactions と invoice_items の二重参照
```sql
-- transactions テーブル:
invoice_id UUID NULL,  -- 外部キー制約なし

-- invoice_items テーブル:
transaction_id UUID NOT NULL REFERENCES transactions(id),  -- 外部キーあり
```
**問題**: 
- `transactions.invoice_id` と `invoice_items.invoice_id` が不一致になる可能性がある
- `transactions.invoice_id` が NULL でも `invoice_items` に存在する可能性がある

**アプリ層での制約**: 
- `transactions.invoice_id` が設定されている場合、対応する `invoice_items` が存在し、`invoice_items.invoice_id` と一致すること
- `invoice_items` が存在する場合、`transactions.invoice_id` が設定されていること

### 🔴 重大: ledger_entries.amount_delta の符号チェックがない
```sql
-- 現在:
amount_delta INTEGER NOT NULL,  -- 符号チェックなし

-- 問題:
-- AUTH_HOLD, CAPTURE は負の値（与信枠を減らす）
-- VOID, REFUND, PAYMENT は正の値（与信枠を回復）
-- しかし、DB層では type と amount_delta の符号の整合性をチェックできない
```
**リスク**: 誤った符号の amount_delta が入る可能性がある。

**アプリ層での制約**:
- `type = 'AUTH_HOLD'` または `type = 'CAPTURE'` の場合、`amount_delta < 0`
- `type = 'VOID'` または `type = 'REFUND'` または `type = 'PAYMENT'` の場合、`amount_delta > 0`

### 🟡 中程度: credit_accounts.available_credit と Ledger の整合性
**問題**: `available_credit` は冗長情報だが、DB層で Ledger との整合性をチェックできない。

**アプリ層での制約**:
- `available_credit` を更新する際は、必ず Ledger から再計算した値と一致すること
- 定期的な整合性チェック（バッチ処理など）を実装すること

### 🟡 中程度: transactions.status の初期値がない
```sql
-- 現在:
status transaction_status NOT NULL,  -- デフォルト値なし

-- 問題: 取引作成時に status を明示的に指定する必要がある
```
**リスク**: アプリ層で status を指定し忘れるとエラーになるが、これは意図的かもしれない。

### 🟡 中程度: invoices.status と issued_at, paid_at の整合性
```sql
-- 現在: status と issued_at, paid_at の整合性が保証されない

-- 問題:
-- status = 'ISSUED' の場合、issued_at が NOT NULL であるべき
-- status = 'PAID' の場合、paid_at が NOT NULL であるべき
```

**アプリ層での制約**:
- `status = 'ISSUED'` の場合、`issued_at IS NOT NULL`
- `status = 'PAID'` の場合、`paid_at IS NOT NULL`
- `status = 'DRAFT'` の場合、`issued_at IS NULL`

### 🟡 中程度: payments.status と paid_at の整合性
```sql
-- 現在: status と paid_at の整合性が保証されない

-- 問題:
-- status = 'SUCCEEDED' の場合、paid_at が NOT NULL であるべき
```

**アプリ層での制約**:
- `status = 'SUCCEEDED'` の場合、`paid_at IS NOT NULL`
- `status = 'FAILED'` または `status = 'PENDING'` の場合、`paid_at IS NULL`

---

## 3. アプリ層で必ず守るべき制約

### 状態遷移の制約（architecture.md 5章）

#### Transaction Status 遷移
- **許可される遷移**:
  - `AUTHORIZED` → `CAPTURED` (売上確定)
  - `AUTHORIZED` → `VOIDED` (取消)
  - `CAPTURED` → `REFUNDED` (返金)
- **禁止される遷移**: 上記以外のすべて（例: `CAPTURED` → `VOIDED` は不可）

#### Invoice Status 遷移
- **許可される遷移**:
  - `DRAFT` → `ISSUED` (請求確定)
  - `ISSUED` → `PAID` (支払い完了)
  - `ISSUED` → `OVERDUE` (支払期限超過)
  - `ISSUED` → `CANCELED` (無効化)
  - `OVERDUE` → `PAID` (遅延後支払い)
- **禁止される遷移**: 上記以外のすべて

### 整合性ルール（database.md 5章）

#### 1. Transaction は必ず LedgerEntry を伴う
- すべての Transaction 作成・更新時に対応する LedgerEntry を作成すること
- `ledger_entries.transaction_id` が NULL の Transaction は存在しないこと

#### 2. Invoice に含まれる Transaction は CAPTURED のみ
- `invoice_items.transaction_id` で参照される Transaction の status は `CAPTURED` であること
- `status != 'CAPTURED'` の Transaction を Invoice に含めてはいけない

#### 3. OVERDUE の Invoice がある場合、新規取引は禁止
- ユーザーに `status = 'OVERDUE'` の Invoice が存在する場合、新規 Transaction の作成を拒否すること
- ユーザーの status を `SUSPENDED` に変更することも検討

#### 4. 支払い成功時のみ与信枠を回復させる
- `payments.status = 'SUCCEEDED'` の場合のみ LedgerEntry を作成し、与信枠を回復すること
- `payments.status = 'FAILED'` や `payments.status = 'PENDING'` では与信枠を回復しない

### 金額・残高の整合性

#### 1. available_credit の検証
- `credit_accounts.available_credit` を更新する際は、必ず Ledger から再計算した値と一致すること
- 再計算式: `available_credit = credit_limit + SUM(ledger_entries.amount_delta)`
- 不一致の場合はエラーを発生させる

#### 2. invoice_items.amount と transactions.amount
- `invoice_items.amount` は元の `transactions.amount` と異なる場合がある（調整のため）
- ただし、`invoice_items.amount` は `transactions.amount` を超えてはいけない（返金は別途処理）

#### 3. invoices.total_amount の計算
- `total_amount = subtotal_amount + adjustment_amount`
- `subtotal_amount = SUM(invoice_items.amount)` であること

#### 4. ledger_entries.amount_delta の符号
- `type = 'AUTH_HOLD'` または `type = 'CAPTURED'`: `amount_delta < 0` (与信枠を減らす)
- `type = 'VOID'` または `type = 'REFUND'`: `amount_delta > 0` (与信枠を回復)
- `type = 'PAYMENT'`: `amount_delta > 0` (与信枠を回復)

### リレーションの整合性

#### 1. transactions.invoice_id と invoice_items
- `transactions.invoice_id IS NOT NULL` の場合、対応する `invoice_items` が存在し、`invoice_items.invoice_id = transactions.invoice_id` であること
- `invoice_items` が存在する場合、`transactions.invoice_id IS NOT NULL` かつ一致すること

#### 2. credit_accounts と users の 1:1 関係
- 1ユーザーにつき1つの credit_account のみ存在すること（DB層で UNIQUE 制約あり）

#### 3. invoice_items.transaction_id の一意性
- 1取引は1請求明細にのみ紐づく（DB層で UNIQUE 制約あり）

### セキュリティ制約（architecture.md 8章）

#### 1. Idempotency-Key の必須操作
- 取引作成: `transactions` 作成時に `idempotency_key` を必須とする
- 売上確定: Transaction を `CAPTURED` に変更する際に `idempotency_key` を検証
- 支払い処理: `payments` 作成時に `idempotency_key` を必須とする

#### 2. 与信枠チェック
- 新規 Transaction 作成時（`AUTHORIZED`）に、`available_credit >= transaction.amount` であること
- 不足している場合は 409 Conflict を返す

#### 3. ユーザーステータスチェック
- `users.status != 'ACTIVE'` の場合、新規 Transaction の作成を拒否すること
- `credit_accounts.status != 'ACTIVE'` の場合も同様

---

## 推奨される DDL 修正

### 1. transactions.invoice_id に外部キー制約を追加
```sql
ALTER TABLE transactions 
  ADD CONSTRAINT fk_transactions_invoice_id 
  FOREIGN KEY (invoice_id) REFERENCES invoices(id);
```

### 2. currency に CHECK 制約を追加
```sql
ALTER TABLE transactions 
  ADD CONSTRAINT check_currency_jpy 
  CHECK (currency = 'JPY');
```

### 3. invoices.total_amount の整合性チェック
```sql
ALTER TABLE invoices 
  ADD CONSTRAINT check_total_amount 
  CHECK (total_amount = subtotal_amount + adjustment_amount);
```

### 4. credit_accounts.available_credit の上限チェック（オプション）
```sql
ALTER TABLE credit_accounts 
  ADD CONSTRAINT check_available_credit_limit 
  CHECK (available_credit <= credit_limit);
```

### 5. transactions.status にデフォルト値を追加（オプション）
```sql
ALTER TABLE transactions 
  ALTER COLUMN status SET DEFAULT 'AUTHORIZED';
```

---

## まとめ

### 必須修正（金融系として危険）
1. ✅ `transactions.invoice_id` に外部キー制約を追加
2. ✅ `transactions.currency` に CHECK 制約を追加（JPY固定）

### 推奨修正（整合性向上）
3. ✅ `invoices.total_amount` の整合性チェック
4. ⚠️ `credit_accounts.available_credit` の上限チェック（アプリ層で Ledger から再計算するため、DB層のチェックは補助的）

### アプリ層での必須実装
- 状態遷移の厳密な制御
- Ledger と available_credit の整合性検証
- Idempotency-Key の検証
- 与信枠チェック
- リレーション整合性の検証

