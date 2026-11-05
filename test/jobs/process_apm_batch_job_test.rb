require "test_helper"
require_relative "../models/apm/apm_test_support"

class ProcessApmBatchJobTest < ActiveJob::TestCase
  include ApmTestSupport

  test "processes the batch by id on the apm queue" do
    id = store_batch(metrics_body)
    assert_equal "apm", ProcessApmBatchJob.new(id).queue_name
    ProcessApmBatchJob.perform_now(id)
    assert ApmInboundBatch.find(id).processed?
  end

  test "a missing or processed batch is a no-op" do
    assert_nothing_raised { ProcessApmBatchJob.perform_now(-1) }
  end

  test "database errors are re-raised without their message" do
    id = store_batch(metrics_body)
    failing = ->(*) { raise ActiveRecord::StatementInvalid, "value mara@example.com violates" }
    Apm::BatchProcessor.class_eval { alias_method :original_process, :process }
    Apm::BatchProcessor.define_method(:process, &failing)
    error = assert_raises(Apm::ProcessingFailed) { ProcessApmBatchJob.perform_now(id) }
    assert_not_includes error.message, "mara"
    assert_includes error.message, id.to_s
  ensure
    Apm::BatchProcessor.class_eval do
      alias_method :process, :original_process
      remove_method :original_process
    end
  end
end
