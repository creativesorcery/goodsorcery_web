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

    assert_equal few, many
    assert_operator many, :<=, 6
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
end
