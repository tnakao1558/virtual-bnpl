# Database Setup Guide

このドキュメントは、本プロジェクトの
PostgreSQL 開発環境を「誰でも同じ状態」で立ち上げ、
DDL が正しく適用されていることを確認するための手順をまとめたものです。

本プロジェクトでは以下を前提とします。

- DB 環境は Docker Compose が唯一の正
- ローカル環境依存のセットアップは禁止
- DDL は init SQL により自動適用される

---

## 使用する PostgreSQL バージョン

- 基準（正）: PostgreSQL 16.3

本プロジェクトでは PostgreSQL 16.3 を使用します。

---

## ディレクトリ構成（DB 関連）

以下の構成になっていることを確認してください。

docker-compose.yml  
docker/postgres/init/  
  ├ 001_create_types.sql  
  ├ 002_create_tables.sql  
  └ 003_indexes.sql  

---

## DB の起動

プロジェクトのルートディレクトリで以下を実行します。

```bash
docker compose up -d
```

起動後、以下を確認してください。

- コンテナが running 状態になっている
- ポート 5432 が公開されている

確認コマンド例：

```bash
docker compose ps
```

---

## 初回起動時の注意

初回起動時のみ、以下の処理が自動で実行されます。

- enum 定義の作成
- テーブル作成
- インデックス作成

init SQL は docker-entrypoint-initdb.d に配置されており、
DB データが存在しない場合のみ実行されます。

DDL を修正した場合は、必ず DB を作り直してください。

```bash
docker compose down -v
docker compose up -d
```

---

## PostgreSQL への接続（psql）

psql は Docker コンテナ経由で実行します。
ローカルに psql をインストールする必要はありません。

接続コマンド：

```bash
docker compose exec db psql -U bnpl_user -d bnpl
```

接続に成功すると、以下のようなプロンプトが表示されます。

bnpl=#

---

## テーブル一覧の確認

psql 上で以下を実行します。

\dt

以下のテーブルがすべて表示されていれば成功です。

- users
- merchants
- credit_accounts
- transactions
- invoices
- invoice_items
- payments
- ledger_entries
- audit_logs

---

## transactions テーブルの確認

psql 上で以下を実行します。

\d transactions

以下を重点的に確認してください。

- 通貨が JPY 固定であること
- status が transaction_status enum であること
- idempotency_key に UNIQUE 制約があること
- users / merchants / invoices への外部キーが存在すること

---

## トラブルシューティング

### テーブルが存在しない場合

init SQL が途中で失敗している可能性があります。
以下を実行して DB を作り直してください。

```bash
docker compose down -v
docker compose up -d
```

### psql に接続できない場合

以下を確認してください。

- docker compose ps で db コンテナが起動しているか
- docker compose logs db にエラーが出ていないか

---

## 運用ルール（重要）

- init SQL ファイルは上書きしない
- DDL 変更は新しい SQL ファイルを追加する（例: 004_xxx.sql）
- enum の変更は追加のみ許可（既存値の削除は禁止）
- 既存カラムの削除は禁止
- 破壊的変更は避け、後方互換性を保つ

これらのルールは、金融系システムを想定した設計方針に基づいています。
詳細は `docs/database.md` の「7. マイグレーション運用ルール」を参照してください。
