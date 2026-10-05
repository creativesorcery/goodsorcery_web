require "test_helper"

class Ingest::RequestBodyTest < ActiveSupport::TestCase
  def request_for(body, headers = {})
    env = Rack::MockRequest.env_for("/api/v1/events", method: "POST", input: body)
    headers.each { |name, value| env["HTTP_#{name.upcase.tr("-", "_")}"] = value }
    ActionDispatch::Request.new(env)
  end

  def gzip(text) = ActiveSupport::Gzip.compress(text)

  test "reads plain and gzip bodies as UTF-8" do
    assert_equal '{"a":"ü"}', Ingest::RequestBody.new(request_for('{"a":"ü"}')).read
    body = Ingest::RequestBody.new(request_for(gzip('{"a":1}'), "Content-Encoding" => "gzip")).read
    assert_equal '{"a":1}', body
    assert_equal Encoding::UTF_8, body.encoding
  end

  test "rejects bodies over the cap, compressed or decompressed" do
    big = "x" * (Ingest::Limits::BODY_BYTES + 1)
    assert_raises(Ingest::PayloadTooLarge) { Ingest::RequestBody.new(request_for(big)).read }
    bomb = request_for(gzip(big), "Content-Encoding" => "gzip")
    assert_operator bomb.content_length, :<, 10_000
    assert_raises(Ingest::PayloadTooLarge) { Ingest::RequestBody.new(bomb).read }
  end

  test "rejects early on a large Content-Length" do
    request = request_for("{}")
    request.set_header("CONTENT_LENGTH", (Ingest::Limits::BODY_BYTES + 1).to_s)
    assert_raises(Ingest::PayloadTooLarge) { Ingest::RequestBody.new(request).read }
  end

  test "treats corrupt gzip and invalid UTF-8 as invalid json" do
    assert_raises(Ingest::InvalidJson) { Ingest::RequestBody.new(request_for("nope", "Content-Encoding" => "gzip")).read }
    assert_raises(Ingest::InvalidJson) { Ingest::RequestBody.new(request_for("\xFF\xFE")).read }
  end

  test "supports identity and gzip encodings only" do
    assert Ingest::RequestBody.new(request_for("{}")).supported_encoding?
    assert Ingest::RequestBody.new(request_for("{}", "Content-Encoding" => "GZIP")).supported_encoding?
    assert_not Ingest::RequestBody.new(request_for("{}", "Content-Encoding" => "br")).supported_encoding?
  end
end
