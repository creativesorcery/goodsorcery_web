require "test_helper"
require Rails.root.join("db/migrate/20261107000002_fit_project_retention_to_choices")

class FitProjectRetentionToChoicesTest < ActiveSupport::TestCase
  test "up moves each app to the nearest of 30, 60 and 90 days, ties to the longer one" do
    expected = { 1 => 30, 29 => 30, 30 => 30, 44 => 30, 45 => 60, 46 => 60, 60 => 60, 74 => 60, 75 => 90, 90 => 90, 400 => 90 }
    projects = expected.keys.map { |days| add_project(days) }

    ActiveRecord::Migration.suppress_messages { FitProjectRetentionToChoices.new.migrate(:up) }

    assert_equal expected.values, projects.map { it.reload.retention_days }
  end

  test "down changes nothing" do
    project = add_project(30)
    ActiveRecord::Migration.suppress_messages { FitProjectRetentionToChoices.new.migrate(:down) }
    assert_equal 30, project.reload.retention_days
  end

  private
    def add_project(days)
      project = with_hosted_mode(false) { accounts(:umbrella).projects.create!(name: "Retention #{days}") }
      project.tap { it.update_column(:retention_days, days) }
    end
end
