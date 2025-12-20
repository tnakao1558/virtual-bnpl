# frozen_string_literal: true

module Exceptions
  # ビジネス例外の基底クラス
  class BusinessError < StandardError
    attr_reader :code

    def initialize(message, code: nil)
      super(message)
      @code = code
    end
  end
end

