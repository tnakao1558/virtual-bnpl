# frozen_string_literal: true

class LedgerEntry < ActiveRecord::Base
  self.table_name = 'ledger_entries'

  # アソシエーション
  belongs_to :user
  belongs_to :transaction, optional: true
  belongs_to :invoice, optional: true
  belongs_to :payment, optional: true
end

