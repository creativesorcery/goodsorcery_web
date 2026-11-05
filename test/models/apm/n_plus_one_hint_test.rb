require "test_helper"

class Apm::NPlusOneHintTest < ActiveSupport::TestCase
  test "names the association after the table" do
    hint = Apm::NPlusOneHint.new('SELECT "products".* FROM "products" WHERE "products"."id" = $1 LIMIT $2')
    assert_equal "Load the products in one query instead:", hint.lead
    assert_equal "….includes(:product)", hint.code

    assert_equal "Load the order items in one query instead:", Apm::NPlusOneHint.new("SELECT * FROM order_items WHERE id = ?").lead
  end

  test "falls back to generic advice without a table" do
    hint = Apm::NPlusOneHint.new("CALL refresh()")
    assert_equal "Preload the association with includes so it loads in one query.", hint.lead
    assert_nil hint.code
  end
end
