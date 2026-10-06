require "test_helper"

class Ingest::BatchTest < ActiveSupport::TestCase
  def batch(events) = Ingest::Batch.new({ events: }.to_json)

  test "valid with 1 to 100 events" do
    assert batch([ { exception: { class: "E" } } ]).valid?
    assert_equal 100, batch(Array.new(100) { { exception: { class: "E" } } }).size
  end

  test "reports shape errors without echoing content" do
    { "[]" => "body must be a JSON object", '{"evts":[]}' => "events must be an array",
      '{"events":"mara@example.com"}' => "events must be an array", '{"events":[]}' => "events must not be empty",
      { events: Array.new(101) { {} } }.to_json => "events must hold at most 100 events" }.each do |body, error|
      assert_equal [ error ], Ingest::Batch.new(body).errors, body
    end
  end

  test "raises InvalidJson without the parser message" do
    error = assert_raises(Ingest::InvalidJson) { Ingest::Batch.new('{"events":[{"user":"mara@example.com"}') }
    assert_equal "invalid json", error.message
  end

  test "splits events into accepted and rejected items by index" do
    id = "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1"
    result = batch([ { event_id: id, exception: { class: "E" } }, { exception: { message: "mara@example.com" } }, 42 ])

    assert_equal [ { index: 0, id: } ], result.accepted_items.map(&:acceptance)
    assert_equal [ { index: 1, error: "invalid_payload", messages: [ "exception.class is required" ] },
                   { index: 2, error: "invalid_payload", messages: [ "event must be a JSON object" ] } ],
                 result.rejected_items.map(&:rejection)
  end

  test "an item is stored as its own re-serialised JSON" do
    item = batch([ { exception: { class: "E" }, user: { email: "mara@example.com" } } ]).items.sole
    assert_equal({ "exception" => { "class" => "E" }, "user" => { "email" => "mara@example.com" } }, JSON.parse(item.body))
    assert_match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/, item.event_uuid)
  end

  test "an item that re-serialises over the single event limit is rejected as too large" do
    item = batch([ { exception: { class: "E", message: "x" * Ingest::Limits::BODY_BYTES } } ]).items.sole
    assert_equal({ index: 0, error: "payload_too_large" }, item.rejection)
  end
end
