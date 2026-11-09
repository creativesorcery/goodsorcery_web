require "test_helper"
require Rails.root.join("db/migrate/20261010000002_map_retired_platforms_to_rails")

class MapRetiredPlatformsToRailsTest < ActiveSupport::TestCase
  include MigrationTestHelper

  test "rails_api and sidekiq apps become rails apps; ruby apps stay ruby" do
    set_platform(projects(:billing), "rails_api")
    set_platform(projects(:marketing), "sidekiq")

    ActiveRecord::Migration.suppress_messages { migration_for(MapRetiredPlatformsToRails).migrate(:up) }

    assert_equal %w[rails rails rails ruby], %i[storefront billing marketing umbrella_app].map { |name| projects(name).reload.platform }
  end

  private
    # Raw SQL: the retired values are no longer valid enum values.
    def set_platform(project, platform)
      Project.connection.execute(Project.sanitize_sql([ "UPDATE projects SET platform = ? WHERE id = ?", platform, project.id ]))
    end
end
