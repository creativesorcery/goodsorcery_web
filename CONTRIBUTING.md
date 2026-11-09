# Contributing

Thanks for helping out. Bug reports, fixes and documentation improvements are
all welcome. For a new feature or a large change, please open an issue first so
we can agree on the approach before you put in the work.

Security problems are the exception: report them privately as described in
[SECURITY.md](SECURITY.md).

## Getting set up

Follow "Requirements" and "Development setup" in [README.md](README.md).
Development needs no secrets: `bin/setup --skip-server && bin/rails db:seed`,
then `bin/dev`.

## Before opening a pull request

Run the full check and the system tests:

```sh
bin/ci                   # setup, RuboCop, the audits, Brakeman, tests and a seed check
bin/rails test:system    # browser tests (headless Chrome)
```

## Code style

- Rails conventions with Hotwire (Turbo and Stimulus) and Action Cable. No
  single-page JavaScript framework.
- Prefer rich models, concerns and plain Ruby objects with descriptive, domain
  method names. No service objects with a single `call` method.
- Keep methods short (RuboCop enforces a 20-line limit) and conditionals shallow.
- Add tests for every change, including authorization tests for new controller
  actions.
- Treat everything captured with an error as sensitive. Never put captured data
  in job arguments, Redis, the cache, logs, broadcasts or exception messages.
  See `docs/ARCHITECTURE.md` before changing the ingest path or encryption.

## Database migrations

Self-hosted installs run migrations by themselves when they boot, often
jumping many releases at once, so a migration must work on any database an
earlier release created. Read [docs/MIGRATIONS.md](docs/MIGRATIONS.md) before
writing one. The short version:

- Never edit, rename or delete a migration once it is on `main`. Fix forward.
- No app code in migrations: no models, constants, config or `ENV`. Use SQL,
  or a bare model defined inside the migration.
- The same migrations run hosted and self-hosted, on empty and huge databases.
- Expand, then contract: the previous release must keep working on the new
  schema. Columns are dropped one release after the code stops using them.
- Keep migrations fast. `strong_migrations` stops locking and rewriting
  operations; large backfills go in a rake task or job, not a migration.
- `safety_assured` only with a comment explaining why it is safe on any
  install.
- Commit `db/schema.rb` with the migration.

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
