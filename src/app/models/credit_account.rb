# frozen_string_literal: true

class CreditAccount < ActiveRecord::Base
  self.table_name = 'credit_accounts'

  # アソシエーション
  belongs_to :user
end

