require "test_helper"

class Apm::TraceLookupTest < ActiveSupport::TestCase
  setup { @project = projects(:storefront) }

  def lookup(id, values: {}, hosted: false, self_hosted_days: 30, now: Time.current, project: @project)
    entitlements = Entitlements.new(values, hosted:, hosted_defaults: { apm_retention_days: 1 },
                                            self_hosted_apm_retention_days: self_hosted_days)
    Apm::TraceLookup.new(project, id, entitlements:, now:)
  end

  test "finds a trace of the project by uuid, case-insensitively" do
    trace = apm_traces(:checkout_slow)
    assert_equal trace, lookup(trace.uuid.upcase).trace
    assert lookup(trace.uuid).found?
  end

  test "another project's trace is never found through this project" do
    assert_nil lookup(apm_traces(:umbrella_trace).uuid).trace
    assert lookup(apm_traces(:umbrella_trace).uuid, project: projects(:umbrella_app)).found?
  end

  test "a valid v7 id within the retention that is gone was trimmed" do
    result = lookup(Apm::TraceId.generate(3.hours.ago))
    assert result.expired?
    assert_equal :trimmed, result.reason
  end

  test "past the retention: :retention self-hosted, :plan hosted within 30 days, :retention beyond" do
    old = Apm::TraceId.generate(3.days.ago)
    assert_equal :retention, lookup(old, self_hosted_days: 2).reason
    assert_equal :plan, lookup(old, hosted: true).reason
    assert_equal :retention, lookup(Apm::TraceId.generate(40.days.ago), hosted: true).reason
  end

  test "a stored trace past the account's retention is expired at query time (a downgrade)" do
    trace = apm_traces(:checkout_old_hour)
    result = lookup(trace.uuid, hosted: true, now: trace.minute + 2.days)
    assert_nil result.trace
    assert result.expired?
    assert_equal :plan, result.reason
  end

  test "unknown: not a uuid, not v7, from the future or before the app existed" do
    [ "nope", SecureRandom.uuid, Apm::TraceId.generate(1.hour.from_now), Apm::TraceId.generate(400.days.ago), nil ].each do |id|
      result = lookup(id)
      assert_not result.found?, id.inspect
      assert_not result.expired?, id.inspect
    end
  end
end
