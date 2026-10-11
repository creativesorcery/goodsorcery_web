# Which environments an app's alert rules watch. "default" follows
# projects.default_environment (nil there means all environments), "all"
# watches every environment, "selected" watches alert_selected_environments.
class AddAlertScopeToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :alert_scope, :string, null: false, default: "default"
    add_column :projects, :alert_selected_environments, :string, array: true, null: false, default: []
  end
end
