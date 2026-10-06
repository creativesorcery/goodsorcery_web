require "test_helper"
require_relative "ingest_test_support"

class Ingest::JobSectionTest < ActiveSupport::TestCase
  include IngestTestSupport

  def section(**job)
    Ingest::JobSection.new(job.deep_stringify_keys, scrubber: Ingest::Scrubber.new).to_h
  end

  test "keeps the known fields as strings and drops unknown keys" do
    job = build_event(event_json("job")).job

    assert_equal %w[framework class id provider_job_id queue priority executions enqueued_at scheduled_at arguments], job.keys
    assert_equal "ChargeCustomerJob", job["class"]
    assert_equal "10", job["priority"]
    assert_equal "3", job["executions"]
    assert_equal "2026-10-04T09:15:00.000Z", job["scheduled_at"]
  end

  test "keeps mailer, action and sidekiq retry_count" do
    mailer = section(framework: "active_job", class: "ActionMailer::MailDeliveryJob", mailer: "UserMailer", action: "welcome",
                     arguments: { params: { user: "gid://shop/User/5521" }, args: [] })
    sidekiq = section(framework: "sidekiq", class: "LegacyWorker", id: "b4c3d2", retry_count: 2, arguments: [ 1, "two" ])

    assert_equal [ "UserMailer", "welcome" ], mailer.values_at("mailer", "action")
    assert_equal({ "params" => { "user" => "gid://shop/User/5521" }, "args" => [] }, mailer["arguments"])
    assert_equal [ "2", [ 1, "two" ] ], sidekiq.values_at("retry_count", "arguments")
  end

  test "scrubs arguments by key, by project scrub fields and in bare strings" do
    arguments = build_event(event_json("job")).job["arguments"]

    assert_equal "gid://shop/Customer/88123", arguments[0]
    assert_equal({ "amount_cents" => 4200, "card_token" => "[FILTERED]", "loyalty_number" => "[FILTERED]",
                   "note" => "Bearer [FILTERED]" }, arguments[1])
    assert_equal "[FILTERED]", arguments[2]
  end

  test "bounds arguments like request params and scalar fields to 255 chars" do
    deep = { a: { b: { c: { d: { e: { f: "too deep" } } } } } }
    job = section(class: "C" * 400, queue: "q\u0000ueue", arguments: [ deep, *(1..80) ].push("x" * 5_000))

    assert_equal 255, job["class"].length
    assert_equal "queue", job["queue"]
    assert_equal 50, job["arguments"].size
    assert_equal "[truncated]", job["arguments"][0].dig("a", "b", "c", "d", "e")
    long = section(arguments: [ "x" * 5_000 ])["arguments"].sole
    assert_equal 4_096, long.length
  end

  test "drops non-scalar fields, non-collection arguments and empty sections" do
    assert_equal({}, section(class: { name: "x" }, queue: [ "a" ], priority: nil, arguments: "secret"))
    assert_equal({ "queue" => "default" }, section(queue: "default", arguments: []))
    assert_equal({}, build_event(minimal_json).job)
    assert_equal({}, build_event(minimal_json(job: "nope")).job)
  end

  test "scrubs secrets out of the summary fields" do
    assert_equal "Bearer [FILTERED]", section(id: "Bearer abc123")["id"]
  end
end
