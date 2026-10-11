require "test_helper"

class IssueQueryTest < ActiveSupport::TestCase
  setup do
    @project = projects(:storefront)
    @philip = users(:philip)
  end

  test "parses chips and free text" do
    query = IssueQuery.new("is:unresolved ENV:Production level:error cart total")

    assert_equal %w[is:unresolved env:production level:error], query.chips.map(&:to_s)
    assert_equal "cart total", query.text
    assert_equal "production", query.environment
    assert_equal "error", query.level
    assert_equal "unresolved", query.status
  end

  test "unknown keys stay free text and duplicates collapse" do
    query = IssueQuery.new("is:unresolved is:unresolved foo:bar")

    assert_equal %w[is:unresolved], query.chips.map(&:to_s)
    assert_equal "foo:bar", query.text
  end

  test "class and user values keep their case" do
    query = IssueQuery.new("class:Stripe::CardError user:Mara")

    assert_equal %w[class:Stripe::CardError user:Mara], query.chips.map(&:to_s)
  end

  test "from_params defaults to unresolved and honours an explicit empty q" do
    assert_equal "is:unresolved", IssueQuery.from_params(params).to_s
    assert_equal "", IssueQuery.from_params(params(q: "")).to_s
    assert_equal "level:error", IssueQuery.from_params(params(q: "level:error")).to_s
  end

  test "from_params composes the hidden chips with the text input" do
    query = IssueQuery.from_params(params(chips: "is:unresolved env:production", text: "level:error checkout"))

    assert_equal "is:unresolved env:production level:error checkout", query.to_s
  end

  test "from_params ignores non-string params" do
    assert_equal "", IssueQuery.from_params(params(q: { "x" => "y" })).to_s
  end

  test "caps the query length" do
    assert_operator IssueQuery.new("a" * 2_000).text.length, :<=, IssueQuery::MAX_LENGTH
  end

  test "is: chips filter by status" do
    assert_equal ids(:nomethod, :regressed, :card_error), filter("is:unresolved")
    assert_equal ids(:resolved_issue), filter("is:resolved")
    assert_equal ids(:ignored_issue), filter("is:ignored")
    assert_equal ids(:nomethod, :regressed), filter("is:for_review")
    assert_equal ids(:nomethod), filter("is:new")
    assert_equal ids(:regressed), filter("is:regressed")
    assert_empty filter("is:bogus")
  end

  test "env and level chips" do
    assert_equal ids(:regressed), filter("env:staging")
    assert_equal ids(:card_error), filter("level:warning")
    assert_empty filter("level:catastrophic")
  end

  test "assigned chips use the current user" do
    assert_equal ids(:nomethod), filter("is:unresolved assigned:me", user: @philip)
    assert_equal ids(:regressed), filter("is:unresolved assigned:none")
    assert_empty filter("assigned:me")
  end

  test "user chip matches id, email or username digests, or a raw digest" do
    digest = PrivateDigest.hexdigest("user.id", "5521")

    assert_equal ids(:nomethod, :regressed), filter("user:mara@example.com")
    assert_equal ids(:nomethod, :regressed), filter("user:MARA@example.com")
    assert_equal ids(:nomethod, :regressed), filter("user:5521")
    assert_equal ids(:nomethod, :regressed), filter("user:#{digest}")
    assert_equal ids(:nomethod), filter("user:sam@example.com")
    assert_empty filter("user:nobody@example.com")
  end

  test "class chip matches the exception class case-insensitively" do
    assert_equal ids(:card_error), filter("class:stripe::carderror")
    assert_empty filter("class:Stripe::")
  end

  test "free text searches class, message, culprit and transaction" do
    assert_equal ids(:nomethod), filter("price_cents")
    assert_equal ids(:card_error), filter("PaymentsController")
    assert_equal ids(:resolved_issue), filter("ups_client")
    assert_equal ids(:nomethod), filter("is:unresolved checkout line_total")
  end

  test "free text treats LIKE wildcards literally" do
    assert_empty filter("100%")
    assert_empty filter("_____________________________________________")
  end

  test "tab detection and rewriting keep the other chips and text" do
    query = IssueQuery.new("is:unresolved env:production checkout")

    assert_equal "unresolved", query.tab
    assert_equal "is:for_review env:production checkout", query.for_tab("for_review").to_s
    assert_equal "is:unresolved assigned:me env:production checkout", query.for_tab("assigned").to_s
    assert_equal "assigned", query.for_tab("assigned").tab
    assert_nil IssueQuery.new("env:production").tab
  end

  test "adding and removing chips" do
    query = IssueQuery.new("is:unresolved env:production oops")

    assert_equal "is:unresolved env:staging oops", query.with_chip("env", "staging").to_s
    assert_equal "is:unresolved oops", query.without_chip(query.chips.last).to_s
    assert_equal "env:production oops", query.without_key("is").to_s
    assert_equal "is:unresolved env:production", query.chips_string
  end

  test "with_environment scopes to one environment or all, keeping chips and text" do
    query = IssueQuery.new("is:unresolved level:error oops")

    assert_equal "is:unresolved level:error env:staging oops", query.with_environment("staging").to_s
    assert_equal "is:unresolved level:error env:production oops", query.with_environment("staging").with_environment("production").to_s
    assert_equal "is:unresolved level:error oops", query.with_environment("staging").with_environment(nil).to_s
    assert_same query, query.with_environment(nil)
  end

  test "default_view? ignores the environment" do
    assert_predicate IssueQuery.new("is:unresolved env:production"), :default_view?
    assert_predicate IssueQuery.new, :default_view?
    assert_not IssueQuery.new("is:unresolved env:production level:error").default_view?
  end

  test "default? and unresolved_only?" do
    assert_predicate IssueQuery.new, :default?
    assert_not IssueQuery.new("is:unresolved x").default?
    assert_predicate IssueQuery.new("is:for_review"), :unresolved_only?
    assert_not IssueQuery.new("is:resolved").unresolved_only?
    assert_not IssueQuery.new("").unresolved_only?
  end

  test "chip labels shorten digests" do
    digest = PrivateDigest.hexdigest("user.id", "5521")
    chip = IssueQuery::Chip.parse("user:#{digest}")

    assert_equal "user:#{digest.first(12)}…", chip.label
    assert_equal "env:production", IssueQuery::Chip.parse("env:production").label
    assert_nil IssueQuery::Chip.parse("plain")
  end

  private
    def filter(query, user: nil)
      IssueQuery.new(query, user:).issues(@project.issues).order(:id).ids
    end

    def ids(*names)
      names.map { |name| issues(name).id }.sort
    end

    def params(hash = {})
      ActionController::Parameters.new(hash)
    end
end
