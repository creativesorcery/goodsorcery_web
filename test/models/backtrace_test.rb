require "test_helper"

class BacktraceTest < ActiveSupport::TestCase
  def frame(file, line, method_name, in_app:, **extra)
    { "file" => file, "line" => line, "method" => method_name, "in_app" => in_app }.merge(extra.stringify_keys)
  end

  def app(file, line = 1, method_name = "run", **extra) = frame(file, line, method_name, in_app: true, **extra)

  def gem(file, line = 1, method_name = "call") = frame(file, line, method_name, in_app: false)

  test "keeps app frames alone and folds consecutive framework frames" do
    backtrace = Backtrace.new([
      app("app/a.rb"), gem("gems/activesupport-8.0.1/lib/x.rb"), gem("gems/activerecord-8.0.1/lib/y.rb"),
      app("app/b.rb"), app("app/c.rb"), gem("gems/rack-3.1.0/lib/z.rb")
    ], exception_class: "RuntimeError")

    kinds = backtrace.segments.map { |segment| [ segment.app? ? :app : :framework, segment.size ] }

    assert_equal [ [ :app, 1 ], [ :framework, 2 ], [ :app, 1 ], [ :app, 1 ], [ :framework, 1 ] ], kinds
    assert_equal %w[activesupport activerecord], backtrace.segments.second.package_names
    assert_equal 3, backtrace.framework_frame_count
  end

  test "expands only the first app frame, even when framework frames come first" do
    backtrace = Backtrace.new([ gem("gems/rack-3.1.0/lib/z.rb"), app("app/a.rb"), app("app/b.rb") ], exception_class: "E")

    assert_equal [ false, true, false ], backtrace.segments.map(&:expanded?)
    assert_equal "app/a.rb", backtrace.top_app_frame.file
  end

  test "a backtrace with no app frames expands nothing" do
    backtrace = Backtrace.new([ gem("gems/rack-3.1.0/lib/z.rb") ], exception_class: "E")

    assert_not backtrace.app_frames?
    assert_not backtrace.segments.any?(&:expanded?)
  end

  test "an empty or missing backtrace has no segments" do
    assert Backtrace.new(nil, exception_class: "E").empty?
    assert_empty Backtrace.new([], exception_class: "E").segments
  end

  test "code lines keep ±3 around the error line and mark it" do
    lines = (1..11).map { |n| "line #{n}" }
    backtrace = Backtrace.new([ app("app/a.rb", 46, "go", context: { "start_line" => 41, "lines" => lines }) ], exception_class: "E")

    code = backtrace.top_app_frame.code_lines

    assert_equal (43..49).to_a, code.map(&:first)
    assert_equal [ 46, "line 6", true ], code.find(&:last)
    assert_equal 1, code.count(&:last)
  end

  test "locals and context are optional" do
    frame = Backtrace.new([ app("app/a.rb") ], exception_class: "E").top_app_frame

    assert_not frame.code?
    assert_not frame.locals?
  end

  test "reads package names from the payload, the older gem key or the path" do
    backtrace = Backtrace.new([
      frame("src/runtime/task.rs", 1, "poll", in_app: false, package: "tokio"),
      frame("gems/actionpack-8.0.1/lib/a.rb", 1, "x", in_app: false, gem: "actionpack"),
      gem("/usr/local/bundle/gems/puma-6.4.0/lib/puma/server.rb"),
      gem("crates/hyper-1.5.0/src/server.rs"),
      gem("/usr/lib/ruby/3.4.0/monitor.rb")
    ], exception_class: "E")

    assert_equal [ "tokio", "actionpack", "puma", "hyper", nil ], backtrace.frames.map(&:package)
  end

  test "package summary truncates long lists" do
    frames = %w[actionpack rack puma activesupport].map { |name| gem("gems/#{name}-1.0.0/lib/x.rb") }

    assert_equal "actionpack, rack, puma…", Backtrace.new(frames, exception_class: "E").segments.first.package_summary
  end

  test "raw text starts with the class and the full message" do
    backtrace = Backtrace.new([ app("app/a.rb", 4, "go"), gem("gems/rack-3.1.0/lib/z.rb", 9, "call") ],
      exception_class: "NoMethodError", message: "undefined method `x' for nil")

    assert_equal "NoMethodError: undefined method `x' for nil\n  app/a.rb:4 in go\n  gems/rack-3.1.0/lib/z.rb:9 in call", backtrace.raw
  end

  test "columns and modules show when sent" do
    backtrace = Backtrace.new([ app("src/cart.rs", 42, "total", column: 17, module: "shop::cart"),
                                app("src/main.rs", 9, "shop::main", module: "shop"), app("src/lib.rs", nil, "x", column: 3) ],
      exception_class: "shop::Error", message: "no variant")
    cart, main, lib = backtrace.frames

    assert_equal [ "src/cart.rs:42:17", "shop::cart" ], [ cart.location, cart.module_label ]
    assert_equal [ "src/main.rs:9", nil ], [ main.location, main.module_label ]
    assert_equal "src/lib.rs", lib.location
    assert_equal "shop::Error: no variant\n  src/cart.rs:42:17 in shop::cart total\n  src/main.rs:9 in shop::main\n  src/lib.rs in x",
      backtrace.raw
  end

  test "reads the fixture payload" do
    occurrence = occurrences(:nomethod_latest)
    backtrace = Backtrace.new(occurrence.frames, exception_class: "NoMethodError", message: occurrence.exception_message)

    top = backtrace.top_app_frame
    assert_equal "app/services/cart_total.rb:42", top.location
    assert_equal "[FILTERED]", top.locals["card_token"]
    assert_equal %i[app app framework app framework], backtrace.segments.map { |segment| segment.app? ? :app : :framework }
  end
end
