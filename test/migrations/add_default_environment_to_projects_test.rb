require "test_helper"
require Rails.root.join("db/migrate/20261010000003_add_default_environment_to_projects")

# Postgres DDL is transactional, so the test's rollback restores the column.
class AddDefaultEnvironmentToProjectsTest < ActiveSupport::TestCase
  teardown { Project.reset_column_information }

  test "apps with a production key start on production; the others on all environments" do
    migration = AddDefaultEnvironmentToProjects.new.tap { |m| m.verbose = false }
    migration.migrate(:down)
    migration.migrate(:up)
    Project.reset_column_information

    assert_equal "production", projects(:storefront).reload.default_environment
    assert_equal "production", projects(:marketing).reload.default_environment
    assert_nil projects(:billing).reload.default_environment, "billing has no production key"
  end
end
