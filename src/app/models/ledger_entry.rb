# frozen_string_literal: true

class LedgerEntry < ActiveRecord::Base
  self.table_name = 'ledger_entries'
  
  # Disable STI: type is a domain enum, not an inheritance discriminator
  self.inheritance_column = :_type_disabled

  # アソシエーション
  belongs_to :user
  # transaction は ActiveRecord の予約メソッドと衝突するため、bnpl_transaction にリネーム
  belongs_to :bnpl_transaction,
             class_name: 'Transaction',
             foreign_key: 'transaction_id',
             optional: true
  belongs_to :invoice, optional: true
  belongs_to :payment, optional: true
end

