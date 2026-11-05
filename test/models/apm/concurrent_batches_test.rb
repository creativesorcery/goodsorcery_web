require "test_helper"
require_relative "apm_test_support"

# Several Sidekiq threads processing metrics for the same transaction and
# minute at once. Runs outside a test transaction so each thread commits on
# its own connection.
class Apm::ConcurrentBatchesTest < ActiveSupport::TestCase
  include ApmTestSupport

  self.use_transactional_tests = false

  THREADS = 4
  BATCHES = 12

  setup do
    @project = accounts(:acme).projects.create!(name: "APM concurrency #{SecureRandom.hex(4)}")
    @key = @project.api_keys.find_by!(environment: "production")
  end

  teardown { Project.where(id: @project.id).delete_all } # rows cascade in the database

  test "concurrent batches for one transaction-minute sum correctly without deadlocks" do
    minute = current_minute - 1.minute
    bodies = Array.new(BATCHES) do |index|
      metrics_body([ metrics_transaction, metrics_transaction(name: "Shared#job", kind: "job"),
                     metrics_transaction(name: "Only#{index}Controller#show") ], minute:)
    end
    ids = bodies.map { store_batch(it, key: @key) }

    errors = process_concurrently(ids)

    assert_empty errors.map { it.class.name }
    checkout = @project.apm_transactions.find_by!(name: "CheckoutsController#create")
    assert_equal 3 * BATCHES, ApmMinuteStat.find_by!(apm_transaction: checkout, minute:).requests_count
    assert_equal 2 * BATCHES, ApmMinuteStat.find_by!(apm_transaction: checkout, minute:).bucket_counts[15]
    web_total = ApmTransaction.total_for(@project, "production", "web")
    assert_equal 6 * BATCHES, ApmHourlyStat.find_by!(apm_transaction: web_total, hour: TimeSeries.align(minute, 1.hour)).requests_count
    assert_equal BATCHES + 1, @project.apm_transactions.listed.web.count
  end

  private
    def process_concurrently(ids)
      errors = Queue.new
      threads = ids.each_slice(BATCHES / THREADS).map do |slice|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { slice.each { Apm::BatchProcessor.new(it).process } }
        rescue StandardError => error
          errors << error
        end
      end
      threads.each(&:join)
      Array.new(errors.size) { errors.pop }
    end
end
