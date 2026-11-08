require "test_helper"

class Ingest::FingerprintTest < ActiveSupport::TestCase
  setup do
    @frame = Ingest::Frame.new(file: "app/models/order.rb", line: 12, method_name: "total", in_app: true,
                               column: nil, module_name: nil, package: nil, context: {}, locals: {})
  end

  def digest(**options)
    Ingest::Fingerprint.new(exception_class: "NoMethodError", top_app_frame: @frame, redacted_message: "m", **options).digest
  end

  test "groups by class, file and method of the top app frame, ignoring line and message" do
    moved = @frame.with(line: 99)
    assert_equal digest, Ingest::Fingerprint.new(exception_class: "NoMethodError", top_app_frame: moved, redacted_message: "other").digest
    assert_not_equal digest, digest(top_app_frame: @frame.with(method_name: "subtotal"))
    assert_match(/\A\h{64}\z/, digest)
  end

  test "is stable across runs" do
    expected = Digest::SHA256.hexdigest([ "v1", "NoMethodError", "app/models/order.rb", "total" ].join("\x1F"))
    assert_equal expected, digest
  end

  test "falls back to class and redacted message without an app frame" do
    a = Ingest::Fingerprint.new(exception_class: "Timeout::Error", top_app_frame: nil, redacted_message: "took [n]s")
    assert_equal [ "v1", "Timeout::Error", "took [n]s" ], a.parts
  end

  test "a client fingerprint overrides grouping and is bounded" do
    custom = Ingest::Fingerprint.new(exception_class: "X", top_app_frame: @frame, redacted_message: "m",
                                     client_parts: [ "checkout", 42, { "a" => 1 }, "x" * 300 ] + %w[a b c d e f g h i j])
    assert_equal [ "custom", "checkout", "42", "x" * 200, *%w[a b c d e f g] ], custom.parts
    assert_equal digest(client_parts: [ "a" ]), Ingest::Fingerprint.new(exception_class: "Other", top_app_frame: nil,
                                                                        redacted_message: "", client_parts: [ "a" ]).digest
  end

  test "an empty or invalid client fingerprint is ignored" do
    assert_equal digest, digest(client_parts: [])
    assert_equal digest, digest(client_parts: [ {}, [ "nested" ], nil ])
  end
end
