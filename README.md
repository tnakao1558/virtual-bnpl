# 仮想後払いサービス（BNPL Sandbox）

このリポジトリは、後払い決済（BNPL）の構造を学習・検証するための
仮想サービスのバックエンド実装です。

本プロジェクトでは以下を重視しています。

- 後払い特有の状態遷移・データ設計
- 金融系サービスを想定したセキュリティ設計
- Ledger（台帳）による整合性管理
- 個人の開発環境に依存しない再現可能な環境構築

実際の金銭移動や外部決済は扱いません。

---

## ドキュメント構成

最初に以下のドキュメントを参照してください。

- アーキテクチャ概要  
  docs/architecture.md

- データベース設計  
  docs/database.md

- 開発環境（DB）セットアップ手順  
  docs/setup/database.md

---

## 開発環境の前提

- Docker / Docker Compose がインストールされていること
- ローカル環境に PostgreSQL や psql をインストールする必要はありません

## クイックスタート

### 1. データベースの起動

```bash
docker compose up -d
```

### 2. データベースへの接続確認

```bash
docker compose exec db psql -U bnpl_user -d bnpl
```

接続後、テーブル一覧を確認：

```sql
\dt
```

### 3. データベースの停止

```bash
docker compose down
```

データも含めて完全に削除する場合：

```bash
docker compose down -v
```

詳細な手順は `docs/setup/database.md` を参照してください。
