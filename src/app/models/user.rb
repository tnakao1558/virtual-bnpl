# frozen_string_literal: true

class User < ActiveRecord::Base
  self.table_name = 'users'

  # アソシエーション
  has_one :credit_account
  has_many :transactions
  has_many :invoices
end

