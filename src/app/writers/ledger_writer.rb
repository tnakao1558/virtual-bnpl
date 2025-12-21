# frozen_string_literal: true

module Writers
  class LedgerWriter
    # AUTH_HOLD タイプの LedgerEntry を作成
    #
    # @param user_id [UUID] ユーザーID
    # @param transaction [Transaction] 取引
    # @param amount [Integer] 金額
    # @return [LedgerEntry] 作成された LedgerEntry
    def self.create_auth_hold(user_id:, transaction:, amount:)
      new.create_auth_hold(user_id:, transaction:, amount:)
    end

    def create_auth_hold(user_id:, transaction:, amount:)
      LedgerEntry.create!(
        user_id:,
        type: 'AUTH_HOLD',
        amount_delta: -amount, # 負の値で利用枠を減らす
        transaction_id: transaction.id
      )
    end
  end
end

