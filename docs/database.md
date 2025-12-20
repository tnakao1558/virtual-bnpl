# Database Design - 仮想後払いサービス

## 1. 設計方針
本DBは以下を最優先とする。

- 後払い特有の **状態遷移の正確性**
- 金額・残高の **整合性と追跡可能性**
- セキュリティ・監査を前提とした設計
- 将来の仕様変更に耐えられる拡張性

「シンプルさ」よりも「壊れにくさ」を優先する。

---

## 2. 通貨・金額の扱い
- 通貨は **JPY 固定**
- 金額はすべて **integer（最小単位）**
- 浮動小数点は一切使用しない

---

## 3. エンティティ一覧（テーブル概要）

### users
利用者アカウント。

- 1ユーザーにつき1つの与信口座を持つ
- 個人情報は最小限（emailのみ）

主なカラム：
- id (uuid, PK)
- email (unique)
- status (ACTIVE / SUSPENDED / CLOSED)
- mfa_enabled
- created_at

---

### merchants
仮想加盟店。

- 実際の外部加盟店は存在しない
- 学習用途のため最小構成

主なカラム：
- id (uuid, PK)
- name
- status (ACTIVE / STOPPED)
- created_at

---

### credit_accounts
ユーザーごとの与信管理。

- user と 1:1
- 与信枠と利用可能額を管理する

主なカラム：
- id (uuid, PK)
- user_id (unique, FK)
- credit_limit
- available_credit（MVPでは冗長保持）
- status (ACTIVE / SUSPENDED)
- updated_at

設計メモ：
- 正の残高情報は Ledger から再計算可能であること
- available_credit は検証可能な冗長情報とする

---

### transactions
後払いの取引情報。

- 購入のたびに1レコード
- 状態遷移を厳密に管理する

主なカラム：
- id (uuid, PK)
- user_id (FK)
- merchant_id (FK)
- amount
- currency
- status (AUTHORIZED / CAPTURED / VOIDED / REFUNDED)
- invoice_id (nullable)
- idempotency_key (unique)
- created_at

制約：
- status の不正遷移は禁止（アプリ層で制御）
- 同一 idempotency_key の重複作成は禁止

---

### invoices
月次請求の親テーブル。

- user ごと、月次で1件
- 締め処理によって生成される

主なカラム：
- id (uuid, PK)
- user_id (FK)
- period_start
- period_end
- due_date
- subtotal_amount
- adjustment_amount
- total_amount
- status (DRAFT / ISSUED / PAID / OVERDUE / CANCELED)
- issued_at
- paid_at
- created_at

---

### invoice_items
請求明細。

- invoice と transaction の中間
- 1取引は1請求明細にのみ紐づく

主なカラム：
- id (uuid, PK)
- invoice_id (FK)
- transaction_id (FK, unique)
- amount
- created_at

---

### payments
支払い記録。

- 実決済は外部サービス or 手動
- 支払いの結果を記録するのみ

主なカラム：
- id (uuid, PK)
- invoice_id (FK)
- provider (stripe / manual)
- provider_payment_id (nullable)
- amount
- status (SUCCEEDED / FAILED / PENDING)
- paid_at
- created_at

---

### ledger_entries
台帳（残高の真実）。

- すべての金額変動はここを通す
- 直接残高を更新しない

主なカラム：
- id (uuid, PK)
- user_id (FK)
- type (AUTH_HOLD / CAPTURE / VOID / REFUND / PAYMENT)
- amount_delta
- transaction_id (nullable)
- invoice_id (nullable)
- payment_id (nullable)
- balance_after（MVPでは保持可）
- created_at

設計メモ：
- balance_after は監査・デバッグ用
- 正確性の正は Ledger の積み上げ結果

---

### audit_logs
監査ログ。

- 管理操作・重要操作を必ず記録
- 削除・更新は禁止（append-only）

主なカラム：
- id (uuid, PK)
- actor_type (USER / ADMIN / SYSTEM)
- actor_id
- action
- target_type
- target_id
- ip
- user_agent
- metadata (jsonb)
- created_at

---

## 4. リレーション概要
- users 1 — 1 credit_accounts
- users 1 — N transactions
- users 1 — N invoices
- invoices 1 — N invoice_items
- invoices 1 — N payments
- transactions 0 — 1 invoice_items
- users 1 — N ledger_entries

---

## 5. 重要な整合性ルール
- Transaction は必ず LedgerEntry を伴う
- Invoice に含まれる Transaction は CAPTURED のみ
- OVERDUE の Invoice がある場合、新規取引は禁止
- 支払い成功時のみ与信枠を回復させる

---

## 6. インデックス設計の方針
- 外部キーには基本 index を貼る
- 検索頻度が高いもの：
  - transactions.user_id
  - invoices.user_id + period
  - ledger_entries.user_id + created_at
- idempotency_key は unique index 必須

---

## 7. マイグレーション運用ルール
- 破壊的変更は禁止
- enum 変更は慎重に（追加のみ）
- 金額・状態に関わる変更は必ずレビューする

---

## 8. Cursor利用時の注意
- CREATE TABLE を生成する際は本ドキュメントを前提とする
- 勝手な正規化・省略をしない
- 金融系として危険な設計変更は必ず指摘する
