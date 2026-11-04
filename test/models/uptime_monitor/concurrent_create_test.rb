require "test_helper"

# Concurrent creates against the account's monitor limit, each thread on its
# own connection. Runs outside a test transaction so each create commits.
class UptimeMonitor::ConcurrentCreateTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  THREADS = 4
  LIMIT = 2

  setup do
    suffix = SecureRandom.hex(4)
    @account = Account.create!(name: "Race #{suffix}", entitlement_values: { "max_monitors" => LIMIT })
    @projects = Array.new(2) { |i| @account.projects.create!(name: "race-#{suffix}-#{i}") }
  end

  teardown do
    Project.where(id: @projects.map(&:id)).delete_all # rows cascade in the database
    Account.where(id: @account.id).delete_all
  end

  test "concurrent creates never exceed the account's monitor limit" do
    results = with_hosted_mode { create_concurrently }

    assert_equal LIMIT, results.count(true)
    assert_equal LIMIT, UptimeMonitor.where(project_id: @projects.map(&:id)).count
  end

  private
    def create_concurrently
      start = Queue.new
      threads = Array.new(THREADS) do |i|
        Thread.new do
          start.pop
          ActiveRecord::Base.connection_pool.with_connection { create_monitor(@projects[i % 2], i) }
        end
      end
      THREADS.times { start << true }
      threads.map(&:value)
    end

    def create_monitor(project, index)
      UptimeMonitor.new(project_id: project.id, name: "Race #{index}", url: "https://race#{index}.example/").save
    end
end
