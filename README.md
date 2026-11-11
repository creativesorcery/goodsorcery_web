# Good Sorcery Error Tracker

Good Sorcery is an open-source error tracker, performance monitor and uptime
checker. Your apps report exceptions and performance data through small client
libraries (Ruby and Rust today) to a language-neutral ingest API. The server
groups errors into issues, shows backtraces and request data, tracks slow
endpoints and traces, checks your URLs, and alerts you by email or Slack. The
dashboard updates live. Use it hosted at
[app.goodsorcery.com](https://app.goodsorcery.com), or run it yourself under
the MIT License.

Built with Rails 8.1, Hotwire (Turbo and Stimulus), Action Cable, Postgres,
Sidekiq, Redis and Tailwind. No single-page JavaScript framework and no Node.js.

## Features

- **Error tracking:** an ingest API for single events and batches, issues
  grouped by exception and code location, search with filter chips, triage
  (resolve, ignore, reopen, assign, notes, bulk actions), issue pages with
  app-first backtraces, breadcrumbs, request, params, headers, session, job and
  environment tabs, tag breakdowns and affected users. Live updates over Action
  Cable.
- **Performance monitoring (APM):** per-endpoint and per-job response times
  (average, p75, p90, p95, p99), where the time goes (database, HTTP,
  rendering, app code), and slow request traces with N+1 query detection.
- **Uptime monitors:** HTTP checks every 1, 5, 10 or 60 minutes, with uptime
  history, incidents and down and recovered alerts.
- **Alerts:** per-app email rules (new issue, regression, reached production,
  still happening, daily digest) with environment scope and per-person
  switches, plus one Slack channel per app through an incoming webhook.
- **MCP server:** AI clients (Claude Code, Codex, Cursor, VS Code) can search,
  read and triage issues with personal access tokens ([docs/MCP.md](docs/MCP.md)).
- **Privacy first:** everything captured with an error is encrypted at rest,
  scrubbed again on ingest, and never put in Redis, job arguments, the cache or
  logs. User identities are stored only as HMAC digests.
- **Staff area:** `/staff` lists every account and user on the instance, for
  the people who run it.

## Use the hosted version

The quickest start is the hosted service at
**[app.goodsorcery.com](https://app.goodsorcery.com)**: sign up, click
**Add a new app**, and follow the app's **Setup** page, which shows your
ingest key and the install snippet for your language. The client libraries
send to app.goodsorcery.com by default, so no endpoint setting is needed.

## Self-host

Good Sorcery runs as one Docker image (the web process and a Sidekiq process)
with Postgres and Redis. `config/deploy.yml` deploys all of it to a single
server with [Kamal](https://kamal-deploy.org), and plain Docker works too. See
[Production](#production) below and [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).
When self-hosting, point the client libraries at your instance with
`GOODSORCERY_ENDPOINT` (the Setup page's snippets include it).

## Client libraries

| Language | Repository | Install |
|---|---|---|
| Ruby (Rails, Rack, plain Ruby) | [creativesorcery/goodsorcery-ruby](https://github.com/creativesorcery/goodsorcery-ruby) | `bundle add goodsorcery` (or `gem install goodsorcery`) |
| Rust (with an axum layer) | [creativesorcery/goodsorcery-rust](https://github.com/creativesorcery/goodsorcery-rust) | `cargo add goodsorcery` |

Both read `GOODSORCERY_API_KEY` and, for self-hosted servers,
`GOODSORCERY_ENDPOINT`. Writing a client for another language? The wire format
is documented in [docs/INGEST_API.md](docs/INGEST_API.md).

## Documentation

- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md): production deploy with Kamal,
  GitHub Actions and Cloudflare Tunnel.
- [docs/INGEST_API.md](docs/INGEST_API.md): the ingest API payload, limits and
  error codes, for client authors.
- [docs/MCP.md](docs/MCP.md): connecting AI clients to the MCP server.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): design notes for contributors
  (data model, ingest pipeline, privacy model, live updates).
- [docs/MIGRATIONS.md](docs/MIGRATIONS.md): rules for database migrations.

## Requirements

| Tool | Version | Needed for | Notes |
|---|---|---|---|
| Ruby | 4.0.7 | everything | Pinned in `.ruby-version`. With rbenv: `rbenv install 4.0.7`. |
| Bundler | ships with Ruby | everything | `bin/setup` runs `bundle install`. |
| PostgreSQL | 14 or newer (the Kamal setup uses 18) | everything | Migrations enable the `pg_trgm` extension (trigram search), which some distributions ship in a separate contrib package. |
| Redis | 7.0 or newer (or Valkey 7.2+) | production only | Sidekiq jobs, the cache store and Action Cable. Sidekiq 8 refuses older versions. Development and test need no Redis. |
| Google Chrome | current | system tests only | `bin/rails test:system` drives headless Chrome through Selenium. |

Node.js is **not** needed. Tailwind runs through the standalone binary in the
`tailwindcss-ruby` gem, and JavaScript is served with importmaps.

In development and test, Rails connects to Postgres over the local socket as
your OS user (no password). On macOS with Homebrew:

```sh
brew install rbenv postgresql@16
brew services start postgresql@16
rbenv install 4.0.7
```

On Debian or Ubuntu (install Ruby 4.0.7 with rbenv, mise or asdf):

```sh
sudo apt install postgresql postgresql-contrib libpq-dev build-essential libyaml-dev
sudo -u postgres createuser --superuser "$USER"   # a role for your OS user
```

Alternatively, set `DATABASE_URL` (for example
`postgres://user:pass@localhost/goodsorcery_web_development`) in `.env`.

## Local development

```sh
git clone https://github.com/creativesorcery/goodsorcery_web.git
cd goodsorcery_web
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

`bin/rails db:seed` creates the "Acme Labs" account with five apps
(storefront, billing-api, backoffice, fulfillment-workers and marketing-site,
which is still "Listening…"), plus issues, occurrences, uptime monitors, a week
of performance data and activity. Sign in at http://localhost:3000 with:

- `alex@example.com` / `password` (Alex Rivera, the account owner)
- `jo@example.com` / `password` (Jo Martin, a member)

Every account member has the same full rights; see [Accounts and
members](#accounts-and-members). To start over: `bin/rails db:reset`.

### Sending a test event

Each app environment has an ingest-only API key. Open an app's
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
processes it, usually within a second. The issue then appears on the app's
issue list without a reload. Only `exception.class` is required. Events with
the same exception class and top in-app frame (file and method) group into one
issue. See [docs/INGEST_API.md](docs/INGEST_API.md) for every field and error code.

For a fuller sample event (code context, locals, headers, session, breadcrumbs
and tags), use the bundled script:

```sh
bin/send_test_event YOUR_API_KEY http://localhost:3000
EXCEPTION_CLASS=ArgumentError bin/send_test_event YOUR_API_KEY   # a separate issue
GZIP=1 bin/send_test_event YOUR_API_KEY                          # gzipped body
BATCH=25 bin/send_test_event YOUR_API_KEY                        # 25 events in one batch request
JOB=1 bin/send_test_event YOUR_API_KEY                           # an error from a background job (Job tab)
```

Script variables: `GOODSORCERY_API_KEY` and `GOODSORCERY_ENDPOINT` (the same
variable the clients read; `GOODSORCERY_HOST` is still accepted as a fallback;
default `http://localhost:3000`) replace the arguments. `EVENT_ID` sets the
event id (the same id twice is counted once). Test events overwrite the app's
runtime label with your local Ruby/Rails versions, and they use up issue numbers.

For performance monitoring, `bin/send_test_apm` posts one minute of metrics
(two endpoints and a job) and a slow checkout trace with an N+1 query. It reads
the same variables:

```sh
bin/send_test_apm YOUR_API_KEY http://localhost:3000
GZIP=1 MINUTES=3 bin/send_test_apm YOUR_API_KEY      # gzipped, three closed minutes
BATCH_ID=0192f7b0-1a2b-7c3d-8e4f-5a6b7c8d9e0f bin/send_test_apm YOUR_API_KEY   # twice: counted once
SLOW=1 bin/send_test_apm YOUR_API_KEY                # ten times slower (Slower after an hour of normal data)
TRACES=0 bin/send_test_apm YOUR_API_KEY              # metrics only
```

### Trying the MCP server locally

Create a token at http://localhost:3000/access_tokens (user menu › **MCP
server**) and run:

```sh
curl -s http://localhost:3000/mcp -H "Authorization: Bearer gs_pat_..." \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}'
```

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
| Web | `./bin/thrust ./bin/rails server` (the Docker image's default) | Puma behind Thruster on port 80. `bin/docker-entrypoint` runs `bin/rails db:prepare` (create and migrate) before the server starts. |
| Jobs | `bundle exec sidekiq -C config/sidekiq.yml` | **Required.** Ingest is accepted by the web process but **processed** by Sidekiq. Queues, by weight: `ingest` (3), `apm` (2, performance data), `default` (2, includes the uptime scheduler), `alerts` (2), `uptime` (2, the checks), `mailers` (1). It also runs the scheduled jobs. A process that leaves a queue out silently stops that work. |
| Redis | Kamal accessory, or external | 7.0 or newer. Sidekiq, the cache store and Action Cable. |
| Postgres | Kamal accessory, or external | 14 or newer, with `pg_trgm` available. |

Production must be served over **HTTPS**: the app sets `assume_ssl` and
`force_ssl`, so its session and CSRF cookies are `Secure` and browsers drop
them over plain HTTP (sign-in then fails with an authenticity-token error or a
redirect loop). Terminate TLS in front of the app (Cloudflare, a load balancer,
a reverse proxy) or let Thruster do it (see "Plain Docker").

### Scheduled tasks

sidekiq-cron runs these inside the Sidekiq process, from `config/schedule.yml`
(times in UTC), so no host cron is needed. Development and test don't run
Sidekiq, so nothing is scheduled there.

| Job | Schedule | Rake task | What it does |
|---|---|---|---|
| `PruneExpiredDataJob` | daily, 03:17 | `bin/rails goodsorcery:prune` | Deletes occurrences older than each app's `retention_days` (30, 60 or 90; default 30), hourly issue counts older than 31 days and app counts older than 90 days, stale personal data on issues past retention, inbound events never processed within a day, old alert deliveries, uptime history and performance data past its retention. |
| `RequeueStaleEventsJob` | every 10 minutes | `bin/rails goodsorcery:requeue_stale` | Re-enqueues inbound events accepted more than 10 minutes ago but never processed (for example after a Redis outage). |
| `CapStoredOccurrencesJob` | every 5 minutes | `bin/rails goodsorcery:cap_occurrences` | Holds each app to 3,000 stored occurrences: the issues with the most stored copies lose their oldest first, and every issue keeps at least its newest. Events are still counted. Each issue also keeps at most its newest 100 (`TrimOccurrencesJob`, every 50 events). |
| `CheckStillHappeningJob` | every 5 minutes | none | Still-happening alerts for issues over their app's threshold in the last hour. |
| `SendDailyDigestsJob` | hourly, :00 | none | Daily digests, sent at 09:00 in each recipient's time zone. |
| `SendAlertSummariesJob` | hourly, :02 | none | One "and N more alerts" email per person for alerts over the hourly cap. |
| `TrimApmTracesJob` | hourly, :03 | none | Keeps the 3 slowest performance traces per transaction for each closed hour. |
| `ScheduleUptimeChecksJob` | every minute | none | Enqueues one uptime check per monitor that is due. |

If Sidekiq isn't running, none of these run: no alerts, digests or uptime
checks, and ingested events wait unprocessed.

### Environment variables

Every variable below is read by the server's code or config.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `SECRET_KEY_BASE` | **yes** | none (**production refuses to boot without it**) | Signs and encrypts cookies and derives the `PrivateDigest` HMAC key. See "Secrets". |
| `GOODSORCERY_PUBLIC_URL` | **yes** | none (**production refuses to boot without it**) | This instance's public URL, e.g. `https://errors.example.com`. Sets the host and protocol of links in emails (password resets, alerts) and Slack alert posts, and the allowed hosts (`config.hosts`). The setup page's install snippet also shows it as the endpoint, the MCP server page (user menu) builds the MCP client snippets from it (`<URL>/mcp`), and the MCP endpoint accepts browser `Origin`s of it only. |
| `GOODSORCERY_EXTRA_HOSTS` | no | none | Comma-separated extra hostnames to accept besides the public URL's host. `/up` answers on any host. |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | **yes** | none | Encrypts captured error data, raw inbound events, API key tokens, tag values and notes. |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | **yes** | none | Deterministic encryption key. |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | **yes** | none | Key derivation salt. |
| `DATABASE_URL` | yes, unless you use the `database.yml` settings below | none | Full Postgres URL. Rails merges it over `config/database.yml`. |
| `DB_HOST` | if not using `DATABASE_URL` | the local socket | Postgres host for the `goodsorcery_web_production` database (user `goodsorcery_web`). The Kamal config sets it to the `db` accessory. |
| `GOODSORCERY_WEB_DATABASE_PASSWORD` | if not using `DATABASE_URL` | none | Password for the `goodsorcery_web` role on the `goodsorcery_web_production` database. |
| `REDIS_URL` | **yes** | `redis://localhost:6379/1` (Action Cable), `redis://localhost:6379/0` (cache), Sidekiq's own default | Sidekiq, Action Cable and, unless overridden, the cache store. |
| `REDIS_CACHE_URL` | no | `REDIS_URL` | A separate Redis for the cache store (rate limits, quota and key-lookup caches, fragments). |
| `SIDEKIQ_CONCURRENCY` | no | `5` | Sidekiq threads per process. Keep `RAILS_MAX_THREADS` (the database pool) at least this high in the Sidekiq process. |
| `RAILS_MAX_THREADS` | no | `3` Puma threads; database pool `5` | Puma threads per worker and the Active Record pool size. |
| `WEB_CONCURRENCY` | no | Puma's default (1) | Puma worker processes. `auto` uses one per CPU. |
| `PORT` | no | `3000` | Puma port. Thruster serves on 80 in the Docker image. |
| `PIDFILE` | no | none | Puma pid file path. |
| `RAILS_LOG_LEVEL` | no | `info` | Keep `info`. `debug` logs SQL, which includes the (redacted) issue titles. |
| `GOODSORCERY_ENABLE_SIGNUPS` | no | sign-up is open only until the first account exists | `1` keeps public sign-up open (the hosted service). |
| `GOODSORCERY_DISABLE_SIGNUPS` | no | none | `1` closes sign-up completely, even before the first account exists. It overrides `ENABLE`. Recommended for a public self-hosted instance; create the owner with `goodsorcery:create_owner` (see "First owner"). |
| `GOODSORCERY_HOSTED` | no | `false` | `true` (or `1`) marks this as the managed hosting service. Leave it unset when self-hosting. Read once at boot. It turns on entitlements: each account's stored values (`accounts.entitlement_values`) decide its uptime intervals, monitors per app, apps per account, monthly event quota (ingest answers `429 quota_exceeded` past it) and error retention choices, falling back to `config/entitlements.yml`. It also restricts uptime monitor URLs to web ports (see "Uptime checks"), shows "Hosted" in the sidebar and drops the endpoint line from install snippets. Self-hosted (unset), every entitlement is unlimited. After switching it on or off, run `bin/rails goodsorcery:fit_entitlements`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §12.2–12.3. |
| `GOODSORCERY_APM_RETENTION_DAYS` | no | `30` | Self-hosted only: days of performance data (hourly figures and slow-request traces) to keep, 1–30. Read once at boot. Hosted accounts use their `apm_retention_days` entitlement instead. Per-minute figures are always kept 2 days. |
| `GOODSORCERY_UPGRADE_URL` | no | none | Hosted mode only. Where the "Upgrade to unlock" link next to locked options goes. Unset, locked options say "Coming soon" and no upgrade text shows. |
| `GOODSORCERY_TERMS_URL` | no | none | An http(s) link to your Terms of Service. Read once at boot. When set, the sign-up page says "By signing up you agree to the Terms of Service." with it linked. |
| `GOODSORCERY_PRIVACY_URL` | no | none | An http(s) link to your Privacy Policy, handled the same way. With neither set, the sign-up page shows no agreement sentence. |
| `GOODSORCERY_UPTIME_ALLOW_PRIVATE_ADDRESSES` | no | off | `1` lets uptime checks reach loopback and private addresses, for testing monitors against a local server in development. Ignored in production, where checks always refuse private, loopback, link-local and cloud-metadata addresses. |
| `POSTMARK_API_TOKEN` | to send mail through Postmark | none | A Postmark **server** API token. When set, mail is delivered through Postmark's API. Without it, configure SMTP instead (see "Email"). |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | if you enable SMTP | none | Read by the commented-out `smtp_settings` in `config/environments/production.rb` once you uncomment it (see "Email"). |
| `GOODSORCERY_MAIL_FROM` | no | `Good Sorcery <no-reply@HOST>`, with HOST taken from the public URL | Sender address for all emails. |
| `GOODSORCERY_DOCS_URL` | no | this repository's `docs/` folder on GitHub | Target of the sidebar's Docs link. |
| `GOODSORCERY_API_KEY` | no | none | Self-reporting: an ingest key the bundled `goodsorcery` gem uses to report this instance's own errors and performance data (`config/initializers/goodsorcery.rb`). Unset, nothing is sent. See "Self-reporting". |
| `GOODSORCERY_ENDPOINT` | no | self-hosted: `GOODSORCERY_PUBLIC_URL`; hosted: `https://app.goodsorcery.com` | Where self-reporting sends this instance's own errors. Self-hosted with neither this nor `GOODSORCERY_PUBLIC_URL` set, self-reporting is off. |
| `GOODSORCERY_PERFORMANCE_MONITORING` | no | on | `0`/`false`/`no`/`off` turns off the gem's performance monitoring of this instance. |
| `SECRET_KEY_BASE_DUMMY` | build only | none | Set by the Dockerfile during `assets:precompile`, so the build needs no secrets or public URL. Never set it at runtime. |

Development and test also read `TEST_DB_SUFFIX` (see "Tests and linters")
and `CI` (eager loading in tests). The image sets `MAX_REQUEST_BODY` for
Thruster, which also reads its own variables such as `TLS_DOMAIN`. The Kamal
deploy reads further variables (`KAMAL_WEB_HOST`, `KAMAL_SSH_PORT`,
`KAMAL_SSH_USER`, `KAMAL_IMAGE`, `GOODSORCERY_HOST`, the registry login and
`CLOUDFLARE_TUNNEL_TOKEN`) on the machine that runs Kamal; see
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

### Secrets

Production reads every secret from environment variables. The repo has no
`config/credentials.yml.enc` or `config/master.key` (both are git-ignored), so
there is nothing to decrypt and nothing to share.

Generate the four secrets once from a checkout (development needs no
configuration for these commands), store them in a password manager, and back
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

**Email.** Password resets, sign-up confirmations and alerts need outgoing mail
(the first owner starts confirmed, so a new instance works before mail is set
up; later sign-ups can't add apps until they confirm). Set `POSTMARK_API_TOKEN`
to send through Postmark, and verify the sender's domain in Postmark (the
sender is `GOODSORCERY_MAIL_FROM`, by default `no-reply@` the public URL's
host). To use another provider, leave the token unset, uncomment
`config.action_mailer.smtp_settings` in `config/environments/production.rb`,
set your SMTP server, and provide `SMTP_USERNAME` and `SMTP_PASSWORD`.

### First owner

Until the first account exists, **anyone who reaches the sign-up page can
create it** and become the instance's verified first owner. After that,
sign-up closes (unless `GOODSORCERY_ENABLE_SIGNUPS=1`). On a server reachable
from the internet, either:

- set `GOODSORCERY_DISABLE_SIGNUPS=1` before the first deploy and create the
  owner from the command line (recommended), or
- open `https://your-host/registration/new` and sign up immediately after the first
  deploy.

To create the owner (and its account) from the command line:

```sh
bin/rails goodsorcery:create_owner EMAIL=you@example.com NAME="Your Name" ACCOUNT="Acme"
```

It prompts for the password twice without echoing it (or reads `PASSWORD`,
which then ends up in your shell history), marks the email verified, and
refuses an email that already has a user. Add `STAFF=1` to also give the owner
the staff area. On a Kamal deploy, run it in a container with a terminal:

```sh
bin/kamal app exec -i --reuse 'bin/rails goodsorcery:create_owner EMAIL=you@example.com NAME="Your Name" ACCOUNT="Acme"'
```

With plain Docker: `docker exec -it goodsorcery_web bin/rails goodsorcery:create_owner EMAIL=... NAME="..." ACCOUNT="..."`.

**Staff.** `/staff` lists every account and user and edits hosted
entitlements. Grant it to an existing user with
`bin/rails goodsorcery:make_staff EMAIL=you@example.com`; staff can then grant
or remove it for others from Staff › Users.

### Accounts and members

**Every member of an account has full admin rights over it.** Accounts record
an owner/member role, but it isn't enforced: any member can change app
settings (including retention), reveal and rotate ingest keys, connect or
disconnect Slack, change alert rules and create or delete uptime monitors.
There is no invite flow yet; extra members can only be added from the Rails
console. Only give accounts to people you trust with all of that.

### Deploying with Kamal

`config/deploy.yml` deploys everything to one server: web, Sidekiq, Postgres,
Redis and a Cloudflare Tunnel (which terminates TLS), so the server publishes
no HTTP ports. It holds no hosts or secrets; Kamal reads them from the
environment. In the upstream repository, CI deploys every push to `main` after
the checks pass. See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the server,
Cloudflare and GitHub setup, deploying from your own fork, and day-to-day
operations.

### Plain Docker

There is no published image; build it from a checkout. The image is built for
the machine's own architecture, so build on the server, or pass
`--platform linux/amd64` (or `linux/arm64`) to match it:

```sh
docker build -t goodsorcery_web .
```

The containers need to reach Postgres and Redis, so put everything on one
Docker network. A minimal single-host setup, with Thruster (built into the
image) getting a Let's Encrypt certificate for your domain:

```sh
docker network create goodsorcery

docker run -d --name goodsorcery-db --network goodsorcery \
  -e POSTGRES_USER=goodsorcery_web -e POSTGRES_PASSWORD=change-me -e POSTGRES_DB=goodsorcery_web_production \
  -v goodsorcery_db:/var/lib/postgresql postgres:18
docker run -d --name goodsorcery-redis --network goodsorcery \
  -v goodsorcery_redis:/data redis:8 redis-server --appendonly yes

# Put the variables from "Environment variables" in an env file, for example:
#   SECRET_KEY_BASE=...  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...  (and the other two keys)
#   GOODSORCERY_PUBLIC_URL=https://errors.example.com
#   DATABASE_URL=postgres://goodsorcery_web:change-me@goodsorcery-db/goodsorcery_web_production
#   REDIS_URL=redis://goodsorcery-redis:6379/0
#   GOODSORCERY_DISABLE_SIGNUPS=1
docker run -d --name goodsorcery_web --network goodsorcery --env-file goodsorcery.env \
  -e TLS_DOMAIN=errors.example.com -p 80:80 -p 443:443 \
  -v goodsorcery_storage:/rails/storage goodsorcery_web
docker run -d --name goodsorcery_job --network goodsorcery --env-file goodsorcery.env \
  goodsorcery_web bundle exec sidekiq -C config/sidekiq.yml
```

`TLS_DOMAIN` makes Thruster serve HTTPS on 443 (ports 80 and 443 must be
reachable from the internet for the certificate) and keep its certificates
under `/rails/storage`, hence the volume. If a reverse proxy or load balancer
terminates TLS instead, leave `TLS_DOMAIN` unset and publish only port 80 to
the proxy (`assume_ssl` makes Rails treat every request as HTTPS, so the proxy
must only ever serve the site over HTTPS). Docker-published
ports bypass host firewalls such as `ufw`; publish only what must be public.
Then create the first owner (see "First owner").

### Self-reporting

The server includes the `goodsorcery` gem, so an instance can track its own
errors and performance. Create an app on the instance (or on another
instance), and set its key as `GOODSORCERY_API_KEY`. Self-hosted, reports go to
`GOODSORCERY_ENDPOINT` if set, otherwise to the instance's own
`GOODSORCERY_PUBLIC_URL`; with neither set, self-reporting stays off. They
never go to app.goodsorcery.com unless you set that as the endpoint. Errors
from the ingest path itself are dropped, so a struggling ingest path doesn't
feed itself; reporting to a second instance gives you visibility when the
first is down.

### Uptime checks

Checks run on the `uptime` Sidekiq queue and always refuse private, loopback,
link-local and cloud-metadata addresses in production. In hosted mode
(`GOODSORCERY_HOSTED`), monitor URLs on well-known non-web service ports (SSH,
SMTP, mail, database, Redis, Docker and similar) are also rejected;
self-hosted instances can monitor any port. See
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for scaling checks with a dedicated
Sidekiq process.

### Logs and tokenised links

Password-reset, email verification and alert-mute links carry a token in the
query string. Rails filters it from its own request log, but proxies in front
of the app (Thruster, kamal-proxy, Cloudflare or your own) may log full URLs.
Reset tokens are single-use and expire after 15 minutes, verification links
after 3 days and mute links after 60 days. Treat proxy access logs as
sensitive.

## Privacy

Everything captured with an error may contain personal data: backtraces, code
context, locals, request params, headers, session, user, breadcrumbs and
environment. It is encrypted at rest. The server scrubs secrets again on
ingest, and user identities are stored only as HMAC digests. Only an id goes
through Redis/Sidekiq, never the payload, and dashboard pages send
`Cache-Control: no-store`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the privacy section
of [docs/INGEST_API.md](docs/INGEST_API.md). The MCP endpoint returns captured data to the member's
AI client only as the dashboard shows it; request data, user details and
unredacted messages need a token with the request data scope ([docs/MCP.md](docs/MCP.md)).

## Troubleshooting

- **`PublicUrl::Missing: Set GOODSORCERY_PUBLIC_URL ...` at production boot.** Set it to an `http(s)://` URL with a host.
- **`ActiveRecord::Encryption::Errors::Configuration` / `Decryption` errors.** The encryption keys are missing or changed. See "Secrets".
- **``Missing `secret_key_base` for 'production' environment`` at boot.** Set `SECRET_KEY_BASE` (the message's `credentials:edit` hint doesn't apply; this app doesn't use credentials).
- **Sign-in fails with `InvalidAuthenticityToken` or redirects in a loop (production).** The site is being served over plain HTTP. Serve it over HTTPS (see "Processes").
- **"Blocked hosts" error page in production.** The request's host isn't the public URL's host. Add it to `GOODSORCERY_EXTRA_HOSTS`.
- **Events return 202 but never appear (production).** Sidekiq isn't running, or it can't reach `REDIS_URL` (Redis 7.0+ is required). Once fixed, run `bin/rails goodsorcery:requeue_stale`.
- **Events return 202 but never appear (development).** Check `log/development.log` for job errors. The async adapter runs jobs inside the server process.
- **401 / 413 / 415 / 422 / 429 from ingest.** See the error table in [docs/INGEST_API.md](docs/INGEST_API.md). A rotated key is rejected right away.
- **`PG::ConnectionBad`, "database does not exist" or `role "..." does not exist`.** Start Postgres, create a role for your OS user on Linux (see "Requirements"), then run `bin/rails db:prepare`.
- **Migration fails with `extension "pg_trgm" is not available`.** Install the Postgres contrib package (`postgresql-contrib` on Debian/Ubuntu; Homebrew's postgresql includes it).
- **Styles missing or stale.** Run `bin/dev` (it starts the Tailwind watcher), or `bin/rails tailwindcss:build` once.
- **System tests hang or fail to start.** Install or update Google Chrome. Selenium Manager fetches a matching chromedriver.
- **Sign-up page redirects to sign-in.** Sign-up closes once the first account exists, and `GOODSORCERY_DISABLE_SIGNUPS=1` closes it entirely. Use `bin/rails goodsorcery:create_owner`, or set `GOODSORCERY_ENABLE_SIGNUPS=1` to keep it open.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
and the [Code of Conduct](CODE_OF_CONDUCT.md). Please report security
vulnerabilities privately, as described in [SECURITY.md](SECURITY.md), not in
a public issue.

## License

Good Sorcery is released under the [MIT License](LICENSE).
