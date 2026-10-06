require "test_helper"

class Ingest::EnvelopeTest < ActiveSupport::TestCase
  test "valid with an exception class" do
    envelope = Ingest::Envelope.new({ exception: { class: "RuntimeError" } }.to_json)
    assert envelope.valid?
    assert_empty envelope.errors
  end

  test "reports shape errors without echoing content" do
    { "[1]" => "body must be a JSON object", '{"exception":{"class":""}}' => "exception.class is required",
      '{"exception":"mara@example.com"}' => "exception.class is required",
      '{"exception":{"class":42}}' => "exception.class is required" }.each do |body, error|
      assert_equal [ error ], Ingest::Envelope.new(body).errors, body
    end
  end

  test "raises InvalidJson without the parser message" do
    error = assert_raises(Ingest::InvalidJson) { Ingest::Envelope.new('{"user":"mara@example.com"') }
    assert_equal "invalid json", error.message
  end

  test "uses the client event id when it is a uuid, otherwise generates a v7 uuid" do
    id = "0192F7A4-6C1E-7B3A-9D21-5F0C8E1B0AA1"
    assert_equal id.downcase, Ingest::Envelope.new({ event_id: id, exception: { class: "E" } }.to_json).event_uuid
    generated = Ingest::Envelope.new({ event_id: "nope", exception: { class: "E" } }.to_json).event_uuid
    assert_match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/, generated)
  end

  test "validates an already parsed event, naming it in messages" do
    assert Ingest::Envelope.new(data: { "exception" => { "class" => "E" } }, subject: "event").valid?
    assert_equal [ "event must be a JSON object" ], Ingest::Envelope.new(data: [ 1 ], subject: "event").errors
  end
end
