# Good Sorcery Error Tracker

A self-hostable error tracker for Rails apps. Client libraries (such as the
`goodsorcery` Ruby gem) post errors to an ingest API. The dashboard groups them
into issues and updates live over Action Cable.

Built with Rails 8.1, Hotwire (Turbo and Stimulus), Action Cable, Postgres and
Tailwind.

- `docs/INGEST_API.md` describes the ingest API used by clients.
- `docs/ARCHITECTURE.md` describes the data model, ingest pipeline, privacy model and live updates.

## Requirements

- Ruby 4.0.7 (see `.ruby-version`)
- PostgreSQL (the `pg_trgm` extension is enabled by the migrations)
- Redis in production only (Sidekiq jobs, the cache store and Action Cable).
  Development needs no Redis: it uses the async job adapter, the memory cache
  store and the async Action Cable adapter.

## Setup

```sh
bin/setup --skip-server   # bundle install, then create and migrate the database
bin/rails db:seed         # demo data (skipped if it is already there)
```

`bin/setup` without `--skip-server` also starts the app.

Development and test use fixed, non-secret Active Record Encryption keys, so a
fresh clone runs without credentials.

## Running

```sh
bin/dev
```

This starts the Rails server and the Tailwind watcher (see `Procfile.dev`) on
http://localhost:3000. Set `PORT=3200 bin/dev` to use another port.

## Demo data and login

`bin/rails db:seed` creates the "Acme Labs" account with five projects
(storefront, billing-api, backoffice, fulfillment-workers and marketing-site),
issues, occurrences and activity. Sign in at http://localhost:3000 as:

- `philip@example.com` / `password` (owner)
- `jo@example.com` / `password` (member)

To start over, run `bin/rails db:reset`.

## Sending a test event

Each project environment has an ingest-only API key. To find one, open a
project's **Settings & setup** page and click **Reveal** next to the key.
You can also print one from the console:

```sh
bin/rails runner 'puts Project.find_by!(slug: "storefront").api_keys.find_by!(environment: "staging").token'
```

Send a minimal event with curl. Replace `YOUR_API_KEY` with the key:

```sh
curl -i -X POST http://localhost:3000/api/v1/events \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "level": "error",
    "transaction": "CheckoutsController#create",
    "exception": {
      "class": "NoMethodError",
      "message": "undefined method price_cents for nil",
      "backtrace": [
        { "file": "app/services/cart_total.rb", "line": 42, "method": "line_total", "in_app": true },
        { "file": "app/controllers/checkouts_controller.rb", "line": 14, "method": "create", "in_app": true }
      ]
    },
    "request": { "url": "https://shop.example.test/checkout", "method": "POST", "params": { "cart_id": 88123 } },
    "user": { "id": "5521", "email": "mara@example.com" },
    "breadcrumbs": [ { "category": "request", "message": "POST /checkout" } ]
  }'
```

A `202 Accepted` response with `{"id":"…"}` means the event was stored.
It is processed in the background, usually within a second. The issue then
appears on the project's issue list (live, with no reload) and on the issue
page. Only `exception.class` is required. See `docs/INGEST_API.md` for every
field and error response.

For a fuller sample event (code context, locals, headers, session,
breadcrumbs and tags), use the bundled script:

```sh
bin/send_test_event YOUR_API_KEY http://localhost:3000
EXCEPTION_CLASS=ArgumentError bin/send_test_event YOUR_API_KEY   # creates a separate issue
GZIP=1 bin/send_test_event YOUR_API_KEY                          # sends a gzipped body
```

Events with the same exception class and top in-app frame (file and method)
are grouped into one issue.

## Tests and checks

```sh
bin/rails test           # unit, controller and integration tests
bin/rails test:system    # browser tests (headless Chrome)
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
```

`bin/ci` runs setup, RuboCop, the security audits, `bin/rails test` and a
seed check (system tests run separately). To keep a separate test database (for example
when running several suites at once), set `TEST_DB_SUFFIX`:
`TEST_DB_SUFFIX=_mine bin/rails db:test:prepare test`.

## Production

- Run `bundle exec sidekiq -C config/sidekiq.yml` next to the web process.
- Set `REDIS_URL` (and optionally `REDIS_CACHE_URL`), `DATABASE_URL` (or
  `ERROR_TRACKER_DATABASE_PASSWORD`),
  `GOODSORCERY_PUBLIC_URL` (required; it also drives host authorization, with
  `GOODSORCERY_EXTRA_HOSTS` for extra hosts) and the
  `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`
  and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` keys (or put them in
  credentials).
- Schedule `bin/rails goodsorcery:prune` daily (retention) and
  `bin/rails goodsorcery:requeue_stale` every few minutes (recovers events
  accepted during a Redis outage).

Everything captured with an error (backtraces, code context, locals, request
params, headers, session, user, breadcrumbs and environment) may contain
personal data. It is stored encrypted at rest, and the server scrubs secrets
again on ingest. See the privacy section of `docs/INGEST_API.md`.
