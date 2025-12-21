# frozen_string_literal: true

module Writers
  class AuditLogger
    # TRANSACTION_AUTHORIZED アクションの AuditLog を作成
    #
    # @param transaction [Transaction] 取引
    # @param actor_type [String] アクタータイプ（USER / ADMIN / SYSTEM）
    # @param actor_id [UUID] アクターID
    # @param ip [String, nil] IPアドレス（オプション）
    # @param user_agent [String, nil] User Agent（オプション）
    # @return [AuditLog] 作成された AuditLog
    def self.log_transaction_authorized(transaction:, actor_type:, actor_id:, ip: nil, user_agent: nil)
      new.log_transaction_authorized(
        transaction:,
        actor_type:,
        actor_id:,
        ip:,
        user_agent:
      )
    end

    def log_transaction_authorized(transaction:, actor_type:, actor_id:, ip:, user_agent:)
      AuditLog.create!(
        actor_type:,
        actor_id:,
        action: 'TRANSACTION_AUTHORIZED',
        target_type: 'TRANSACTION',
        target_id: transaction.id,
        ip:,
        user_agent:,
        metadata: {
          amount: transaction.amount,
          currency: transaction.currency,
          merchant_id: transaction.merchant_id,
          idempotency_key: transaction.idempotency_key
        }
      )
    end
  end
end

