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

  test "removes row and value dumps from common database and lookup errors" do
    assert_equal "PG::NotNullViolation: ERROR: null value in column \"email\" DETAIL: Failing row contains ([row]).",
                 @redactor.redact('PG::NotNullViolation: ERROR: null value in column "email" DETAIL: ' \
                                  "Failing row contains (12, Mara Kowalski, 221B Baker Street, +44 20 7946 0958).")
    assert_equal "DETAIL: Key (username)=([value]) already exists.",
                 @redactor.redact("DETAIL: Key (username)=(mara_k) already exists.")
    assert_equal "Couldn't find User with 'username'=[value]", @redactor.redact("Couldn't find User with 'username'=mara_k")
    assert_equal "WHERE name =[value] LIMIT [n]", @redactor.redact("WHERE name = 'Mara Kowalski' LIMIT 10")
    assert_equal "No user found for [value]", @redactor.redact("No user found for 'Mara Kowalski'")
  end

  test "keeps quoted code identifiers" do
    assert_equal "undefined method 'price_cents' for nil", @redactor.redact("undefined method 'price_cents' for nil")
    assert_equal "undefined local variable or method `cart' for an instance of CartsController",
                 @redactor.redact("undefined local variable or method `cart' for an instance of CartsController")
  end

  test "redacts transaction names, dropping query strings" do
    assert_equal "GET /users/[email]/reset?[query]", @redactor.redact_transaction("GET /users/mara@example.com/reset?x=1")
    assert_equal "GET /orders/[n]", @redactor.redact_transaction("GET /orders/5521")
    assert_equal "Api::V2::OrdersController#create", @redactor.redact_transaction("Api::V2::OrdersController#create")
    assert_nil @redactor.redact_transaction(nil)
  end

  test "redacts locations but keeps line numbers" do
    assert_equal "app/x.rb:142 in [email]", @redactor.redact_location("app/x.rb:142 in mara@example.com")
    assert_equal "app/models/user.rb:42 in find_by_login", @redactor.redact_location("app/models/user.rb:42 in find_by_login")
  end

  test "caps the title at 1,024 characters and squishes whitespace" do
    assert_equal 1_024, @redactor.redact("x " * 2_000).length
    assert_equal "a b", @redactor.redact("a\n\n  b")
  end

  test "handles nil" do
    assert_equal "", @redactor.redact(nil)
  end
end
