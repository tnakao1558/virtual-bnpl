# frozen_string_literal: true

module Exceptions
  # 利用不可（枠不足）エラー
  # available_credit < amount の場合に発生
  class InsufficientCreditError < BusinessError
    attr_reader :available_credit, :amount

    def initialize(available_credit:, amount:, message: nil)
      @available_credit = available_credit
      @amount = amount
      error_message = message || "Insufficient credit: available=#{available_credit}, required=#{amount}"
      super(error_message, code: 'INSUFFICIENT_CREDIT')
    end
  end
end

