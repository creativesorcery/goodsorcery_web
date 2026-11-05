require "test_helper"

class Apm::SqlSummaryTest < ActiveSupport::TestCase
  test "labels name the verb, table and condition" do
    assert_equal 'SELECT "users" WHERE "id" = $1', label('SELECT "users".* FROM "users" WHERE "users"."id" = $1 LIMIT $2')
    assert_equal 'INSERT INTO "orders"', label('INSERT INTO "orders" ("total") VALUES ($1) RETURNING "id"')
    assert_equal 'UPDATE "inventory_levels" WHERE "sku" IN (?)', label('UPDATE "inventory_levels" SET "count" = ? WHERE "sku" IN (?)')
    assert_equal 'DELETE FROM "carts" WHERE "id" = $1', label('DELETE FROM "carts" WHERE "carts"."id" = $1')
    assert_equal "BEGIN", label("BEGIN")
  end

  test "the first table read" do
    assert_equal "products", Apm::SqlSummary.new('SELECT * FROM "public"."products" WHERE x = 1').table
    assert_nil Apm::SqlSummary.new("COMMIT").table
  end

  test "one clause per line; joins stay with their modifier" do
    lines = Apm::SqlSummary.new("SELECT a FROM b LEFT OUTER JOIN c ON c.id = b.c_id WHERE b.x = $1 ORDER BY a LIMIT ?").lines
    texts = lines.map { |line| line.map(&:last).join }
    assert_equal [ "SELECT a FROM b", "LEFT OUTER JOIN c ON c.id = b.c_id", "WHERE b.x = $1", "ORDER BY a LIMIT ?" ], texts
    assert_includes lines.last, [ :placeholder, "?" ]
    assert_includes lines.first, [ :keyword, "SELECT" ]
    assert_includes lines.first, [ :text, "a" ]
  end

  test "quoted identifiers are never keywords" do
    tokens = Apm::SqlSummary.new('SELECT "order" FROM "select"').lines.flatten(1)
    assert_includes tokens, [ :text, '"order"' ]
    assert_includes tokens, [ :text, '"select"' ]
  end

  private
    def label(sql) = Apm::SqlSummary.new(sql).label
end
