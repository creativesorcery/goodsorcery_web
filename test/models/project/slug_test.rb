require "test_helper"

class Project::SlugTest < ActiveSupport::TestCase
  test "prefix from initials of several words" do
    assert_equal "MS", Project::Slug.prefix_for("marketing-site")
    assert_equal "FW", Project::Slug.prefix_for("fulfillment-workers")
  end

  test "prefix from the first three letters of a single word" do
    assert_equal "STO", Project::Slug.prefix_for("storefront")
    assert_equal "API", Project::Slug.prefix_for("api-2")
  end

  test "prefix is capped and has a fallback" do
    assert_equal "ABCDEF", Project::Slug.prefix_for("a-b-c-d-e-f-g")
    assert_equal "APP", Project::Slug.prefix_for("123")
  end

  test "unique slug falls back for names with no letters" do
    assert_equal "app", Project::Slug.new(accounts(:acme), "!!!").unique
  end

  test "like wildcards in names do not match other slugs" do
    accounts(:acme).projects.create!(name: "a_b")
    assert_equal "a_b-2", Project::Slug.new(accounts(:acme), "a_b").unique
  end
end
