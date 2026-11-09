# Database migrations

Good Sorcery is self-hosted. Every install runs pending migrations by itself
when it boots (`bin/docker-entrypoint` runs `db:prepare`), and people upgrade
whenever they get round to it: from last week's release, or from one a year
old. Nobody is there to fix their database by hand. A migration that works on
our database but fails on theirs leaves their instance unable to boot.

So every migration must run cleanly on **any database created by any earlier
release**: hosted or self-hosted, empty or with millions of events, upgraded
one release at a time or many at once.

These rules apply to everyone who writes a migration: maintainers,
contributors and AI coding agents.

## The rules

### 1. A merged migration never changes

Once a migration is on `main`, databases have run it. Never edit, rename,
renumber or delete it. Rails records only the version, so an edited migration
never runs again anywhere it already ran, and installs end up with different
schemas. If it is wrong, fix it forward with a new migration.

Before merging, a migration may still change freely. Create it with
`bin/rails generate migration`, and make sure its version is newer than every
migration on `main` when it merges (rename it after rebasing if needed).

### 2. Migrations are self-contained

A migration must behave the same years from now, after the app code around it
has changed. Inside a migration, never use:

- app models, concerns or plain Ruby objects (`Project`, `Entitlements`, …);
- app constants, `config/*.yml`, `Rails.configuration.x.*` or `ENV`;
- validations, callbacks or anything else that runs app code.

Change data with SQL through `execute`, quoting every value with
`connection.quote`. If you need Active Record, define a bare model inside the
migration class:

```ruby
class BackfillProjectsDefaultEnvironment < ActiveRecord::Migration[8.1]
  class MigrationProject < ActiveRecord::Base
    self.table_name = "projects"
  end

  def up
    MigrationProject.where(default_environment: nil).update_all(default_environment: "production")
  end
end
```

Copy any values the migration needs (a list of kinds, a default) into the
migration itself, even if the app has the same constant.

### 3. Hosted and self-hosted run the same migrations

`GOODSORCERY_HOSTED` is not known to migrations, and must not be. A data
change written for the hosted service also runs on every self-hosted
database, so it has to be correct there too. Expect any data an earlier
release allowed: `NULL`s, old enum values, empty accounts, and rows created
before a validation existed.

### 4. Expand, then contract

The previous release keeps running while migrations run, and a rollback
(`bin/kamal rollback`) runs previous code against the new schema without
running migrations backwards. Every migration must keep the previous release
working:

- **Add** columns as nullable or with a default. Make a column `NOT NULL`
  only once every row has a value and no running release writes `NULL`.
- **Remove** a column in two releases: first stop using it and list it in the
  model's `ignored_columns`, then drop it in a later release.
- **Rename** a column or table in steps: add the new one, write to both,
  backfill, switch reads, then drop the old one in a later release. Often it
  is simpler to keep the old name and alias it in the model (see the APM
  `ruby_ms` columns in `CLAUDE.md`).
- **Change a column's type** the same way, through a new column. In-place
  type changes rewrite the table and break the running release.

### 5. Migrations are fast and don't block ingest

Self-hosted databases can be far bigger than ours, and ingest writes all the
time. A migration that holds a lock for minutes stalls ingest and can make the
deploy's health check give up. `strong_migrations` (below) stops the common
mistakes. In short:

- Add indexes with `algorithm: :concurrently` in a migration with
  `disable_ddl_transaction!`, and remove them the same way.
- Add foreign keys and check constraints with `validate: false`, then
  validate them in a separate migration.
- Make a column `NOT NULL` by adding a validated check constraint first.
- **No bulk data changes on tables that grow with traffic** (events,
  occurrences, issues, rollups, traces, uptime checks, deliveries, activity
  logs). A migration may change the schema; a large backfill or cleanup goes
  in a `goodsorcery:` rake task or a background job that works in batches,
  and the release notes say to run it. A one-statement fix on a small table
  (accounts, users, projects, alert rules) is fine in a migration.

### 6. Reversible where possible

Write `change`, or `up` and `down`, so developers can roll back and try again.
A data change that can't be undone uses `up_only` or raises
`ActiveRecord::IrreversibleMigration` in `down`. Production never runs `down`:
the way back from a bad upgrade is restoring the backup taken before it.

### 7. Postgres compatibility

Support Postgres 14 and newer (`StrongMigrations.target_version`). Extensions
must ship with standard Postgres (contrib, like `pg_trgm`) and be added with
`enable_extension`. A new extension needs a release note, since managed
Postgres services may require turning it on first.

### 8. Say what upgraders need to know

Note in the pull request (and later the changelog) any migration that needs a
manual step, takes noticeable time on a large database, or comes with a rake
task to run.

## strong_migrations

The [`strong_migrations`](https://github.com/ankane/strong_migrations) gem
checks each new migration as it runs and stops with an explanation and a safe
alternative when an operation could lock or rewrite a table. Settings are in
`config/initializers/strong_migrations.rb`:

- `start_after`: older migrations shipped before the checks and are skipped.
- `target_version = 14`: checks assume the oldest supported Postgres.
- `lock_timeout` 10 seconds with 3 retries: a migration fails rather than
  queue behind ingest traffic. The previous release keeps running and the
  next boot tries again.
- `statement_timeout` 1 hour.

If a check stops your migration, follow its suggestion. Use `safety_assured`
only when you are sure the operation is safe on any install (for example, a
table no release has written to yet), and add a comment saying why:

```ruby
# Safe: uptime_tags was created in the previous migration and is still empty.
safety_assured { change_column :uptime_tags, :name, :text }
```

`execute` always stops, because the gem can't see inside SQL. Check the
statement against rules 4 and 5, then wrap it the same way:

```ruby
# Safe: projects has one row per app, and the UPDATE touches only the
# retired platform values.
safety_assured { execute "UPDATE projects SET platform = 'rails' WHERE platform = 'sidekiq'" }
```

Migration tests must build the migration with `migration_for(TheMigration)`
(`test/test_helpers/migration_test_helper.rb`), not `TheMigration.new`, so
the checks know its version.

## Before you open a pull request

```sh
bin/rails db:migrate        # runs the strong_migrations checks, updates db/schema.rb
bin/rails db:rollback       # if reversible: does down work?
bin/rails db:migrate        # and up again
bin/ci
```

Run it against a development database that has data in it (`bin/rails
db:seed` before you add the migration), not only an empty one: data
migrations fail on rows, not on empty tables.

Commit `db/schema.rb` together with the migration. Fresh installs load
`schema.rb` rather than running every migration, so it must match.

## Deleting old migrations

Don't. Old migrations are how a year-old install catches up. Squashing them
will only happen at a major release that names a required upgrade stop
("upgrade to the last 1.x release first"), with a check that refuses to
migrate a database older than that stop.
