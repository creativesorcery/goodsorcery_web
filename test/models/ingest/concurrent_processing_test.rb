require "test_helper"
require_relative "ingest_test_support"

# Several processors working on events of one issue at once, as Sidekiq
# threads do during an error storm. Runs outside a test transaction so each
# thread commits on its own connection.
class Ingest::ConcurrentProcessingTest < ActiveSupport::TestCase
  include IngestTestSupport

  self.use_transactional_tests = false

  THREADS = 4
  EVENTS = 40

  setup do
    @project = accounts(:acme).projects.create!(name: "Concurrency #{SecureRandom.hex(4)}")
    @key = @project.api_keys.first
  end

  teardown { Project.where(id: @project.id).delete_all } # rows cascade in the database

  test "events of one issue process concurrently without deadlocks" do
    inbound = Array.new(EVENTS) { inbound_event_for(minimal_json, key: @key, event_uuid: SecureRandom.uuid) }

    errors = process_concurrently(inbound)

    assert_empty errors.map { |error| error.class.name }
    issue = @project.issues.sole
    assert_equal EVENTS, issue.events_count
    assert_equal EVENTS, ProjectHourlyCount.where(project: @project).sum(:count)
    assert_equal EVENTS, IssueHourlyCount.where(issue:).sum(:count)
    assert_not InboundEvent.exists?(project_id: @project.id)
  end

  private
    def process_concurrently(inbound)
      errors = Queue.new
      threads = inbound.each_slice(EVENTS / THREADS).map do |slice|
        Thread.new { process_all(slice, errors) }
      end
      threads.each(&:join)
      Array.new(errors.size) { errors.pop }
    end

    def process_all(inbound_events, errors)
      ActiveRecord::Base.connection_pool.with_connection do
        inbound_events.each { |inbound_event| Ingest::Processor.new(inbound_event).process }
      end
    rescue StandardError => error
      errors << error
    end
end
