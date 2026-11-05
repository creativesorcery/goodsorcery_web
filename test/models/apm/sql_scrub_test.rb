require "test_helper"

class Apm::SqlScrubTest < ActiveSupport::TestCase
  def scrub(sql) = Apm::SqlScrub.new.scrub(sql)

  test "literals become ?, placeholders and identifiers stay" do
    assert_equal %(SELECT "users".* FROM "users" WHERE "users"."email" = ? AND "id" = $1 AND t2.n > ? LIMIT ?),
                 scrub(%(SELECT "users".* FROM "users" WHERE "users"."email" = 'mara@example.com' AND "id" = $1 AND t2.n > 42.5 LIMIT 10))
  end

  test "escaped and cut-off strings, dollar quotes and E strings" do
    assert_equal "SELECT ?, ?, ?", scrub("SELECT 'it''s', $$a 'b' c$$, $tag$secret$tag$")
    assert_equal "SELECT ?", scrub("SELECT E'it\\'s'")
    assert_equal "SELECT ?", scrub("SELECT 'cut off here")
  end

  test "comments are removed, including query-log tags" do
    assert_equal "SELECT ? FROM t", scrub("SELECT 1 /* request_id:abc-123, user:mara */ FROM t -- trailing\n")
  end

  test "IN lists and VALUES rows collapse" do
    assert_equal "SELECT * FROM t WHERE id IN (…) AND x IN (…)", scrub("SELECT * FROM t WHERE id IN (1, 2, 3) AND x IN ($1,$2)")
    assert_equal "INSERT INTO t (a, b) VALUES (?, ?), …", scrub("INSERT INTO t (a, b) VALUES (1, 'x'), (2, 'y'), (3, 'z')")
  end

  test "TRUE, FALSE, NULL and whitespace" do
    assert_equal "SELECT * FROM t WHERE a IS NULL AND b = TRUE", scrub("SELECT *\n  FROM t\tWHERE a IS NULL AND b = TRUE")
  end

  test "secrets left in identifiers are scrubbed and the result is capped" do
    assert_includes scrub(%(SELECT "password=hunter2" FROM t)), "[FILTERED]"
    assert_equal Apm::Limits::SQL, scrub("SELECT #{"a" * 5_000}").size
  end
end
