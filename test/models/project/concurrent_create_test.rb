require "test_helper"

# Concurrent creates against the account's app limit (max_projects), each
# thread on its own connection. Runs outside a test transaction so each
# create commits.
class Project::ConcurrentCreateTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  THREADS = 4
  LIMIT = 2
  NAMES = %w[ alpha bravo charlie delta ].freeze # distinct issue prefixes

  setup do
    @suffix = SecureRandom.hex(4)
    @account = Account.create!(name: "Race #{@suffix}", entitlement_values: { "max_projects" => LIMIT })
  end

  teardown do
    Project.where(account_id: @account.id).delete_all # rows cascade in the database
    Account.where(id: @account.id).delete_all
  end

  test "concurrent creates never exceed the account's app limit" do
    results = with_hosted_mode { create_concurrently }

    assert_equal LIMIT, results.count(true)
    assert_equal LIMIT, Project.where(account_id: @account.id).count
  end

  private
    def create_concurrently
      start = Queue.new
      threads = Array.new(THREADS) do |i|
        Thread.new do
          start.pop
          ActiveRecord::Base.connection_pool.with_connection { create_project(i) }
        end
      end
      THREADS.times { start << true }
      threads.map(&:value)
    end

    def create_project(index)
      Project.new(account_id: @account.id, name: "#{NAMES[index]} #{@suffix}").save
    end
end
