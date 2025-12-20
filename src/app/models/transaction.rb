# frozen_string_literal: true

class Transaction < ActiveRecord::Base
  self.table_name = 'transactions'

  # アソシエーション
  belongs_to :user
  belongs_to :merchant
  belongs_to :invoice, optional: true

  # スコープ
  scope :by_user_and_idempotency_key, ->(user_id, idempotency_key) do
    where(user_id:, idempotency_key:)
  end
end

