# frozen_string_literal: true

module Domain
  module Credit
    class CreditChecker
      # 利用可否チェック
      # available_credit >= amount を判定する
      #
      # @param available_credit [Integer] 利用可能額
      # @param amount [Integer] 必要額
      # @raise [Exceptions::InsufficientCreditError] 利用不可（枠不足）の場合
      # @return [void] 利用可能な場合は何も返さない（例外を投げない）
      def self.check_available(available_credit:, amount:)
        new(available_credit:, amount:).check_available
      end

      def initialize(available_credit:, amount:)
        @available_credit = available_credit
        @amount = amount
      end

      def check_available
        return if @available_credit >= @amount

        raise Exceptions::InsufficientCreditError,
              available_credit: @available_credit,
              amount: @amount
      end
    end
  end
end

