require "test_helper"
require_relative "../models/ingest/ingest_test_support"

class IngestFlowTest < ActionDispatch::IntegrationTest
  include IngestTestSupport
  include ActiveJob::TestHelper

  def post_event(body, token: FIXTURE_TOKENS[:storefront_production])
    post api_v1_events_path, params: body,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    assert_response :accepted
  end

  test "two events with the same fingerprint become one issue with two occurrences" do
    assert_difference -> { Issue.count } => 1, -> { Occurrence.count } => 2 do
      perform_enqueued_jobs(only: ProcessInboundEventJob) do
        post_event event_json
        post_event event_json
      end
    end

    issue = projects(:storefront).issues.order(:id).last
    assert_equal [ 2, 1 ], [ issue.events_count, issue.users_count ]
    assert_equal "GS-1046", issue.short_id
    assert_equal 0, InboundEvent.where(project: projects(:storefront)).where.not(id: inbound_events(:storefront_pending).id).count
  end

  test "retrying with the same event id is idempotent" do
    json = event_json("full", event_id: "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0ee5")
    perform_enqueued_jobs(only: ProcessInboundEventJob) { 2.times { post_event json } }
    assert_equal 1, Occurrence.where(uuid: "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0ee5").sole.issue.events_count
  end

  test "captured data never reaches the log" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    Rails.logger.broadcast_to(logger)
    perform_enqueued_jobs(only: ProcessInboundEventJob) { post_event event_json }
    log = output.string

    assert_includes log, "Api::V1::EventsController#create"
    assert_match(/Parameters: \{controller: "api\/v1\/events", action: "create"\}$/, log)
    # Debug SQL lines may show the redacted issue title (plaintext by design); nothing else.
    [ "mara@example.com", "Mara Lindqvist", "hunter2", "4242424242424242", "sk_live_abc123", "81.2.69.160", "88123" ]
      .each { |text| assert_not_includes log, text }
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end
end

# Real concurrency: separate connections racing to create the same issue.
class IngestRaceTest < ActiveSupport::TestCase
  include IngestTestSupport

  self.use_transactional_tests = false

  setup do
    @project = Project.create!(account: accounts(:umbrella), name: "race-#{SecureRandom.hex(4)}")
    @key = @project.api_keys.first
  end

  teardown { @project.delete }

  test "concurrent processors with the same fingerprint create one issue" do
    4.times do |n|
      json = minimal_json(exception: { class: "RaceError#{n}" })
      ids = Array.new(2) { inbound_event_for(json, key: @key).id }
      ids.map { |id| Thread.new { ActiveRecord::Base.connection_pool.with_connection { process_by_id(id) } } }.each(&:join)
    end

    assert_equal 4, @project.issues.count
    assert_equal [ 2 ] * 4, @project.issues.order(:id).pluck(:events_count)
    assert_equal 8, @project.occurrences.count
    assert_equal 0, @project.inbound_events.count
  end

  private
    def process_by_id(id)
      Ingest::Processor.new(InboundEvent.find(id)).process
    rescue ActiveRecord::Deadlocked
      retry
    end
end
