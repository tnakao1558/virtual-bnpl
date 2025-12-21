# frozen_string_literal: true

module Domain
  module Credit
    class CreditCalculator
      # Ledger から利用可能額を計算（純粋な計算のみ）
      # 正の残高情報は Ledger から再計算可能であること
      #
      # 計算式：
      # available_credit = credit_limit + SUM(ledger_entries.amount_delta)
      #
      # amount_delta は負の値（AUTH_HOLD, CAPTURE など）と正の値（VOID, REFUND, PAYMENT など）を含む
      #
      # 注意：このメソッドは生の計算値を返す
      # - 検証やチェックは行わない
      # - 範囲外の値（負の値や credit_limit を超える値）は整合性違反として扱うべき
      # - 検証とエラーは UseCase 層で行う
      #
      # @param user_id [UUID] ユーザーID
      # @param credit_limit [Integer] 与信枠
      # @return [Integer] 計算された利用可能額（生の値、正規化なし）
      def self.calculate_available(user_id:, credit_limit:)
        # Ledger の合計を計算（ロック付き）
        # amount_delta の合計が負の値なら利用枠が減っている
        # lock により並行実行時に最新の ledger_sum を取得できる
        ledger_sum = LedgerEntry.where(user_id:).lock.sum(:amount_delta)

        # available_credit = credit_limit + ledger_sum
        # ledger_sum は負の値（AUTH_HOLD: -amount）なので、結果的に credit_limit から減算される
        # 生の計算値を返す（正規化・clamp は行わない）
        credit_limit + ledger_sum
      end
    end
  end
end

