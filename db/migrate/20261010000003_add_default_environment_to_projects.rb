# The environment an app's issue list opens on; nil means all environments.
# Existing apps that have a production key start on production. Plain SQL,
# so the migration never depends on the Project model.
class AddDefaultEnvironmentToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :default_environment, :string

    execute <<~SQL.squish
      UPDATE projects SET default_environment = 'production'
      WHERE EXISTS (SELECT 1 FROM api_keys WHERE api_keys.project_id = projects.id AND api_keys.environment = 'production')
    SQL
  end

  def down
    remove_column :projects, :default_environment
  end
end
