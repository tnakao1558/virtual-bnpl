# frozen_string_literal: true

module Validators
  class TransactionValidator
    # authorizeTransaction の前提条件をチェック
    #
    # チェック項目：
    # - users.status = ACTIVE
    # - credit_accounts.status = ACTIVE
    # - OVERDUE 状態の invoice が存在しない
    #
    # @param user_id [UUID] ユーザーID
    # @param credit_account [CreditAccount] 与信口座
    # @param merchant_id [UUID] 加盟店ID
    # @raise [Exceptions::InvalidStateError] 前提条件を満たさない場合
    def self.validate_authorize(user_id:, credit_account:, merchant_id:)
      new(user_id:, credit_account:, merchant_id:).validate_authorize
    end

    def initialize(user_id:, credit_account:, merchant_id:)
      @user_id = user_id
      @credit_account = credit_account
      @merchant_id = merchant_id
    end

    def validate_authorize
      validate_user_status
      validate_credit_account_status
      validate_no_overdue_invoices
    end

    private

    attr_reader :user_id, :credit_account, :merchant_id

    # users.status = ACTIVE をチェック
    def validate_user_status
      user = credit_account.user
      return if user.status == 'ACTIVE'

      raise Exceptions::InvalidStateError,
            "User status must be ACTIVE, but got #{user.status}"
    end

    # credit_accounts.status = ACTIVE をチェック
    def validate_credit_account_status
      return if credit_account.status == 'ACTIVE'

      raise Exceptions::InvalidStateError,
            "Credit account status must be ACTIVE, but got #{credit_account.status}"
    end

    # OVERDUE 状態の invoice が存在しないことをチェック
    def validate_no_overdue_invoices
      overdue_invoice = Invoice.by_user(user_id).overdue.exists?
      return unless overdue_invoice

      raise Exceptions::InvalidStateError,
            'Cannot authorize transaction: user has OVERDUE invoice'
    end
  end
end

