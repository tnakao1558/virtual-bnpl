# frozen_string_literal: true

module UseCases
  module Transactions
    class AuthorizeTransaction
      def self.call(user_id:, merchant_id:, amount:, idempotency_key:)
        new(
          user_id:,
          merchant_id:,
          amount:,
          idempotency_key:
        ).call
      end

      def initialize(user_id:, merchant_id:, amount:, idempotency_key:)
        @user_id = user_id
        @merchant_id = merchant_id
        @amount = amount
        @idempotency_key = idempotency_key
      end

      def call
        transaction = nil

        ActiveRecord::Base.transaction do
          # ① credit_account をロック
          credit_account = lock_credit_account

          # ② 冪等性チェック（ロック内）
          existing = find_existing_transaction
          return existing if existing

          # ③ 前提条件チェック
          validate_prerequisites(credit_account)

          # ④ PENDING transaction 作成（idempotency_key を占有）
          transaction = create_pending_transaction

          # ⑤ Ledger に AUTH_HOLD を記録
          create_ledger_entry(transaction)

          # ⑥ 利用可能額を再計算 & 検証
          update_and_verify_available_credit!(credit_account)

          # ⑦ transaction を AUTHORIZED に昇格
          authorize_transaction(transaction)

          # ⑧ audit log
          create_audit_log(transaction)
        end

        transaction
      rescue Exceptions::InsufficientCreditError => e
        # transaction 内で作られたすべてを rollback 済み
        raise e
      end

      private

      attr_reader :user_id, :merchant_id, :amount, :idempotency_key

      # ---- locking -------------------------------------------------

      def lock_credit_account
        CreditAccount.lock.find_by!(user_id:)
      end

      # ---- idempotency --------------------------------------------

      def find_existing_transaction
        Transaction.by_user_and_idempotency_key(user_id, idempotency_key).first
      end

      # ---- validation ---------------------------------------------

      def validate_prerequisites(credit_account)
        Validators::TransactionValidator.validate_authorize(
          user_id:,
          credit_account:,
          merchant_id:
        )
      end

      # ---- transaction lifecycle ----------------------------------

      def create_pending_transaction
        Transaction.create!(
          user_id:,
          merchant_id:,
          amount:,
          currency: 'JPY',
          status: 'PENDING',
          idempotency_key:,
          invoice_id: nil
        )
      end

      def authorize_transaction(transaction)
        transaction.update!(status: 'AUTHORIZED')
      end

      # ---- ledger --------------------------------------------------

      def create_ledger_entry(transaction)
        Writers::LedgerWriter.create_auth_hold(
          user_id:,
          transaction_id: transaction.id,
          amount:
        )
      end

      # ---- credit verification ------------------------------------

      def update_and_verify_available_credit!(credit_account)
        calculated_credit =
          Domain::Credit::CreditCalculator.calculate_available(
            user_id:,
            credit_limit: credit_account.credit_limit
          )

        # 枠超過 → rollback
        if calculated_credit < 0
          raise Exceptions::InsufficientCreditError.new(
            available_credit: calculated_credit,
            amount: amount,
            message: "Insufficient credit after ledger entry"
          )
        end

        # 整合性違反
        if calculated_credit > credit_account.credit_limit
          raise Exceptions::IntegrityError.new(
            calculated_credit:,
            stored_credit: credit_account.available_credit
          )
        end

        credit_account.update!(available_credit: calculated_credit)

        credit_account.reload
        if credit_account.available_credit != calculated_credit
          raise Exceptions::IntegrityError.new(
            calculated_credit:,
            stored_credit: credit_account.available_credit
          )
        end
      end

      # ---- audit ---------------------------------------------------

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
