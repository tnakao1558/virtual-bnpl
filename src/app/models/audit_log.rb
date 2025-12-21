# frozen_string_literal: true

class AuditLog < ActiveRecord::Base
  self.table_name = 'audit_logs'
end

