require "test_helper"

class Apm::TraceTrimTest < ActiveSupport::TestCase
  setup do
    @transaction = apm_transactions(:products_show)
    @now = Time.current
    @open_hour = TimeSeries.align(@now, 1.hour)
  end

  def add_traces(hour, durations)
    rows = durations.each_with_index.map do |duration, index|
      minute = hour + index.minutes
      { project_id: @transaction.project_id, apm_transaction_id: @transaction.id, uuid: Apm::TraceId.generate(minute),
        minute:, hour:, started_at: minute, duration_ms: duration, payload: "{}", created_at: @now }
    end
    ApmTrace.insert_all(rows)
  end

  def durations(hour) = ApmTrace.where(apm_transaction: @transaction, hour:).order(duration_ms: :desc).pluck(:duration_ms)

  test "keeps the 3 slowest per transaction for each closed hour and never touches the open hour" do
    closed, older, too_old = @open_hour - 1.hour, @open_hour - 3.hours, @open_hour - 4.hours
    add_traces(closed, [ 10, 50, 20, 40, 30 ])
    add_traces(older, [ 5, 6, 7, 8 ])
    add_traces(too_old, [ 1, 2, 3, 4 ])
    add_traces(@open_hour, [ 1, 2, 3, 4, 5 ])

    assert_equal 3, Apm::TraceTrim.new(now: @now).trim

    assert_equal [ 50.0, 40.0, 30.0 ], durations(closed)
    assert_equal [ 8.0, 7.0, 6.0 ], durations(older)
    assert_equal 4, durations(too_old).size, "outside the look-back"
    assert_equal 5, durations(@open_hour).size
    assert_equal 0, Apm::TraceTrim.new(now: @now).trim
  end

  test "other transactions in the same hour are trimmed separately" do
    closed = @open_hour - 1.hour
    add_traces(closed, [ 1, 2, 3 ])
    @transaction = apm_transactions(:place_order_job)
    add_traces(closed, [ 4, 5, 6, 7 ])
    Apm::TraceTrim.new(now: @now).trim
    assert_equal 3, ApmTrace.where(apm_transaction: apm_transactions(:products_show), hour: closed).count
    assert_equal [ 7.0, 6.0, 5.0 ], durations(closed)
  end
end
