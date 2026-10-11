require "test_helper"

class ProjectOverviewTest < ActiveSupport::TestCase
  setup do
    @projects = accounts(:acme).projects.order(:name).to_a
  end

  test "builds one card per project, in order" do
    cards = ProjectOverview.new(@projects).cards

    assert_equal @projects, cards.map(&:project)
  end

  test "counts unresolved and new issues per project" do
    storefront = card_for(:storefront)

    assert_equal projects(:storefront).issues.unresolved.count, storefront.unresolved_count
    assert_equal 1, storefront.new_count
    assert_equal 1, card_for(:billing).unresolved_count
    assert_equal 0, card_for(:billing).new_count
  end

  test "projects without issues get zeros and no last error" do
    marketing = card_for(:marketing)

    assert_equal 0, marketing.unresolved_count
    assert_equal 0, marketing.new_count
    assert_nil marketing.last_seen_at
  end

  test "last error is the latest last_seen_at across every status" do
    assert_in_delta issues(:nomethod).last_seen_at, card_for(:storefront).last_seen_at, 1.second
  end

  test "environments come from api keys in creation order" do
    assert_equal %w[production staging], card_for(:storefront).environments
    assert_equal %w[production], card_for(:marketing).environments
    assert_equal [], card_for(:billing).environments
  end

  test "unresolved issues are broken down per environment, production first" do
    issues(:card_error).update_columns(environments: %w[staging])

    assert_equal [ [ "production", 2 ], [ "staging", 2 ] ], card_for(:storefront).unresolved_by_environment
    assert_equal [ [ "production", 1 ] ], card_for(:billing).unresolved_by_environment
    assert_equal [], card_for(:marketing).unresolved_by_environment
  end

  test "environments outside the key list follow by name, production-like ones lead" do
    issues(:nomethod).update_columns(environments: %w[qa])
    issues(:card_error).update_columns(environments: %w[live])

    assert_equal %w[production live staging qa], card_for(:storefront).unresolved_by_environment.map(&:first)
  end

  test "daily series are kept per environment and summed for the total" do
    card = card_for(:storefront)

    assert_equal %w[production staging], card.series_by_environment.map(&:first)
    assert_equal card.series_by_environment.map(&:last).transpose.map(&:sum), card.daily_series
    assert_equal 6, card.series_by_environment.to_h.fetch("staging").last
    assert_equal [], card_for(:marketing).series_by_environment
  end

  test "daily series has fourteen zero-filled days" do
    assert_equal 14, card_for(:storefront).daily_series.size
    assert_equal Array.new(14, 0), card_for(:marketing).daily_series
    assert_operator card_for(:storefront).daily_series.sum, :>, 0
  end

  test "health is derived for each card" do
    assert_predicate card_for(:marketing).health, :listening?
    assert_includes %i[spiking steady], card_for(:storefront).health.status
  end

  test "uses a fixed number of queries however many projects there are" do
    few = count_queries { ProjectOverview.new(@projects.first(1)).cards }
    many = count_queries { ProjectOverview.new(@projects).cards }
    more = accounts(:acme).projects.create!(name: "Extra app")
    issues(:nomethod).dup.tap { |issue| issue.assign_attributes(project: more, number: 1, environments: %w[staging]) }.save!
    most = count_queries { ProjectOverview.new(@projects + [ more ]).cards.each(&:unresolved_by_environment) }

    assert_equal few, many
    assert_equal many, most
    assert_operator many, :<=, 6
  end

  test "per-environment counts and series come from one grouped query each" do
    sql = capture_sql { ProjectOverview.new(@projects).cards }

    assert_equal 1, sql.grep(/unnest\(issues\.environments\)/).size
    assert_equal 1, sql.grep(/FROM "project_hourly_counts".*GROUP BY "project_hourly_counts"\."project_id", "project_hourly_counts"\."environment"/).size
  end

  test "never loads encrypted api key tokens" do
    sql = capture_sql { ProjectOverview.new(@projects).cards }

    api_key_sql = sql.grep(/FROM "api_keys"/)

    assert_equal 1, api_key_sql.size
    assert_no_match(/"api_keys"\.\*|"token"/, api_key_sql.first)
  end

  test "cache key changes when a number on the card changes" do
    before = card_for(:billing).cache_key
    issues(:billing_timeout).update_columns(status: "resolved")

    assert_not_equal before, card_for(:billing).cache_key
  end

  test "cache key is stable when nothing changed" do
    now = Time.current

    assert_equal ProjectOverview.new(@projects, now:).card_for(projects(:billing)).cache_key,
      ProjectOverview.new(@projects, now:).card_for(projects(:billing)).cache_key
  end

  test "cache key changes when an issue reaches another environment" do
    before = card_for(:storefront).cache_key
    issues(:card_error).update_columns(environments: %w[production staging])

    assert_not_equal before, card_for(:storefront).cache_key
  end

  test "cache key holds no issue text" do
    key = card_for(:storefront).cache_key

    assert_no_match(/price_cents|NoMethodError/, key)
  end

  private
    def card_for(name)
      ProjectOverview.new(@projects).card_for(projects(name))
    end

    def count_queries(&block)
      capture_sql(&block).size
    end

    def capture_sql(&block)
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
      statements
    end

  test "last seen times come from one index probe per project, not a grouped scan of all issues" do
    overview = ProjectOverview.new(accounts(:acme).projects.order(:name))
    sql = nil
    callback = ->(*, payload) { sql ||= payload[:sql] if payload[:sql].include?("MAX(issues.last_seen_at)") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { overview.cards }

    assert_includes sql, "WHERE issues.project_id = projects.id"
    assert_equal projects(:storefront).issues.maximum(:last_seen_at), overview.card_for(projects(:storefront)).last_seen_at
    assert_nil overview.card_for(projects(:marketing)).last_seen_at
  end
end
