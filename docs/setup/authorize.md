# authorizeTransaction 実装ガイド

このドキュメントは、
後払い取引の「与信枠予約（authorizeTransaction）」を
安全に実装・検証するための手順と設計ルールをまとめたものです。

本処理は後払いシステムの中核であり、
金額・残高・同時実行・冪等性をすべて考慮する必要があります。

---

## 1. authorizeTransaction の役割

authorizeTransaction は以下を保証します。

- 利用可能額（available_credit）を超えた取引を防ぐ
- 同時実行でも二重利用を起こさない
- 同じリクエストが複数回送られても結果が変わらない（冪等）
- すべての金額変動を Ledger に記録する

---

## 2. 前提条件（必須）

以下を満たさない場合、処理は失敗とします。

- users.status = ACTIVE
- credit_accounts.status = ACTIVE
- OVERDUE 状態の invoice が存在しない
- amount > 0
- currency = JPY

---

## 3. 入力と出力

### 入力
- user_id
- merchant_id
- amount
- idempotency_key

### 出力
- transaction_id
- status = AUTHORIZED

---

## 4. 処理フロー（必ずこの順）

### ① DB トランザクション開始

- READ COMMITTED 以上
- 1リクエスト = 1トランザクション

---

### ② 冪等性チェック

- user_id + idempotency_key で transactions を検索
- 既存レコードが存在する場合
  - 新規作成せず、既存結果を返す
  - Ledger を二重に作らない

---

### ③ credit_accounts をロック

- SELECT ... FOR UPDATE
- 同一ユーザーの同時 authorize を直列化する

---

### ④ 利用可否チェック

- available_credit >= amount
- 満たさない場合は 409 Conflict

---

### ⑤ transaction 作成

- status = AUTHORIZED
- currency = JPY
- invoice_id = NULL

---

### ⑥ ledger_entries 作成

- type = AUTH_HOLD
- amount_delta = -amount
- transaction_id を紐付ける

---

### ⑦ available_credit 更新

- Ledger から再計算した値と一致することを確認
- 不一致の場合はロールバック

---

### ⑧ audit_logs 作成

- action = TRANSACTION_AUTHORIZED
- 金額・対象・actor を metadata に記録

---

### ⑨ コミット

- 途中で失敗した場合は必ずロールバック

---

## 5. 同時実行に関する注意（重要）

以下の状況を必ず防止します。

- 並列 authorize による枠超過
- 冪等キー競合時の二重 Ledger 作成

対策：
- credit_accounts を FOR UPDATE でロック
- idempotency_key に UNIQUE 制約
- トランザクション境界を明確にする

---

## 6. エラーハンドリング指針

- 利用不可（枠不足）: 409 Conflict
- 状態不正（SUSPENDED / OVERDUE）: 403 Forbidden
- 冪等キー競合（意味的衝突）: 409 Conflict
- 内部不整合: 500 Internal Error（詳細はログのみ）

---

## 7. 実装後の確認手順

### 正常系
- authorize 実行で transactions が 1 件作成される
- ledger_entries が 1 件作成される
- available_credit が減少する

---

### 冪等性
- 同じ idempotency_key で複数回実行
  - transactions は 1 件のみ
  - ledger_entries も 1 件のみ

---

### 同時実行
- 並列リクエストを送信
- credit_limit を超えないこと

---

## 8. やってはいけないこと

- available_credit を直接減らすだけの実装
- Ledger を作らずに残高更新
- FOR UPDATE を使わない
- idempotency をアプリメモリで管理する

---

## 9. 実装スタンス

- 正しさ > パフォーマンス
- 速く壊れるより、遅くても壊れない
- 金融系では「例外ケース」が本体

この処理が安全に実装できれば、
後続の capture / invoice / payment は同じ思想で拡張できます。
