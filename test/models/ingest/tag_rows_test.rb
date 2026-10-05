require "test_helper"

class Ingest::TagRowsTest < ActiveSupport::TestCase
  setup { @issue = issues(:card_error) }

  def fill(key, values)
    IssueTagCount.insert_all(values.map do |value|
      { issue_id: @issue.id, key:, value_digest: IssueTagCount.value_digest(key, value), value:, count: 1 }
    end)
  end

  def rows(tags) = Ingest::TagRows.new(@issue.id, tags).to_a

  test "rows for every tag, sorted by key and digest" do
    result = rows("release" => "a1", "browser" => "Chrome")

    assert_equal %w[browser release], result.map { it[:key] }
    assert_equal IssueTagCount.value_digest("browser", "Chrome"), result.first[:value_digest]
  end

  test "a key at its value cap counts new values as Other values but keeps counting known ones" do
    fill("request_id", Array.new(IssueTagCount::VALUES_PER_KEY) { "req-#{it}" })

    assert_equal [ [ "other", "Other values" ] ], rows("request_id" => "req-new").map { it.values_at(:value_digest, :value) }
    assert_equal IssueTagCount.value_digest("request_id", "req-7"), rows("request_id" => "req-7").sole[:value_digest]
  end

  test "an issue at its key cap drops new keys but keeps counting known keys" do
    IssueTagCount::KEYS_PER_ISSUE.times { |n| fill("key#{n}", [ "v" ]) }

    assert_empty rows("brand_new" => "x")
    assert_equal [ "key3" ], rows("key3" => "another").map { it[:key] }
  end

  test "known values cost one query" do
    fill("browser", [ "Chrome" ])
    assert_queries_count(1) { rows("browser" => "Chrome") }
  end

  test "the issue page reads capped keys as N+ values" do
    fill("request_id", Array.new(IssueTagCount::VALUES_PER_KEY) { "req-#{it}" })
    IssueTagCount.upsert_all(rows("request_id" => "req-new"), on_duplicate: Arel.sql("count = issue_tag_counts.count + 1"),
                             record_timestamps: false)

    key = IssueTagCount.distribution(@issue).sole
    assert key.capped?
    assert_equal IssueTagCount::VALUES_PER_KEY, key.distinct_count
    assert_equal IssueTagCount::VALUES_PER_KEY + 1, key.total
  end
end
