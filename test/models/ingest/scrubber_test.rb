require "test_helper"

class Ingest::ScrubberTest < ActiveSupport::TestCase
  setup { @scrubber = Ingest::Scrubber.new(extra_keys: [ "Loyalty" ]) }

  test "filters values under sensitive keys, case-insensitively and deeply" do
    input = { "password" => "hunter2", "Authorization" => "Basic xyz", "Cookie" => "a=b", "X-CSRF-Token" => "t",
              "credit_card" => "4111", "card-number" => "4111", "cvv" => "123", "card_cvc" => "123", "user_ssn" => "1",
              "otp_code" => "9", "session_id" => "s", "api_key" => "k", "accessKey" => "k", "private-key" => "k",
              "client_secret" => "s", "nested" => [ { "token" => "t", "keep" => "me" } ] }
    scrubbed = @scrubber.scrub(input)

    (input.keys - [ "nested" ]).each { |key| assert_equal "[FILTERED]", scrubbed[key], key }
    assert_equal [ { "token" => "[FILTERED]", "keep" => "me" } ], scrubbed["nested"]
  end

  test "does not filter look-alike keys" do
    scrubbed = @scrubber.scrub({ "lessness" => "a", "footprint" => "b", "cart_id" => 88123, "coupon" => "FALL25" })
    assert_equal({ "lessness" => "a", "footprint" => "b", "cart_id" => 88123, "coupon" => "FALL25" }, scrubbed)
  end

  test "filters project extra keys as case-insensitive substrings" do
    assert_equal "[FILTERED]", @scrubber.scrub({ "user_LOYALTY_number" => "LOY-1" })["user_LOYALTY_number"]
  end

  test "filters a whole subtree under a sensitive key" do
    assert_equal({ "secrets" => "[FILTERED]" }, @scrubber.scrub({ "secrets" => { "a" => 1 } }))
  end

  test "replaces Luhn-valid card numbers inside strings but keeps other digit runs" do
    assert_equal "card [FILTERED] ok", @scrubber.scrub_text("card 4111 1111 1111 1111 ok")
    assert_equal "card [FILTERED]", @scrubber.scrub_text("card 4242-4242-4242-4242")
    assert_equal "order 1234567890123 ok", @scrubber.scrub_text("order 1234567890123 ok")
    assert_equal "cart 88123", @scrubber.scrub_text("cart 88123")
  end

  test "keeps UUIDs whole even when a digit run inside one passes the Luhn check" do
    # "19-9060-9196127" is 13 digits that pass Luhn; it used to be cut out of job and request ids.
    uuid = "25dfdfbd-5a0d-4e19-9060-9196127d06a5"
    assert_equal "job #{uuid} failed", @scrubber.scrub_text("job #{uuid} failed")
    assert_equal({ "id" => uuid }, @scrubber.scrub({ "id" => uuid }))
    assert_equal "#{uuid} card [FILTERED]", @scrubber.scrub_text("#{uuid} card 4242-4242-4242-4242")
  end

  test "replaces bearer and basic credentials and JWTs" do
    assert_equal "header Bearer [FILTERED]", @scrubber.scrub_text("header Bearer abc.def-123")
    assert_equal "Authorization: [FILTERED]", @scrubber.scrub_text("Authorization: Bearer abc.def-123")
    assert_equal "basic [FILTERED] end", @scrubber.scrub_text("basic dXNlcjpwYXNz end")
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI1NTIxIn0.c2lnbmF0dXJl"
    assert_equal "jwt=[FILTERED]", @scrubber.scrub_text("jwt=#{jwt}")
  end

  test "filters sensitive URL query parameters and URL passwords" do
    assert_equal "https://x.dev/a?page=2&token=[FILTERED]&api_key=[FILTERED]#top",
                 @scrubber.scrub_text("https://x.dev/a?page=2&token=abc&api_key=k1#top")
    assert_equal "https://x.dev/?loyalty_id=[FILTERED]", @scrubber.scrub_text("https://x.dev/?loyalty_id=7")
    assert_equal "postgres://shop:[FILTERED]@db:5432/shop", @scrubber.scrub_text("postgres://shop:s3cret@db:5432/shop")
  end

  test "replaces Token, Digest and ApiKey credentials but keeps the word token" do
    assert_equal "Authorization: [FILTERED]", @scrubber.scrub_text("Authorization: Token abc123")
    assert_equal "sent Token [FILTERED] and ApiKey [FILTERED]", @scrubber.scrub_text("sent Token abc123 and ApiKey k-x")
    assert_equal "Token expired at noon", @scrubber.scrub_text("Token expired at noon")
  end

  test "filters URL passwords with an empty username" do
    assert_equal "redis://:[FILTERED]@redis:6379/0", @scrubber.scrub_text("redis://:hunter2@redis:6379/0")
  end

  test "filters sensitive keys written as free text" do
    assert_equal "login failed password=[FILTERED] api_key: [FILTERED]",
                 @scrubber.scrub_text("login failed password=hunter2 api_key: sk_live_123")
    assert_equal "Cookie: [FILTERED]; remember_token=[FILTERED]", @scrubber.scrub_text("Cookie: _session=abc; remember_token=xyz")
    assert_equal 'Parameters: {"user"=>{"password"=>"[FILTERED]", "name"=>"Mara"}}',
                 @scrubber.scrub_text('Parameters: {"user"=>{"password"=>"hunter2", "name"=>"Mara"}}')
    assert_equal '{"secret": "[FILTERED]", "page": 2}', @scrubber.scrub_text('{"secret": "s3", "page": 2}')
    assert_equal '#<User email: "m@x.io", password_digest: "[FILTERED]">',
                 @scrubber.scrub_text('#<User email: "m@x.io", password_digest: "$2a$12$abc">')
    assert_equal "loyalty_no=[FILTERED]", @scrubber.scrub_text("loyalty_no=LOY-1"), "project extra keys"
  end

  test "free-text filtering leaves code and class names alone" do
    [ "ActionController::InvalidAuthenticityToken: Can't verify CSRF token authenticity.",
      "Token::Invalid raised", "if token == expected", "undefined method `token' for nil",
      "https://x.dev/a?token=[FILTERED]" ].each { |text| assert_equal text, @scrubber.scrub_text(text) }
  end

  test "free-text filtering stays linear on long input" do
    long_word = "x" * 20_000
    assert_equal long_word, @scrubber.scrub_text(long_word)
    assert_equal 3_000, @scrubber.scrub_text("token: a " * 3_000).scan("[FILTERED]").size
  end

  test "leaves non-string scalars alone" do
    assert_equal [ 1, 2.5, true, nil ], @scrubber.scrub([ 1, 2.5, true, nil ])
  end
end
