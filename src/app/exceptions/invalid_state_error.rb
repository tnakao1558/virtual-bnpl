# frozen_string_literal: true

module Exceptions
  # 状態不正エラー
  # ユーザーや与信口座の状態が不正、または OVERDUE の invoice が存在する場合に発生
  class InvalidStateError < BusinessError
    def initialize(message = 'Invalid state for transaction authorization')
      super(message, code: 'INVALID_STATE')
    end
  end
end

