require "test_helper"
require "rake"

class Account::ProjectRetentionTest < ActiveSupport::TestCase
  setup do
    freeze_time
    @account = accounts(:acme)
    @storefront, @billing, @marketing = projects(:storefront), projects(:billing), projects(:marketing)
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  def retention(*projects) = projects.map { it.reload.retention_days }

  test "a hosted downgrade moves every app to the nearest allowed retention" do
    @account.update_entitlements!("retention_days" => [ 30, 60, 90 ])
    @billing.update_column(:retention_days, 60)
    @marketing.update_column(:retention_days, 90)

    with_hosted_mode { @account.update_entitlements!("retention_days" => [ 30 ]) }

    assert_equal [ 30, 30, 30 ], retention(@storefront, @billing, @marketing)
    assert_equal Time.current, @billing.updated_at
  end

  test "nearest wins, and a tie goes to the longer retention" do
    @storefront.update_column(:retention_days, 60)
    @billing.update_column(:retention_days, 45)
    @marketing.update_column(:retention_days, 30)

    with_hosted_mode { @account.update_entitlements!("retention_days" => [ 30, 90 ]) }
    assert_equal [ 90, 30, 30 ], retention(@storefront, @billing, @marketing), "60 is as far from 30 as from 90"

    @billing.update_column(:retention_days, 45)
    with_hosted_mode { @account.update_entitlements!("retention_days" => [ 60, 90 ]) }
    assert_equal [ 90, 60, 60 ], retention(@storefront, @billing, @marketing), "45 and 30 are below the shortest allowed"
  end

  test "an upgrade moves nothing" do
    with_hosted_mode { @account.update_entitlements!("retention_days" => [ 30, 60, 90 ]) }

    assert_equal [ 30, 30, 30 ], retention(@storefront, @billing, @marketing)
  end

  test "self-hosted, every choice is allowed and only other values move to the nearest choice" do
    @storefront.update_column(:retention_days, 14)
    @billing.update_column(:retention_days, 75)
    @marketing.update_column(:retention_days, 60)
    @account.update_entitlements!("retention_days" => [ 30 ])

    assert_equal [ 30, 90, 60 ], retention(@storefront, @billing, @marketing)
  end

  test "fitting is one statement however many apps need moving" do
    with_hosted_mode(false) { 3.times { |n| @account.projects.create!(name: "Extra #{n}") } }
    @account.projects.update_all(retention_days: 90)

    statements = count_queries { with_hosted_mode { @account.fit_project_retention_to_entitlements } }

    assert_equal 1, statements
    assert_equal [ 30 ], @account.projects.distinct.pluck(:retention_days)
    assert_equal 1, count_queries { with_hosted_mode { @account.fit_project_retention_to_entitlements } }
  end

  test "fitting never touches another account's apps" do
    projects(:umbrella_app).update_column(:retention_days, 90)
    accounts(:umbrella).update_entitlements!("retention_days" => [ 30, 60, 90 ])

    with_hosted_mode { @account.fit_to_entitlements }

    assert_equal 90, projects(:umbrella_app).reload.retention_days
  end

  test "an entitlement_values change fits retention after commit, other changes don't" do
    @storefront.update_column(:retention_days, 90)

    with_hosted_mode { @account.update!(name: "Acme Renamed") }
    assert_equal 90, @storefront.reload.retention_days

    with_hosted_mode { @account.update_entitlements!("max_projects" => 5) }
    assert_equal 30, @storefront.reload.retention_days
  end

  test "the rake task fits every account's apps" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("goodsorcery:fit_entitlements")
    @storefront.update_column(:retention_days, 90)
    projects(:umbrella_app).update_column(:retention_days, 60)

    with_hosted_mode { assert_output(/Fitted/) { Rake::Task["goodsorcery:fit_entitlements"].execute } }

    assert_equal [ 30, 30 ], retention(@storefront, projects(:umbrella_app))
  end

  test "nearest_value picks the nearest allowed value, ties going up" do
    assert_equal "30", Account::ProjectRetention.nearest_value([ 30 ]).to_sql
    assert_equal 'CASE WHEN "projects"."retention_days" * 2 < 90 THEN 30 ELSE 60 END',
                 Account::ProjectRetention.nearest_value([ 60, 30 ]).to_sql
    assert_equal 'CASE WHEN "projects"."retention_days" * 2 < 90 THEN 30 WHEN "projects"."retention_days" * 2 < 150 THEN 60 ELSE 90 END',
                 Account::ProjectRetention.nearest_value([ 30, 60, 90 ]).to_sql
    assert_raises(ArgumentError) { Account::ProjectRetention.nearest_value([ "30; DROP TABLE projects" ]) }
  end
end
