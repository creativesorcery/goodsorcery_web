require "test_helper"
require_relative "ingest_test_support"

class Ingest::EventTest < ActiveSupport::TestCase
  include IngestTestSupport

  setup { @event = build_event }

  test "reads the summary fields" do
    assert_equal "NoMethodError", @event.exception_class
    assert_equal "CheckoutsController#create", @event.transaction_name
    assert_equal "error", @event.level
    assert_equal "a1b2c3d", @event.release
    assert_equal "app/services/cart_total.rb:42 in line_total", @event.culprit
    assert_equal "Rails 8.0 · Ruby 3.4", @event.runtime_label
    assert_equal "production", @event.environment
  end

  test "scrubs the message and redacts the title" do
    assert_includes @event.message, "mara@example.com"
    assert_includes @event.message, "card [FILTERED]"
    assert_equal "undefined method `price_cents' for nil (cart [n], [email], card [FILTERED])", @event.redacted_message
  end

  test "normalises frames, infers in_app and gem names" do
    file, *others = @event.frames.map(&:file)
    assert_equal "app/services/cart_total.rb", file
    assert_equal [ "app/models/order.rb", "gems/activerecord-8.0.1/lib/active_record/relation.rb", "ruby/3.4.0/monitor.rb" ], others
    assert_equal [ true, true, false, false ], @event.frames.map(&:in_app?)
    assert_equal [ nil, nil, "activerecord", nil ], @event.frames.map(&:gem_name)
    assert_equal "[FILTERED]", @event.frames.first.locals["api_key"]
    assert_equal 39, @event.frames.first.context[:start_line]
  end

  test "scrubs nested keys of hash locals before turning them into text" do
    json = minimal_json(exception: { backtrace: [ { file: "app/x.rb", line: 1, method: "a",
      locals: { params: { password: "hunter2", user: { token: "abc", name: "Mara" } }, list: [ 1, 2 ] } } ] })
    locals = build_event(json).frames.first.locals

    assert_equal({ "password" => "[FILTERED]", "user" => { "token" => "[FILTERED]", "name" => "Mara" } }, JSON.parse(locals["params"]))
    assert_equal "[1,2]", locals["list"]
    assert_no_match(/hunter2|abc/, locals.values.join)
  end

  test "client in_app flags win over inference" do
    json = minimal_json(exception: { backtrace: [ { file: "app/x.rb", line: 1, method: "a", in_app: false },
                                                  { file: "vendor/thing.rb", line: "7", method: "b", in_app: true } ] })
    event = build_event(json)
    assert_equal [ false, true ], event.frames.map(&:in_app?)
    assert_equal "vendor/thing.rb:7 in b", event.culprit
    assert_equal 7, event.top_app_frame.line
  end

  test "culprit falls back to the first frame, then nil" do
    json = minimal_json(exception: { backtrace: [ { file: "gems/rack-3.1/lib/rack.rb", line: 3, method: "call" } ] })
    assert_equal "gems/rack-3.1/lib/rack.rb:3 in call", build_event(json).culprit
    assert_nil build_event(minimal_json).culprit
  end

  test "clamps occurred_at to the accepted window" do
    received_at = Time.utc(2026, 10, 4, 9)
    within = build_event(minimal_json(occurred_at: "2026-10-04T08:59:00Z"), received_at:)
    assert_equal Time.utc(2026, 10, 4, 8, 59), within.occurred_at
    [ "2026-08-01T00:00:00Z", "2026-10-04T09:06:00Z", "yesterday", 12 ].each do |value|
      assert_equal received_at, build_event(minimal_json(occurred_at: value), received_at:).occurred_at, value.to_s
    end
  end

  test "unknown levels become error" do
    assert_equal "warning", build_event(minimal_json(level: "warning")).level
    assert_equal "error", build_event(minimal_json(level: "catastrophic")).level
  end

  test "tags merge server tags; the key environment always wins" do
    assert_equal({ "release" => "a1b2c3d", "host" => "web-7f9c-2", "browser" => "Mobile Safari", "coupon" => "FALL25",
                   "environment" => "production", "build" => "42" }, @event.tags)
    client_host = build_event(minimal_json(context: { host: "web-1" }, tags: { host: "custom" }))
    assert_equal "custom", client_host.tags["host"]
  end

  test "tags are bounded and scrubbed" do
    many = (1..40).to_h { |n| [ "k#{n}", "v" * 300 ] }.merge("auth_token" => "abc")
    tags = build_event(minimal_json(tags: many)).tags
    assert_equal 26, tags.size
    assert tags.values.all? { |value| value.length <= 200 }
    assert_equal({ "auth_token" => "[FILTERED]" }, build_event(minimal_json(tags: { auth_token: "abc" })).tags.except("environment"))
  end

  test "keeps only user identity fields and digests them" do
    assert_equal({ "id" => "5521", "email" => "Mara@Example.com", "username" => "mara", "name" => "Mara Lindqvist" }, @event.user)
    assert_equal PrivateDigest.hexdigest("user.id", "5521"), @event.user_identity.primary_digest
    assert_includes @event.user_identity.digests, PrivateDigest.hexdigest("user.email", "mara@example.com")
  end

  test "bounds free-form trees" do
    deep = { a: { b: { c: { d: { e: { f: { g: "too deep" } } } } } } }
    json = minimal_json(request: { params: deep.merge(list: (1..80).to_a, long: "x" * 5_000) }, context: { blob: "y" * 9_000 })
    event = build_event(json)
    params = event.request.params
    assert_equal "[truncated]", params.dig("a", "b", "c", "d", "e", "f")
    assert_equal 50, params["list"].size
    assert_equal 4_096, params["long"].length
    assert_equal 4_096, event.context["blob"].length
  end

  test "bounds frames, breadcrumbs and messages" do
    json = minimal_json(exception: { message: "m" * 20_000, backtrace: Array.new(300) { { file: "app/a.rb", line: 1 } } },
                        breadcrumbs: Array.new(150) { |n| { message: "crumb #{n}", data: (1..30).to_h { [ "k#{it}", it ] } } })
    event = build_event(json)
    assert_equal 10_000, event.message.length
    assert_equal 250, event.frames.size
    crumbs = event.breadcrumbs
    assert_equal 100, crumbs.size
    assert_equal "crumb 50", crumbs.first.message
    assert_equal 20, crumbs.first.data.size
  end

  test "normalises breadcrumbs with offsets relative to occurred_at" do
    crumbs = @event.breadcrumbs
    assert_equal %w[request sql custom], crumbs.map(&:category)
    assert_equal %w[info debug info], crumbs.map(&:level)
    assert crumbs.all? { |crumb| crumb.offset_ms.between?(-11_000, -9_000) }
    assert_equal "[FILTERED]", crumbs.second.data["password"]
    assert_includes crumbs.third.message, "api_key=[FILTERED]"
  end

  test "builds the stored payload shape without unscrubbed secrets" do
    payload = JSON.parse(@event.to_payload_json)
    assert_equal %w[exception transaction request params headers session user breadcrumbs context tags notifier], payload.keys
    assert_equal %w[url method format request_id remote_ip], payload["request"].keys
    assert_equal "[FILTERED]", payload.dig("params", "password")
    assert_equal "[FILTERED]", payload.dig("headers", "Authorization")
    assert_equal "[FILTERED]", payload.dig("headers", "Cookie")
    assert_equal "[FILTERED]", payload.dig("params", "loyalty_number"), "project scrub_fields apply"
    %w[hunter2 4242424242424242 deadbeef sk_live_abc123 s3cret].each { |secret| assert_not_includes @event.to_payload_json, secret }
  end

  test "rejects bodies without an exception class" do
    [ "[]", "nope", { exception: { class: " " } }.to_json, { exception: "x" }.to_json ].each do |json|
      assert_raises(Ingest::MalformedPayload) { build_event(json) }
    end
  end
end
