# frozen_string_literal: true

module Writers
  class LedgerWriter
    # AUTH_HOLD タイプの LedgerEntry を作成
    #
    # @param user_id [UUID] ユーザーID
    # @param transaction_id [UUID] 取引ID
    # @param amount [Integer] 金額
    # @return [LedgerEntry] 作成された LedgerEntry
    def self.create_auth_hold(user_id:, transaction_id:, amount:)
      new.create_auth_hold(user_id:, transaction_id:, amount:)
    end

    def create_auth_hold(user_id:, transaction_id:, amount:)
      LedgerEntry.create!(
        user_id:,
        type: 'AUTH_HOLD',
        amount_delta: -amount, # 負の値で利用枠を減らす
        transaction_id:
      )
    end
  end
end

