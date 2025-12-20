# frozen_string_literal: true

module UseCases
  module Transactions
    class AuthorizeTransaction
      # 入力パラメータ
      # @param user_id [UUID] ユーザーID
      # @param merchant_id [UUID] 加盟店ID
      # @param amount [Integer] 金額（最小単位、JPY）
      # @param idempotency_key [String] 冪等性キー
      # @return [Transaction] 作成された取引
      # @raise [Exceptions::InsufficientCreditError] 利用不可（枠不足）
      # @raise [Exceptions::InvalidStateError] 状態不正
      # @raise [Exceptions::IntegrityError] 整合性エラー
      def self.call(user_id:, merchant_id:, amount:, idempotency_key:)
        new(user_id:, merchant_id:, amount:, idempotency_key:).call
      end

      def initialize(user_id:, merchant_id:, amount:, idempotency_key:)
        @user_id = user_id
        @merchant_id = merchant_id
        @amount = amount
        @idempotency_key = idempotency_key
      end

      def call
        ActiveRecord::Base.transaction do
          # ① DB トランザクション開始
          # 1リクエスト = 1トランザクション

          # ② credit_accounts をロック
          # 同一ユーザーの同時 authorize を直列化する
          credit_account = lock_credit_account

          # ③ 冪等性チェック（ロック内で実行）
          # 同一ユーザーの冪等性はロック内で保証する
          existing_transaction = find_existing_transaction
          return existing_transaction if existing_transaction

          # ④ 前提条件チェック
          validate_prerequisites(credit_account)

          # ⑤ 利用可否チェック
          # TODO: 実装予定

          # ⑥ transaction 作成
          # TODO: 実装予定

          # ⑦ ledger_entries 作成
          # TODO: 実装予定

          # ⑧ available_credit 更新
          # TODO: 実装予定

          # ⑨ audit_logs 作成
          # TODO: 実装予定

          # ⑩ コミット
          # 途中で失敗した場合は必ずロールバック（ActiveRecord が自動処理）
        end
      end

      private

      attr_reader :user_id, :merchant_id, :amount, :idempotency_key

      # ② credit_accounts をロック
      # SELECT ... FOR UPDATE
      # 同一ユーザーの同時 authorize を直列化する
      #
      # @return [CreditAccount] ロックされた与信口座
      # @raise [ActiveRecord::RecordNotFound] 与信口座が存在しない場合
      def lock_credit_account
        CreditAccount.lock.find_by!(user_id:)
      end

      # ③ 冪等性チェック（ロック内で実行）
      # user_id + idempotency_key で transactions を検索
      # 既存レコードが存在する場合、新規作成せず既存結果を返す
      # Ledger を二重に作らない
      # 同一ユーザーの冪等性はロック内で保証する
      #
      # @return [Transaction, nil] 既存の取引、存在しない場合は nil
      def find_existing_transaction
        Transaction.by_user_and_idempotency_key(user_id, idempotency_key).first
      end

      # ④ 前提条件チェック
      # Validator を使用して以下を確認：
      # - users.status = ACTIVE
      # - credit_accounts.status = ACTIVE
      # - OVERDUE 状態の invoice が存在しない
      #
      # @param credit_account [CreditAccount] 与信口座
      # @raise [Exceptions::InvalidStateError] 前提条件を満たさない場合
      def validate_prerequisites(credit_account)
        Validators::TransactionValidator.validate_authorize(
          user_id:,
          credit_account:,
          merchant_id:
        )
      end
    end
  end
end

