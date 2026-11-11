require "test_helper"

class IssueListTest < ActiveSupport::TestCase
  setup do
    @project = projects(:storefront)
    @alex = users(:alex)
  end

  test "lists the query's issues sorted by last seen with assignees preloaded" do
    list = list_for("is:unresolved")

    assert_equal [ issues(:nomethod), issues(:regressed), issues(:card_error) ], list.issues
    assert list.issues.all? { |issue| issue.association(:assignee).loaded? }
    assert list.issues.all? { |issue| issue.association(:project).loaded? }
  end

  test "sorts by events, users and first seen" do
    assert_equal issues(:card_error), list_for("is:unresolved", sort: "events").issues.first
    assert_equal issues(:nomethod), list_for("is:unresolved", sort: "users").issues.first
    assert_equal issues(:nomethod), list_for("is:unresolved", sort: "first_seen").issues.first
    assert_equal "last_seen", list_for("", sort: "drop table").sort
  end

  test "histograms come from one query for the whole page" do
    list = list_for("is:unresolved")
    list.issues

    queries = count_queries { list.issues.each { |issue| list.histogram_for(issue) } }
    nomethod = list.histogram_for(issues(:nomethod))

    assert_equal 1, queries
    assert_equal 24, nomethod.size
    assert_equal 32, nomethod.last
    assert_equal [ 0 ] * 23 + [ 4 ], list.histogram_for(issues(:regressed))
  end

  test "tab counts honour the other chips and come from one query" do
    list = list_for("is:unresolved")
    counts = nil

    assert_equal 1, count_queries { counts = list.tab_counts }
    assert_equal({ "unresolved" => 3, "for_review" => 2, "assigned" => 1, "ignored" => 1, "resolved" => 1 }, counts)
    assert_equal 1, list_for("is:unresolved env:staging").tab_counts["unresolved"]
  end

  test "assigned count is zero without a user" do
    assert_equal 0, IssueList.new(@project, IssueQuery.new).tab_counts["assigned"]
  end

  test "pages with a lookahead row and a cap" do
    create_issues(30)
    first = list_for("is:unresolved")
    second = list_for("is:unresolved", page: 2)

    assert_equal 25, first.issues.size
    assert_predicate first, :next_page?
    assert_equal 2, first.next_page
    assert_equal 33, first.total_count
    assert_equal 8, second.issues.size
    assert_not second.next_page?
    assert_equal 33, second.shown_count
    assert_empty first.issues & second.issues
  end

  test "page numbers are clamped" do
    assert_equal 1, list_for("", page: "-3").page
    assert_equal IssueList::MAX_PAGE, list_for("", page: "999999").page
  end

  test "default state is the first unresolved page in the default sort" do
    assert_predicate list_for("is:unresolved"), :default_state?
    assert_not list_for("is:unresolved", page: 2).default_state?
    assert_not list_for("is:unresolved", sort: "events").default_state?
    assert_not list_for("is:resolved").default_state?
  end

  test "an empty page needs no histogram query" do
    list = list_for("is:unresolved nothing-matches-this")
    issue = issues(:nomethod)
    list.issues

    assert_predicate list, :empty?
    assert_equal 0, count_queries { list.histogram_for(issue) }
  end

  private
    def list_for(query, page: 1, sort: nil)
      IssueList.new(@project, IssueQuery.new(query, user: @alex), page:, sort:)
    end

    def create_issues(count)
      count.times do |index|
        @project.issues.create!(number: 5_000 + index, fingerprint: Digest::SHA256.hexdigest("list-#{index}"),
          exception_class: "RuntimeError", message: "boom #{index}", first_seen_at: 3.days.ago,
          last_seen_at: (index + 20).minutes.ago, environments: [ "production" ])
      end
    end

    def count_queries(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end

  test "every sort is backed by an index for the default unresolved list" do
    indexes = Issue.connection.indexes(:issues).map(&:columns)
    Issue::SORTS.values.each do |column|
      assert indexes.any? { |columns| columns.first == "project_id" && columns.last == column.to_s }, "index ending in #{column}"
    end
  end
end
