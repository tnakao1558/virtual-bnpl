# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe UseCases::Transactions::AuthorizeTransaction, type: :model do

  let(:user) { create_user }
  let(:merchant) { create_merchant }
  let(:credit_account) { create_credit_account(user:, credit_limit: 1000, available_credit: 1000) }

  before do
    # Ensure credit account exists and is in correct state
    credit_account
  end

  after(:all) do
    # Clean up test data after all examples
    Transaction.delete_all
    LedgerEntry.delete_all
    AuditLog.delete_all
    CreditAccount.delete_all
    Merchant.delete_all
    User.delete_all
  end

  describe 'when concurrent authorization exceeds credit limit' do
    it 'allows only one transaction to succeed' do
      # Prepare synchronization primitives
      # ready_queue: threads signal when they are ready
      # start_queue: main thread signals when to start
      ready_queue = Queue.new
      start_queue = Queue.new
      results = Queue.new
      errors = Queue.new

      # Thread A: authorizeTransaction(amount: 600)
      thread_a = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Signal that thread is ready
          ready_queue.push(:ready)
          # Wait for start signal
          start_queue.pop
          begin
            transaction = UseCases::Transactions::AuthorizeTransaction.call(
              user_id: user.id,
              merchant_id: merchant.id,
              amount: 600,
              idempotency_key: SecureRandom.uuid
            )
            results.push({ thread: 'A', success: true, transaction_id: transaction.id })
          rescue Exceptions::InsufficientCreditError => e
            errors.push({ thread: 'A', error: 'InsufficientCreditError', message: e.message })
          rescue Exceptions::IntegrityError => e
            errors.push({ thread: 'A', error: 'IntegrityError', message: e.message })
          rescue StandardError => e
            # Unexpected errors must fail the test
            errors.push({ thread: 'A', error: e.class.name, message: e.message, unexpected: true })
          end
        end
      end

      # Thread B: authorizeTransaction(amount: 600)
      thread_b = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Signal that thread is ready
          ready_queue.push(:ready)
          # Wait for start signal
          start_queue.pop
          begin
            transaction = UseCases::Transactions::AuthorizeTransaction.call(
              user_id: user.id,
              merchant_id: merchant.id,
              amount: 600,
              idempotency_key: SecureRandom.uuid
            )
            results.push({ thread: 'B', success: true, transaction_id: transaction.id })
          rescue Exceptions::InsufficientCreditError => e
            errors.push({ thread: 'B', error: 'InsufficientCreditError', message: e.message })
          rescue Exceptions::IntegrityError => e
            errors.push({ thread: 'B', error: 'IntegrityError', message: e.message })
          rescue StandardError => e
            # Unexpected errors must fail the test
            errors.push({ thread: 'B', error: e.class.name, message: e.message, unexpected: true })
          end
        end
      end

      # Wait for both threads to be ready
      ready_queue.pop
      ready_queue.pop

      # Start both threads simultaneously
      start_queue.push(:start)
      start_queue.push(:start)

      # Wait for both threads to complete
      thread_a.join
      thread_b.join

      # Collect results
      result_array = []
      error_array = []
      # Pop all results (non_blocking to avoid hanging)
      loop do
        result = results.pop(true) rescue nil
        break unless result
        result_array << result
      end
      loop do
        error = errors.pop(true) rescue nil
        break unless error
        error_array << error
      end

      success_count = result_array.size
      error_count = error_array.size

      # Check for unexpected errors first (must fail the test)
      unexpected_errors = error_array.select { |e| e[:unexpected] }
      if unexpected_errors.any?
        fail "Unexpected errors occurred: #{unexpected_errors.map { |e| "#{e[:thread]}: #{e[:error]} - #{e[:message]}" }.join(', ')}"
      end

      # Verify all errors are expected types
      error_array.each do |error|
        expect(['InsufficientCreditError', 'IntegrityError']).to include(error[:error]),
                                                                  "Unexpected error type: #{error[:error]} from thread #{error[:thread]}"
      end

      # Assertions
      expect(success_count).to eq(1), "Expected exactly 1 success, got #{success_count}. Errors: #{error_array}"
      expect(error_count).to eq(1), "Expected exactly 1 error, got #{error_count}"

      # Verify database state
      expect(Transaction.count).to eq(1), 'Expected exactly 1 transaction'
      expect(LedgerEntry.count).to eq(1), 'Expected exactly 1 ledger entry'

      ledger_entry = LedgerEntry.first
      expect(ledger_entry.type).to eq('AUTH_HOLD'), 'Expected ledger entry type to be AUTH_HOLD'
      expect(ledger_entry.amount_delta).to eq(-600), 'Expected ledger entry amount_delta to be -600'

      # Reload credit account and verify available_credit
      credit_account.reload
      expect(credit_account.available_credit).to eq(400), 'Expected available_credit to be 400'

      # Verify Ledger-derived available_credit matches credit_accounts.available_credit
      calculated_credit = Domain::Credit::CreditCalculator.calculate_available(
        user_id: user.id,
        credit_limit: credit_account.credit_limit
      )
      expect(calculated_credit).to eq(credit_account.available_credit),
                                   "Ledger-derived credit (#{calculated_credit}) must match stored credit (#{credit_account.available_credit})"
    end
  end

  describe 'when concurrent authorization uses same idempotency key' do
    it 'creates only one transaction and returns same transaction ID' do
      idempotency_key = SecureRandom.uuid

      # Prepare synchronization primitives
      # ready_queue: threads signal when they are ready
      # start_queue: main thread signals when to start
      ready_queue = Queue.new
      start_queue = Queue.new
      results = Queue.new
      errors = Queue.new

      # Thread A: authorizeTransaction with idempotency_key
      thread_a = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Signal that thread is ready
          ready_queue.push(:ready)
          # Wait for start signal
          start_queue.pop
          begin
            transaction = UseCases::Transactions::AuthorizeTransaction.call(
              user_id: user.id,
              merchant_id: merchant.id,
              amount: 500,
              idempotency_key:
            )
            results.push({ thread: 'A', success: true, transaction_id: transaction.id })
          rescue StandardError => e
            errors.push({ thread: 'A', error: e.class.name, message: e.message })
          end
        end
      end

      # Thread B: authorizeTransaction with same idempotency_key
      thread_b = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Signal that thread is ready
          ready_queue.push(:ready)
          # Wait for start signal
          start_queue.pop
          begin
            transaction = UseCases::Transactions::AuthorizeTransaction.call(
              user_id: user.id,
              merchant_id: merchant.id,
              amount: 500,
              idempotency_key:
            )
            results.push({ thread: 'B', success: true, transaction_id: transaction.id })
          rescue StandardError => e
            errors.push({ thread: 'B', error: e.class.name, message: e.message })
          end
        end
      end

      # Wait for both threads to be ready
      ready_queue.pop
      ready_queue.pop

      # Start both threads simultaneously
      start_queue.push(:start)
      start_queue.push(:start)

      # Wait for both threads to complete
      thread_a.join
      thread_b.join

      # Collect results
      result_array = []
      error_array = []
      # Pop all results (non_blocking to avoid hanging)
      loop do
        result = results.pop(true) rescue nil
        break unless result
        result_array << result
      end
      loop do
        error = errors.pop(true) rescue nil
        break unless error
        error_array << error
      end

      # Assertions
      expect(error_array).to be_empty, "Expected no errors, got: #{error_array}"
      expect(result_array.size).to eq(2), "Expected 2 successful results, got #{result_array.size}"

      # Both threads must return the same transaction ID
      transaction_ids = result_array.map { |r| r[:transaction_id] }
      expect(transaction_ids.uniq.size).to eq(1),
                                          "Expected both threads to return same transaction ID, got: #{transaction_ids}"

      # Verify database state
      expect(Transaction.count).to eq(1), 'Expected exactly 1 transaction'
      expect(LedgerEntry.count).to eq(1), 'Expected exactly 1 ledger entry'

      # Verify the transaction has the correct idempotency_key
      transaction = Transaction.first
      expect(transaction.idempotency_key).to eq(idempotency_key)
      expect(transaction.amount).to eq(500)

      # Verify available_credit
      credit_account.reload
      expect(credit_account.available_credit).to eq(500), 'Expected available_credit to be 500'

      # Verify Ledger-derived available_credit matches
      calculated_credit = Domain::Credit::CreditCalculator.calculate_available(
        user_id: user.id,
        credit_limit: credit_account.credit_limit
      )
      expect(calculated_credit).to eq(credit_account.available_credit),
                                   "Ledger-derived credit (#{calculated_credit}) must match stored credit (#{credit_account.available_credit})"
    end
  end

  private

  def create_user
    User.create!(
      id: SecureRandom.uuid,
      email: "user_#{SecureRandom.hex(8)}@example.com",
      status: 'ACTIVE',
      mfa_enabled: false
    )
  end

  def create_merchant
    Merchant.create!(
      id: SecureRandom.uuid,
      name: "Merchant #{SecureRandom.hex(8)}",
      status: 'ACTIVE'
    )
  end

  def create_credit_account(user:, credit_limit:, available_credit:)
    CreditAccount.create!(
      id: SecureRandom.uuid,
      user_id: user.id,
      credit_limit:,
      available_credit:,
      status: 'ACTIVE'
    )
  end
end

