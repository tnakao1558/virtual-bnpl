# frozen_string_literal: true

class Merchant < ActiveRecord::Base
  self.table_name = 'merchants'

  # アソシエーション
  has_many :transactions
end

