require "test_helper"

class Ingest::MessageRedactorTest < ActiveSupport::TestCase
  setup { @redactor = Ingest::MessageRedactor.new }

  test "replaces emails, uuids, ips, numbers, query strings and tokens" do
    message = "User mara.l+shop@example.co.uk (id 5521) from 81.2.69.160 hit " \
              "https://shop.acme.dev/cart?coupon=FALL25&u=1 with request 7d4c2a91-1e0f-4b8e-a2d1-55f0c8e1b0aa " \
              "token a1b2c3d4e5f6a7b8c9d0 and key sk_live_4eC39HqLyjWDarjtT1zdp7dc"
    assert_equal "User [email] (id [n]) from [ip] hit https://shop.acme.dev/cart?[query] with request [uuid] " \
                 "token [token] and key [token]", @redactor.redact(message)
  end

  test "keeps code identifiers and short numbers" do
    message = 'PG::UniqueViolation: duplicate key value violates unique constraint "index_orders_on_idempotency_key"'
    assert_equal message, @redactor.redact(message)
    assert_equal "undefined method `price_cents' for nil", @redactor.redact("undefined method `price_cents' for nil")
    assert_equal "retry 3 of 5", @redactor.redact("retry 3 of 5")
  end

  test "caps the title at 1,024 characters and squishes whitespace" do
    assert_equal 1_024, @redactor.redact("x " * 2_000).length
    assert_equal "a b", @redactor.redact("a\n\n  b")
  end

  test "handles nil" do
    assert_equal "", @redactor.redact(nil)
  end
end
