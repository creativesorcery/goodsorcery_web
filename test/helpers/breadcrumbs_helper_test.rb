require "test_helper"

class BreadcrumbsHelperTest < ActionView::TestCase
  include CapturedDataHelper

  test "details per category" do
    assert_equal "SELECT 1", breadcrumb_details({ "category" => "sql", "data" => { "sql" => "SELECT 1" } })
    assert_equal "200 · 212ms", breadcrumb_details({ "category" => "http", "data" => { "status" => 200, "duration_ms" => 212 } })
    assert_equal "job: Mailer · args: [1]", breadcrumb_details({ "category" => "job", "data" => { "job" => "Mailer", "args" => [ 1 ] } })
    assert_equal "", breadcrumb_details({ "category" => "log", "data" => "not a hash" })
  end

  test "offsets, tones, counts and loud levels" do
    assert_equal "−1,204ms", breadcrumb_offset(-1204)
    assert_equal "bg-lilac-400", breadcrumb_tone("sql")[:dot]
    assert_equal BreadcrumbsHelper::DEFAULT_TONE, breadcrumb_tone("custom")
    assert_equal 2, breadcrumb_count([ { "category" => "sql" }, { "category" => "sql" }, { "category" => "log" } ], "sql")
    assert_equal "[warn]", breadcrumb_level_prefix({ "level" => "warning" })
    assert_nil breadcrumb_level_prefix({ "level" => "info" })
  end
end
