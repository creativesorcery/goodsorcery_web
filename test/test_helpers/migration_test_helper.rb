# Builds a migration with its real version, as the migrator does. Without the
# version, StrongMigrations.start_after can't tell an old migration from a new
# one and checks it anyway. Require the migration file first.
module MigrationTestHelper
  def migration_for(migration_class)
    path = Dir[Rails.root.join("db/migrate/*_#{migration_class.name.underscore}.rb")].sole
    migration_class.new(migration_class.name, File.basename(path).to_i)
  end
end
