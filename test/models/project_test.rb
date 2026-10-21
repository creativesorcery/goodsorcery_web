require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { Current.session = sessions(:philip_browser) }
  teardown { Current.reset }

  test "to_param is the slug" do
    assert_equal "storefront", projects(:storefront).to_param
  end

  test "creating a project derives slug, prefix and color and adds default keys" do
    project = accounts(:acme).projects.create!(name: "Fulfillment Workers")

    assert_equal "fulfillment-workers", project.slug
    assert_equal "FW", project.issue_prefix
    assert_equal Project::COLORS[3 % 4], project.color
    assert_equal %w[production staging], project.environments
    assert_equal users(:philip), project.api_keys.first.created_by
  end

  test "a new app opens on production, since it is created with a production key" do
    project = accounts(:acme).projects.create!(name: "Fulfillment Workers")

    assert_equal "production", project.default_environment
    assert_equal "production", project.reload.default_environment
  end

  test "default environment is one of the app's environments, or nil for all" do
    project = projects(:storefront)

    project.default_environment = "staging"
    assert project.valid?

    project.default_environment = " "
    assert project.valid?
    assert_nil project.default_environment

    project.default_environment = "Production"
    assert project.valid?
    assert_equal "production", project.default_environment

    project.default_environment = "qa"
    assert_not project.valid?
    assert_includes project.errors[:default_environment], "must be one of this app's environments"
  end

  test "slug collisions within an account get a numeric suffix" do
    first = accounts(:acme).projects.create!(name: "storefront")
    second = accounts(:acme).projects.create!(name: "Storefront!")

    assert_equal "storefront-2", first.slug
    assert_equal "storefront-3", second.slug
    assert_equal "storefront", accounts(:umbrella).projects.create!(name: "storefront").slug
  end

  test "slug is immutable" do
    project = projects(:storefront)
    assert_raises(ActiveRecord::ReadonlyAttributeError) { project.update!(slug: "other") }
  end

  test "explicit prefix and color are kept" do
    project = accounts(:acme).projects.create!(name: "Back office", issue_prefix: "bo", color: "lilac")
    assert_equal "BO", project.issue_prefix
    assert_equal "lilac", project.color
  end

  test "validations" do
    project = accounts(:acme).projects.new(name: "x" * 61, retention_days: 400, issue_prefix: "TOOLONGX", platform: "php")
    assert_not project.valid?
    assert_equal %i[issue_prefix name platform retention_days], project.errors.attribute_names.sort
  end

  test "retention defaults to 30 days and can't go above it" do
    project = accounts(:acme).projects.new(name: "Back office")
    assert_equal 30, project.retention_days

    project.retention_days = 31
    assert_not project.valid?
    assert_includes project.errors[:retention_days], "must be in 1..30"

    project.retention_days = 30
    assert project.valid?
  end

  test "an account has at most MAX_PER_ACCOUNT projects" do
    with_constant(Project, :MAX_PER_ACCOUNT, accounts(:acme).projects.count) do
      project = accounts(:acme).projects.create(name: "One more")
      assert_includes project.errors[:base], "An account can have at most #{Project::MAX_PER_ACCOUNT} apps"
    end
  end

  test "issue prefixes are unique per account, including derived defaults" do
    account = accounts(:acme)
    store = account.projects.create!(name: "Store")
    storefront = account.projects.create!(name: "Storefront")

    assert_equal [ "STO", "STOB" ], [ store.issue_prefix, storefront.issue_prefix ]
    duplicate = account.projects.create(name: "Other", issue_prefix: "STO")
    assert_includes duplicate.errors[:issue_prefix], "has already been taken"
    assert accounts(:umbrella).projects.create(name: "Other", issue_prefix: "STO").persisted?
  end

  test "scrub fields are normalised" do
    project = projects(:storefront)
    project.update!(scrub_fields: [ " Loyalty_Number ", "", "loyalty_number", "pin" ])
    assert_equal %w[loyalty_number pin], project.scrub_fields
  end

  test "listening until the first event" do
    assert projects(:marketing).listening?
    assert_not projects(:storefront).listening?
  end

  test "accessible by account members only" do
    assert projects(:storefront).accessible_by?(users(:jo))
    assert_not projects(:storefront).accessible_by?(users(:outsider))
  end

  test "environments come from api keys in creation order, with or without preloading" do
    assert_equal %w[production staging], projects(:storefront).environments
    preloaded = Project.includes(:api_keys).find(projects(:storefront).id)
    assert_equal %w[production staging], preloaded.environments
  end

  test "allocate_issue_number increments atomically" do
    project = projects(:storefront)
    assert_equal 1046, project.allocate_issue_number
    assert_equal 1047, project.allocate_issue_number
    assert_equal 1047, project.reload.issues_sequence
  end

  test "record_first_event keeps the first timestamp and updates the runtime label" do
    project = projects(:marketing)
    first = 2.minutes.ago.change(usec: 0)

    project.record_first_event(runtime_label: "Rails 8.1 · Ruby 4.0", at: first)
    project.record_first_event(runtime_label: nil, at: Time.current)

    project.reload
    assert_equal first, project.first_event_at
    assert_equal "Rails 8.1 · Ruby 4.0", project.runtime_label
  end

  test "unresolved count" do
    assert_equal 3, projects(:storefront).unresolved_count
  end

  test "broadcast_changes_later enqueues a live update (slice G)" do
    assert_enqueued_with(job: BroadcastProjectChangesJob) { projects(:storefront).broadcast_changes_later }
  end

  private
    def with_constant(owner, name, value)
      original = owner.const_get(name)
      owner.send(:remove_const, name)
      owner.const_set(name, value)
      yield
    ensure
      owner.send(:remove_const, name)
      owner.const_set(name, original)
    end
end
