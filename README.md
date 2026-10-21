# Good Sorcery Error Tracker

A self-hostable error tracker for Rails apps. Client libraries (such as the
upcoming `goodsorcery` Ruby gem) post errors to an ingest API. The dashboard
groups them into issues and updates live over Action Cable.

Built with Rails 8.1, Hotwire (Turbo and Stimulus), Action Cable, Postgres and
Tailwind. No single-page JavaScript framework, and no Solid Queue, Solid Cache
or Solid Cable.

- `docs/INGEST_API.md` documents the ingest API payload for client authors.
- `docs/ARCHITECTURE.md` describes the data model, ingest pipeline, privacy model and live updates.
- `docs/DEPLOYMENT.md` covers the production deploy: Kamal, GitHub Actions and Cloudflare Tunnel.

## Requirements

| Tool | Version | Needed for | Notes |
|---|---|---|---|
| Ruby | 4.0.7 | everything | Pinned in `.ruby-version`. With rbenv: `rbenv install 4.0.7` (rbenv picks it up from `.ruby-version`). |
| Bundler | ships with Ruby | everything | `bin/setup` runs `bundle install`. |
| PostgreSQL | 14 or newer recommended | everything | Migrations enable `pg_trgm` (trigram search). The dev/test role is your OS user over the local socket. |
| Redis | 6 or newer | production only | Sidekiq jobs, the cache store and Action Cable. Development and test need no Redis. |
| Google Chrome | current | system tests only | `bin/rails test:system` drives headless Chrome through Selenium. |

Node.js is **not** needed. Tailwind runs through the standalone binary in the
`tailwindcss-ruby` gem, and JavaScript is served with importmaps.

On macOS with Homebrew:

```sh
brew install rbenv postgresql@16 redis
brew services start postgresql@16
rbenv install 4.0.7
```

## Development setup

```sh
bin/setup --skip-server   # bundle install, create and migrate the dev and test databases, clear logs/tmp
bin/rails db:seed         # demo data (does nothing if the demo user already exists)
bin/dev                   # Rails server + Tailwind watcher (Procfile.dev) on http://localhost:3000
```

`bin/setup` without `--skip-server` runs `bin/dev` at the end.
`bin/setup --reset` also resets the database. Use `PORT=3200 bin/dev` for
another port.

Development needs **no secrets, credentials or environment variables**:

- Active Record Encryption uses fixed, non-secret keys in `config/environments/development.rb` and `test.rb`.
- Jobs run on the `:async` adapter, the cache is the in-process memory store,
  and Action Cable uses the `async` adapter. So no Sidekiq or Redis process is needed.
- Fragment caching is off by default. `bin/rails dev:cache` toggles it.

To set optional variables locally (sign-up flags, a test-event API key and so on),
`cp .env.example .env` and uncomment what you need. `.env` is git-ignored and is
loaded in development only, never in test or production.

### Demo login

`bin/rails db:seed` creates the "Acme Labs" account with five projects
(storefront, billing-api, backoffice, fulfillment-workers and marketing-site,
which is still "Listening…"), plus issues, occurrences and activity:

- `philip@example.com` / `password` (owner)
- `jo@example.com` / `password` (member)

To start over: `bin/rails db:reset`.

### Sending a test event

Each project environment has an ingest-only API key. Open a project's
**Settings & setup** page and click **Reveal**, or print one:

```sh
bin/rails runner 'puts Project.find_by!(slug: "storefront").api_keys.find_by!(environment: "staging").token'
```

Send a minimal event with curl:

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

`202 Accepted` with `{"id":"…"}` means the event was stored. A background job
processes it, usually within a second. The issue then appears on the project's
issue list without a reload. Only `exception.class` is required. Events with
the same exception class and top in-app frame (file and method) group into one
issue. See `docs/INGEST_API.md` for every field and error code.

For a fuller sample event (code context, locals, headers, session, breadcrumbs
and tags), use the bundled script:

```sh
bin/send_test_event YOUR_API_KEY http://localhost:3000
EXCEPTION_CLASS=ArgumentError bin/send_test_event YOUR_API_KEY   # a separate issue
GZIP=1 bin/send_test_event YOUR_API_KEY                          # gzipped body
JOB=1 bin/send_test_event YOUR_API_KEY                           # an error from a background job (Job tab)
```

Script variables: `GOODSORCERY_API_KEY` and `GOODSORCERY_HOST` (default
`http://localhost:3000`) replace the arguments. `EVENT_ID` sets the event id
(the same id twice is counted once), `EXCEPTION_CLASS` sets the class, and
`GZIP=1` compresses the body. Test events overwrite the project's runtime label
with your local Ruby/Rails versions, and they use up issue numbers.

## Tests and linters

```sh
bin/rails test           # unit, controller, job and integration tests
bin/rails test:system    # browser tests (headless Chrome)
bin/rubocop              # style, plus the 20-line method limit and nesting limit
bin/brakeman --no-pager  # static security analysis
bin/bundler-audit        # gem CVEs
bin/importmap audit      # JS package CVEs
bin/ci                   # setup, RuboCop, the audits, Brakeman, tests and a seed check
```

`bin/ci` doesn't run the system tests. To run suites side by side with
separate test databases, set `TEST_DB_SUFFIX`; `config/database.yml` appends it
to the test database name:

```sh
TEST_DB_SUFFIX=_mine bin/rails db:test:prepare test
```

## Production

### Processes

| Process | Command | Notes |
|---|---|---|
| Web | `./bin/thrust ./bin/rails server` (the Docker image's default) | Puma behind Thruster. `bin/docker-entrypoint` runs `bin/rails db:prepare` before the server starts. |
| Jobs | `bundle exec sidekiq -C config/sidekiq.yml` | Required. Ingest is accepted by the web process but **processed** by Sidekiq. Queues, by weight: `ingest` (3), `default` (2), `mailers` (1). Also runs the scheduled jobs. |
| Redis | Kamal accessory, or external | Sidekiq, the cache store and Action Cable. |
| Postgres | Kamal accessory, or external | |

### Scheduled tasks

sidekiq-cron runs these inside the Sidekiq process, from `config/schedule.yml`
(times in UTC). Development and test don't run Sidekiq, so nothing is scheduled
there. Each has a rake task for running it by hand.

| Job | Schedule | Rake task | What it does |
|---|---|---|---|
| `PruneExpiredDataJob` | daily, 03:17 | `bin/rails goodsorcery:prune` | Deletes occurrences older than each project's `retention_days` (default and maximum 30), hourly issue counts older than 31 days and project counts older than 90 days, stale personal data on issues past retention, and inbound events never processed within a day. |
| `RequeueStaleEventsJob` | every 10 minutes | `bin/rails goodsorcery:requeue_stale` | Re-enqueues inbound events accepted more than 10 minutes ago but never processed (for example after a Redis outage). |

### Environment variables

Every variable below is read by the app's code or config.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `SECRET_KEY_BASE` | **yes** | none (**production refuses to boot without it**) | Signs and encrypts cookies and derives the `PrivateDigest` HMAC key. See "Secrets". |
| `GOODSORCERY_PUBLIC_URL` | **yes** | none (**production refuses to boot without it**) | This instance's public URL, e.g. `https://errors.example.com`. Sets the host and protocol of email links (password resets) and the allowed hosts (`config.hosts`). The setup page's install snippet also shows it as the endpoint. |
| `GOODSORCERY_EXTRA_HOSTS` | no | none | Comma-separated extra hostnames to accept besides the public URL's host. `/up` answers on any host. |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | **yes** | none | Encrypts captured error data, raw inbound events, API key tokens, tag values and notes. |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | **yes** | none | Deterministic encryption key. |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | **yes** | none | Key derivation salt. |
| `DATABASE_URL` | yes, unless you use the `database.yml` defaults | none | Full Postgres URL. Rails merges it over `config/database.yml`. |
| `DB_HOST` | if not using `DATABASE_URL` | the local socket | Postgres host for the `goodsorcery_web_production` database. The Kamal config sets it to the `db` accessory. |
| `GOODSORCERY_WEB_DATABASE_PASSWORD` | if not using `DATABASE_URL` | none | Password for the `goodsorcery_web` role on the `goodsorcery_web_production` database. |
| `REDIS_URL` | **yes** | `redis://localhost:6379/1` (Action Cable), `redis://localhost:6379/0` (cache), Sidekiq's own default | Sidekiq, Action Cable and, unless overridden, the cache store. |
| `REDIS_CACHE_URL` | no | `REDIS_URL` | A separate Redis for the cache store (rate limits, quota and key-lookup caches, fragments). |
| `SIDEKIQ_CONCURRENCY` | no | `5` | Sidekiq threads per process. Keep `RAILS_MAX_THREADS` (the database pool) at least this high in the Sidekiq process. |
| `RAILS_MAX_THREADS` | no | `3` Puma threads; database pool `5` | Puma threads per worker and the Active Record pool size. |
| `WEB_CONCURRENCY` | no | Puma's default (1) | Puma worker processes. `auto` uses one per CPU. |
| `PORT` | no | `3000` | Puma port. Thruster serves on 80 in the Docker image. |
| `PIDFILE` | no | none | Puma pid file path. |
| `RAILS_LOG_LEVEL` | no | `info` | Keep `info`. `debug` logs SQL, which includes the (redacted) issue titles. |
| `GOODSORCERY_ENABLE_SIGNUPS` | no | sign-up is open only until the first account exists | `1` keeps public sign-up open (hosted service). |
| `GOODSORCERY_DISABLE_SIGNUPS` | no | none | `1` closes sign-up completely, even before the first account exists. It overrides `ENABLE`. |
| `GOODSORCERY_HOSTED` | no | `false` | `true` marks this as the managed hosting service: the sidebar shows "Hosted" instead of "Self-hosted", and the setup page's install snippets drop the `config.endpoint` / `GOODSORCERY_ENDPOINT` line. |
| `POSTMARK_API_TOKEN` | to send mail through Postmark | none | A Postmark **server** API token. When set, mail (password resets) is delivered through Postmark's API. Without it, configure SMTP instead (see "Email"). |
| `GOODSORCERY_API_KEY` | no | none | Ingest key the `goodsorcery` gem uses to report this app's own errors (`config/initializers/goodsorcery.rb`). Unset, nothing is sent. |
| `GOODSORCERY_MAIL_FROM` | no | `Good Sorcery <no-reply@HOST>`, with HOST taken from the public URL | Sender address for password-reset emails. |
| `GOODSORCERY_DOCS_URL` | no | the project's GitHub `docs/` folder | Target of the sidebar's Docs link. |
| `SECRET_KEY_BASE_DUMMY` | build only | none | Set by the Dockerfile during `assets:precompile`, so the build needs no secrets or public URL. Never set it at runtime. |

Account event quotas aren't environment variables. Each account has a
`monthly_event_quota` column (`nil` means unlimited, the self-hosted default).
Ingest returns `429 quota_exceeded` once an account reaches it.

### Secrets

Production reads every secret from environment variables. The repo has no
`config/credentials.yml.enc` or `config/master.key` (both are git-ignored), so
there is nothing to decrypt and nothing to share.

Generate the four secrets once, store them in a password manager, and back
them up separately from the database:

```sh
bin/rails secret                # SECRET_KEY_BASE
bin/rails db:encryption:init    # prints the three ACTIVE_RECORD_ENCRYPTION_* values
```

`db:encryption:init` prints the keys as YAML (`primary_key`, `deterministic_key`,
`key_derivation_salt`). Set them as `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
`ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` and
`ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`.

**`SECRET_KEY_BASE`** signs and encrypts session cookies and signed Action Cable
stream names. It also derives the HMAC key for the affected-user and tag digests
(`PrivateDigest`), so **changing it logs everyone out and breaks matching
against existing user and tag digests**.

**Active Record Encryption keys.** Production boots without them, but every
ingest and every captured-data read then fails, so nothing is ever stored in
plaintext. **Losing these keys makes all stored error data, API key tokens and
notes unreadable.** `support_unencrypted_data` is off, so plaintext rows are
rejected rather than read.

**Email.** Password resets and sign-up confirmation emails need outgoing mail
(the first account's owner starts confirmed, so a new instance works before
mail is set up; later sign-ups can't add apps until they confirm). Set `POSTMARK_API_TOKEN` to
send through Postmark, and verify the sender's domain in Postmark (the sender
is `GOODSORCERY_MAIL_FROM`, by default `no-reply@` the public URL's host). To
use another provider, leave the token unset, uncomment
`config.action_mailer.smtp_settings` in `config/environments/production.rb`,
set your SMTP server, and provide `SMTP_USERNAME` and `SMTP_PASSWORD`.

### Deploying with Kamal

`config/deploy.yml` deploys everything to one server: web, Sidekiq, Postgres,
Redis and a Cloudflare Tunnel, so the server publishes no HTTP ports. It holds
no hosts or secrets; Kamal reads them from the environment. CI deploys every
push to `main` after the checks pass. See `docs/DEPLOYMENT.md` for the server,
Cloudflare and GitHub setup.

Plain Docker works too:
`docker run -e SECRET_KEY_BASE=... -e ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=... -e ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=... -e ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=... -e GOODSORCERY_PUBLIC_URL=... -e REDIS_URL=... -e DATABASE_URL=... goodsorcery_web`.
Run a second container from the same image with `bundle exec sidekiq -C config/sidekiq.yml`.

## Privacy

Everything captured with an error may contain personal data: backtraces, code
context, locals, request params, headers, session, user, breadcrumbs and
environment. It is encrypted at rest. The server scrubs secrets again on
ingest, and user identities are stored only as HMAC digests. Only an id goes
through Redis/Sidekiq, never the payload, and dashboard pages send
`Cache-Control: no-store`. See `docs/ARCHITECTURE.md` and the privacy section
of `docs/INGEST_API.md`.

## Troubleshooting

- **`PublicUrl::Missing: Set GOODSORCERY_PUBLIC_URL ...` at production boot.** Set it to an `http(s)://` URL with a host.
- **`ActiveRecord::Encryption::Errors::Configuration` / `Decryption` errors.** The encryption keys are missing or changed. See "Secrets".
- **``Missing `secret_key_base` for 'production' environment`` at boot.** Set `SECRET_KEY_BASE` (the message's `credentials:edit` hint doesn't apply; this app doesn't use credentials).
- **"Blocked hosts" error page in production.** The request's host isn't the public URL's host. Add it to `GOODSORCERY_EXTRA_HOSTS`.
- **Events return 202 but never appear (production).** Sidekiq isn't running, or it can't reach `REDIS_URL`. Once fixed, run `bin/rails goodsorcery:requeue_stale`.
- **Events return 202 but never appear (development).** Check `log/development.log` for job errors. The async adapter runs jobs inside the server process.
- **401 / 413 / 415 / 422 / 429 from ingest.** See the error table in `docs/INGEST_API.md`. A rotated key is rejected right away.
- **`PG::ConnectionBad` or "database does not exist".** Start Postgres (`brew services start postgresql@16`), then run `bin/rails db:prepare`.
- **Migration fails with `extension "pg_trgm" is not available`.** Install the Postgres contrib package (Homebrew's postgresql includes it).
- **Styles missing or stale.** Run `bin/dev` (it starts the Tailwind watcher), or `bin/rails tailwindcss:build` once.
- **System tests hang or fail to start.** Install or update Google Chrome. Selenium Manager fetches a matching chromedriver.
- **Sign-up page redirects to sign-in.** Sign-up closes once the first account exists. Set `GOODSORCERY_ENABLE_SIGNUPS=1` to keep it open.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
Please report security vulnerabilities privately, as described in
[SECURITY.md](SECURITY.md), not in a public issue.

## License

Good Sorcery is released under the [MIT License](LICENSE).
