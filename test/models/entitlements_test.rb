require "test_helper"

class EntitlementsTest < ActiveSupport::TestCase
  HOSTED_DEFAULTS = { uptime_intervals: [ 10, 60 ], max_monitors: 1 }.freeze

  test "the configured hosted defaults are 10 and 60 minute intervals and one monitor" do
    defaults = Rails.configuration.x.entitlements.hosted_defaults

    assert_equal({ uptime_intervals: [ 10, 60 ], max_monitors: 1 }, defaults.to_h.symbolize_keys)
    assert_empty Entitlements.problems(defaults.to_h)
  end

  test "hosted mode is off by default" do
    assert_equal false, Rails.configuration.x.hosted
    assert Entitlements.new({}).unlimited?
    with_hosted_mode { assert_not Entitlements.new({}).unlimited? }
  end

  test "self-hosted is unlimited and ignores stored values" do
    entitlements = self_hosted("uptime_intervals" => [ 60 ], "max_monitors" => 0)

    assert entitlements.unlimited?
    assert_equal [ 1, 5, 10, 60 ], entitlements.uptime_intervals
    assert_empty entitlements.locked_uptime_intervals
    assert_nil entitlements.max_monitors
    assert_nil entitlements.monitors_left(1_000)
    assert_not entitlements.monitor_limit_reached?(1_000)
    assert_equal 10, entitlements.default_uptime_interval
    Entitlements::UPTIME_INTERVALS.each { |minutes| assert entitlements.allows_uptime_interval?(minutes) }
  end

  test "hosted with nothing stored uses the hosted defaults" do
    entitlements = hosted({})

    assert_not entitlements.unlimited?
    assert_equal [ 10, 60 ], entitlements.uptime_intervals
    assert_equal [ 1, 5 ], entitlements.locked_uptime_intervals
    assert_equal 1, entitlements.max_monitors
    assert_not entitlements.allows_uptime_interval?(1)
    assert entitlements.allows_uptime_interval?(60)
  end

  test "hosted stored values win" do
    entitlements = hosted("uptime_intervals" => [ 60, 1, 5 ], "max_monitors" => 25)

    assert_equal [ 1, 5, 60 ], entitlements.uptime_intervals, "sorted"
    assert_equal [ 10 ], entitlements.locked_uptime_intervals
    assert_equal 25, entitlements.max_monitors
  end

  test "hosted falls back per key when a key is missing" do
    only_intervals = hosted("uptime_intervals" => [ 1, 5, 10, 60 ])
    assert_equal [ 1, 5, 10, 60 ], only_intervals.uptime_intervals
    assert_equal 1, only_intervals.max_monitors

    only_limit = hosted("max_monitors" => 10)
    assert_equal [ 10, 60 ], only_limit.uptime_intervals
    assert_equal 10, only_limit.max_monitors
  end

  test "a stored null max_monitors means no cap, unlike a missing key" do
    entitlements = hosted("max_monitors" => nil)

    assert_nil entitlements.max_monitors
    assert_nil entitlements.monitors_left(500)
    assert_not entitlements.monitor_limit_reached?(500)
  end

  test "symbol keys are read like string keys" do
    assert_equal 4, hosted(max_monitors: 4).max_monitors
  end

  test "invalid stored values fall back to the default and are logged by key name only" do
    values = { "uptime_intervals" => [ 2, "secret-ish" ], "max_monitors" => -1 }

    log = capture_log { @entitlements = Entitlements.new(values, hosted: true, hosted_defaults: HOSTED_DEFAULTS, account_id: 42) }
    assert_equal "", log, "nothing is resolved before it is read"

    log = capture_log do
      assert_equal [ 10, 60 ], @entitlements.uptime_intervals
      assert_equal 1, @entitlements.max_monitors
    end
    assert_includes log, "Ignoring invalid entitlement uptime_intervals for account 42"
    assert_includes log, "Ignoring invalid entitlement max_monitors for account 42"
    assert_not_includes log, "secret-ish"
  end

  test "junk stored values never raise" do
    junk = [
      { "uptime_intervals" => "10", "max_monitors" => "5" },
      { "uptime_intervals" => [], "max_monitors" => 1.5 },
      { "uptime_intervals" => [ 10, 10 ], "max_monitors" => true },
      { "uptime_intervals" => { "10" => true }, "max_monitors" => [ 1 ] },
      { "uptime_intervals" => [ nil ], "max_monitors" => {} },
      [ 1, 2 ], "nonsense", nil, 7
    ]

    junk.each do |values|
      entitlements = hosted(values)
      assert_equal [ 10, 60 ], entitlements.uptime_intervals, values.inspect
      assert_equal 1, entitlements.max_monitors, values.inspect
    end
  end

  test "unknown stored keys are ignored" do
    entitlements = hosted("seats" => 99, "max_monitors" => 2)

    assert_equal 2, entitlements.max_monitors
    assert_equal [ 10, 60 ], entitlements.uptime_intervals
  end

  test "a hosted default missing from the configuration is unlimited" do
    entitlements = Entitlements.new({}, hosted: true, hosted_defaults: { uptime_intervals: [ 60 ] })

    assert_equal [ 60 ], entitlements.uptime_intervals
    assert_nil entitlements.max_monitors
  end

  test "the arguments default to the application configuration" do
    with_hosted_mode do
      entitlements = Entitlements.new({})
      assert_equal [ 10, 60 ], entitlements.uptime_intervals
      assert_equal 1, entitlements.max_monitors
    end
  end

  test "default_uptime_interval prefers 10, then the next longer, then the longest" do
    assert_equal 10, hosted("uptime_intervals" => [ 1, 10, 60 ]).default_uptime_interval
    assert_equal 60, hosted("uptime_intervals" => [ 1, 60 ]).default_uptime_interval
    assert_equal 60, hosted("uptime_intervals" => [ 60 ]).default_uptime_interval
    assert_equal 5, hosted("uptime_intervals" => [ 1, 5 ]).default_uptime_interval
    assert_equal 1, hosted("uptime_intervals" => [ 1 ]).default_uptime_interval
  end

  test "nearest_uptime_interval takes the smallest allowed at least as long, else the longest" do
    entitlements = hosted("uptime_intervals" => [ 5, 10 ])

    assert_equal 5, entitlements.nearest_uptime_interval(1)
    assert_equal 5, entitlements.nearest_uptime_interval(5)
    assert_equal 10, entitlements.nearest_uptime_interval(6)
    assert_equal 10, entitlements.nearest_uptime_interval(60)
    assert_equal 10, hosted({}).nearest_uptime_interval(1)
    assert_equal 60, self_hosted({}).nearest_uptime_interval(60)
  end

  test "monitor limit and monitors left" do
    entitlements = hosted("max_monitors" => 3)

    assert_not entitlements.monitor_limit_reached?(2)
    assert entitlements.monitor_limit_reached?(3)
    assert entitlements.monitor_limit_reached?(4), "over the limit after a downgrade"
    assert_equal 1, entitlements.monitors_left(2)
    assert_equal 0, entitlements.monitors_left(5)
  end

  test "a limit of zero allows no monitors" do
    entitlements = hosted("max_monitors" => 0)

    assert entitlements.monitor_limit_reached?(0)
    assert_equal 0, entitlements.monitors_left(0)
  end

  test "uptime_intervals can't be mutated through the reader" do
    entitlements = hosted({})

    assert_raises(FrozenError) { entitlements.uptime_intervals << 1 }
    assert_raises(FrozenError) { self_hosted({}).uptime_intervals << 2 }
  end

  test "problems accepts valid documents" do
    assert_empty Entitlements.problems({})
    assert_empty Entitlements.problems("uptime_intervals" => [ 1, 5, 10, 60 ], "max_monitors" => nil)
    assert_empty Entitlements.problems(uptime_intervals: [ 60 ], max_monitors: 0)
    assert_empty Entitlements.problems("seats" => "unknown keys are not checked")
  end

  test "problems describes each invalid key in a whole sentence" do
    assert_equal [ Entitlements::PROBLEMS["uptime_intervals"] ], Entitlements.problems("uptime_intervals" => [ 2 ])
    assert_equal [ Entitlements::PROBLEMS["max_monitors"] ], Entitlements.problems("max_monitors" => "5")
    assert_equal 2, Entitlements.problems("uptime_intervals" => [], "max_monitors" => -3).size
    assert_equal [ "Entitlements must be an object of values." ], Entitlements.problems([ 1 ])
    assert_match(/\A[A-Z].*\.\z/, Entitlements::PROBLEMS["uptime_intervals"])
  end

  test "problems rejects duplicate, empty and non-integer intervals" do
    [ [], [ 10, 10 ], [ "10" ], [ 10.0 ], [ 3 ], "10", nil ].each do |intervals|
      assert_not_empty Entitlements.problems("uptime_intervals" => intervals), intervals.inspect
    end
  end

  # "free text" is fine; "free" as a plan name (a string, a symbol, "free plan") isn't.
  TIER_WORDS = /\bpremium\b|["':]free\b|\bfree[ _-](plan|tier)s?\b/i

  test "no tier names appear in app, config or lib code" do
    files = Dir[Rails.root.join("{app,config,lib}/**/*.{rb,erb,yml}")]
    offenders = files.select { |path| File.read(path).match?(TIER_WORDS) }

    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end

  private
    def hosted(values)
      Entitlements.new(values, hosted: true, hosted_defaults: HOSTED_DEFAULTS)
    end

    def self_hosted(values)
      Entitlements.new(values, hosted: false, hosted_defaults: HOSTED_DEFAULTS)
    end

    def capture_log
      output = StringIO.new
      previous = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(output)
      yield
      output.string
    ensure
      Rails.logger = previous
    end
end
