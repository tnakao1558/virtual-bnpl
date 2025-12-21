# frozen_string_literal: true

module Exceptions
  # 整合性エラー
  # Ledger から再計算した available_credit と credit_accounts.available_credit が一致しない場合に発生
  class IntegrityError < BusinessError
    attr_reader :calculated_credit, :stored_credit

    def initialize(calculated_credit:, stored_credit:, message: nil)
      @calculated_credit = calculated_credit
      @stored_credit = stored_credit
      error_message = message || "Integrity mismatch: calculated=#{calculated_credit}, stored=#{stored_credit}"
      super(error_message, code: 'INTEGRITY_ERROR')
    end
  end
end

