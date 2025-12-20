# frozen_string_literal: true

class Invoice < ActiveRecord::Base
  self.table_name = 'invoices'

  # アソシエーション
  belongs_to :user

  # スコープ
  scope :overdue, -> { where(status: 'OVERDUE') }
  scope :by_user, ->(user_id) { where(user_id:) }
end

