require "test_helper"

class IssueTagCountTest < ActiveSupport::TestCase
  test "distribution ranks values per key with shares from one query" do
    issue = issues(:nomethod)
    keys = nil
    assert_queries_count(1) { keys = IssueTagCount.distribution(issue) }

    assert_equal %w[browser coupon], keys.map(&:key)
    browser = keys.first
    assert_equal 3, browser.distinct_count
    assert_equal 1284, browser.total
    assert_equal [ "Mobile Safari", "Chrome", "Firefox" ], browser.values.map(&:value)
    assert_in_delta 1100 / 1284.0, browser.values.first.share
  end

  test "distribution limits values per key but keeps the distinct count" do
    browser = IssueTagCount.distribution(issues(:nomethod), per_key: 1).first

    assert_equal [ "Mobile Safari" ], browser.values.map(&:value)
    assert_equal 3, browser.distinct_count
  end

  test "distribution is empty without tags" do
    assert_empty IssueTagCount.distribution(issues(:card_error))
  end

  test "value digests are namespaced by key" do
    assert_equal PrivateDigest.hexdigest("tag.browser", "Chrome"), IssueTagCount.value_digest("browser", "Chrome")
    assert_not_equal IssueTagCount.value_digest("browser", "x"), IssueTagCount.value_digest("os", "x")
  end
end
