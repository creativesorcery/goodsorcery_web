# The platform choice is now "Ruby on Rails" or "Ruby"; Rails API and Sidekiq
# apps become Rails apps. Plain SQL, so the migration never depends on the
# Project model or its enum. Down is a no-op: the old value is not kept.
class MapRetiredPlatformsToRails < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE projects SET platform = 'rails' WHERE platform IN ('rails_api', 'sidekiq')"
  end

  def down
  end
end
