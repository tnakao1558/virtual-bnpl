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

          # ⑤ 利用可否チェック（予備チェック）
          # CreditChecker は fail-fast の予備チェックのみ
          # 最終的な権威は Ledger である
          check_credit_availability(credit_account)

          # ⑥ transaction 作成
          transaction = create_transaction

          # ⑦ ledger_entries 作成
          # 真実の源は Ledger
          create_ledger_entry(transaction)

          # ⑧ available_credit 更新と整合性検証
          # Ledger から再計算し、更新後に即座に検証する
          update_and_verify_available_credit(credit_account)

          # ⑨ audit_logs 作成
          # action = TRANSACTION_AUTHORIZED
          # 金額・対象・actor を metadata に記録
          create_audit_log(transaction)

          transaction

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

      # ⑤ 利用可否チェック（予備チェック）
      # CreditChecker は fail-fast の予備チェックのみ
      # 最終的な権威は Ledger である
      #
      # @param credit_account [CreditAccount] 与信口座
      # @raise [Exceptions::InsufficientCreditError] 利用不可（枠不足）の場合
      def check_credit_availability(credit_account)
        Domain::Credit::CreditChecker.check_available(
          available_credit: credit_account.available_credit,
          amount: amount
        )
      end

      # ⑥ transaction 作成
      # status = AUTHORIZED
      # currency = JPY
      # invoice_id = NULL
      #
      # @return [Transaction] 作成された取引
      def create_transaction
        Transaction.create!(
          user_id:,
          merchant_id:,
          amount:,
          currency: 'JPY',
          status: 'AUTHORIZED',
          idempotency_key:,
          invoice_id: nil
        )
      end

      # ⑦ ledger_entries 作成
      # 真実の源は Ledger
      # type = AUTH_HOLD
      # amount_delta = -amount
      # transaction_id を紐付ける
      #
      # @param transaction [Transaction] 取引
      def create_ledger_entry(transaction)
        Writers::LedgerWriter.create_auth_hold(
          user_id:,
          transaction_id: transaction.id,
          amount:
        )
      end

      # ⑧ available_credit 更新と整合性検証
      # Ledger から再計算した値と一致することを確認
      # 不一致の場合はロールバック
      #
      # @param credit_account [CreditAccount] 与信口座
      # @raise [Exceptions::IntegrityError] 整合性が取れない場合
      def update_and_verify_available_credit(credit_account)
        # Ledger から再計算（真実の源）
        # CreditCalculator は生の計算値を返す（正規化なし）
        calculated_credit = Domain::Credit::CreditCalculator.calculate_available(
          user_id:,
          credit_limit: credit_account.credit_limit
        )

        # 整合性検証：計算値が有効な範囲内であることを確認
        # 範囲外の値は整合性違反として扱う（clamp で隠さない）
        if calculated_credit < 0 || calculated_credit > credit_account.credit_limit
          raise Exceptions::IntegrityError,
                calculated_credit:,
                stored_credit: credit_account.available_credit,
                message: "Calculated credit is out of valid range: #{calculated_credit} (must be 0..#{credit_account.credit_limit})"
        end

        # available_credit を更新
        credit_account.update!(available_credit: calculated_credit)

        # 更新後に即座に検証
        # 更新後の stored 値が計算値と一致することを確認
        credit_account.reload
        if calculated_credit != credit_account.available_credit
          raise Exceptions::IntegrityError,
                calculated_credit:,
                stored_credit: credit_account.available_credit
        end
      end

      # ⑨ audit_logs 作成
      # action = TRANSACTION_AUTHORIZED
      # 金額・対象・actor を metadata に記録
      #
      # @param transaction [Transaction] 取引
      def create_audit_log(transaction)
        Writers::AuditLogger.log_transaction_authorized(
          transaction:,
          actor_type: 'USER',
          actor_id: user_id
        )
      end
    end
  end
end

