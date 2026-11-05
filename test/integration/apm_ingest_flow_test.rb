require "test_helper"
require_relative "../models/apm/apm_test_support"

# The whole performance path: both endpoints, the job, the merged rows and
# the stored trace, and where captured trace data must never appear.
class ApmIngestFlowTest < ActionDispatch::IntegrationTest
  include ApmTestSupport
  include ActiveJob::TestHelper

  SECRET = "apm-fixture-secret".freeze

  setup do
    @headers = { "Content-Type" => "application/json", "Authorization" => "Bearer #{FIXTURE_TOKENS[:marketing_production]}" }
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @log = StringIO.new
    @loggers = [ Rails.logger, ActiveRecord::Base.logger ]
    Rails.logger = ActiveRecord::Base.logger = ActiveSupport::Logger.new(@log).tap { it.level = :debug }
  end

  teardown do
    Rails.cache = @original_cache
    Rails.logger, ActiveRecord::Base.logger = @loggers
  end

  def secret_trace
    spans = sample_spans
    spans[1] = spans[1].deep_merge(sql: "SELECT \"#{SECRET}\" FROM \"products\"", call_site: { context: { lines: [ "# #{SECRET}" ] } })
    trace_hash(name: "PagesController#home", spans:, request: { method: "GET", path: "/#{SECRET}?q=1", request_id: "r-1" })
  end

  test "metrics and traces flow into merged rows and an encrypted trace" do
    post api_v1_apm_metrics_path, params: ActiveSupport::Gzip.compress(metrics_body([ metrics_transaction(name: "PagesController#home") ])),
         headers: @headers.merge("Content-Encoding" => "gzip")
    assert_response :accepted
    post api_v1_apm_traces_path, params: traces_body([ secret_trace ]), headers: @headers
    assert_response :accepted

    job_args = enqueued_jobs.map { it[:args] }.to_json
    perform_enqueued_jobs

    project = projects(:marketing)
    home = project.apm_transactions.find_by!(name: "PagesController#home")
    stats = Apm::StatsQuery.new(Apm::Range.new("1h"))
    assert_equal 3, stats.by_transaction([ home.id ])[home.id].count
    total = ApmTransaction.total_for(project, "production", "web")
    assert_equal 3, stats.by_transaction([ total.id ])[total.id].count
    trace = project.apm_traces.sole
    assert_equal "/#{SECRET}", trace.details.request["path"]
    assert ApmInboundBatch.where(project:).all?(&:processed?)

    assert_not_includes job_args, SECRET
    assert_not_includes @log.string, SECRET
    assert_not_includes Marshal.dump(Rails.cache.instance_variable_get(:@data)), SECRET
    assert_not_includes trace.payload_before_type_cast.to_s, SECRET
  end
end
