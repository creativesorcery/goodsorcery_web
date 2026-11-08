require "test_helper"

class TrimApmTracesJobTest < ActiveJob::TestCase
  include ApmFixtureClock

  test "trims closed hours to the 3 slowest traces per transaction" do
    transaction = apm_transactions(:products_show)
    hour = TimeSeries.align(Time.current, 1.hour) - 1.hour
    ApmTrace.insert_all(Array.new(5) do |index|
      minute = hour + index.minutes
      { project_id: transaction.project_id, apm_transaction_id: transaction.id, uuid: Apm::TraceId.generate(minute), minute:,
        hour:, started_at: minute, duration_ms: index, payload: "{}", created_at: minute }
    end)

    TrimApmTracesJob.perform_now

    assert_equal [ 4.0, 3.0, 2.0 ], ApmTrace.where(apm_transaction: transaction).order(duration_ms: :desc).pluck(:duration_ms)
    assert_equal "default", TrimApmTracesJob.new.queue_name
  end
end
