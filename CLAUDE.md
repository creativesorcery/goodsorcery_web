# Good Sorcery Error Tracker

## Standing guidelines (from the user, 2026-10-04)

1. **Don't build until told.** The user approved the v1 build on 2026-10-04, and v1 is built (see "Current state"). Any new feature or significant change still needs the user's explicit go-ahead first. Discussion, questions and design talk are fine before then.
2. **How to build, once told:** use Opus with high effort, run as a workflow. Build the Rails app to match the approved UI design in `~/projects/goodsorcery/design` (`index.html` and `DESIGN.md`):
   - Flat pastel theme.
   - No deploy tracking, no keyboard shortcuts, no needs-attention callout.
   - Use the wording "Add a new app".
3. **Rails conventions, old-school style:** Hotwire (Turbo and Stimulus) and Action Cable. No single-page JavaScript framework.
4. **Stack (already scaffolded):** Ruby 4.0.7, Rails 8.1.4, Postgres, Tailwind. No Solid Queue, Solid Cache or Solid Cable.
   - Production: Sidekiq on Redis for jobs, Redis cache store, Redis for Action Cable.
   - Development: async jobs, memory store, async Action Cable.
5. **No service objects with a `call` method.** Whenever an object is needed, plain old Ruby objects or classes with descriptive, domain-named methods are welcome. Just don't write them service-call style. Otherwise prefer rich models and concerns, in old-school Rails style.
6. **Short methods, shallow conditionals.**
   - Keep methods short. 20 lines is a hard limit, and split well before that.
   - Avoid deeply nested conditionals.
   - A growing method is a sign that its distinct behaviors belong in separate, well-named classes, designed in an object-oriented way.
7. **Review every code change for security and performance.**
   - Performance: avoid N+1 queries, cache where possible, and design for high-rate error ingest.
   - Security: treat everything captured with an error as sensitive, since it may contain personal data such as emails and usernames. That covers stack traces, code references, request params, headers, session, user context, breadcrumbs and environment.

## Current state (as of 2026-10-05)

v1 is built and committed on `main`. It was built in three workflows: foundation, feature slices, then security, performance, correctness and design reviews with fixes. The final check was green: 668 tests and 8 system tests passing, RuboCop and Brakeman clean, and the bundler and importmap audits clean.

v1 scope:
- **Accounts:** sign-up, sign-in, password reset and session expiry. Accounts, users and memberships; every dashboard query is scoped through `Current.account`.
- **Projects ("apps"):** created via "Add a new app", with ingest-only API keys per environment that can be revealed, copied and rotated, plus the General settings page.
- **Ingest:** `POST /api/v1/events` and `POST /api/v1/events/batch` (up to 100 events; Bearer key) return 202; `GET /api/v1/verify` checks a key. The raw body is stored encrypted and its id goes to a Sidekiq job. Processing scrubs and redacts the data, fingerprints it into an issue and updates the hourly rollups, tag counts and affected users.
- **Projects overview:** sparklines and the "Listening…" state.
- **Issue list:** triage tabs, filters, query-chip search, 24h histograms and bulk resolve/ignore.
- **Issue detail:** chart, app-first backtrace, breadcrumbs, the six data tabs (Request, Params, Headers, Session, Job, Environment), tag bars, affected user, occurrence navigator and notes.
- **Setup/onboarding page.**
- **Live updates:** pointer broadcasts over Action Cable. They carry ids and paths only; the browser re-fetches with its own session.

## Ruby client gem

The `goodsorcery` gem (module `GoodSorcery`) lives in a sibling checkout, `../goodsorcery-ruby`. Its `docs/DESIGN.md` is the blueprint for the gem and for the server endpoints it uses (§7: batch and verify). Keep the setup page snippets (`app/views/projects/setups/*`, `SetupHelper`) in step with its configuration API.

## Not built yet (each needs the user's go-ahead)

- Postgres backups (see `docs/DEPLOYMENT.md`).
- Merge/unmerge, Assign and mute rules.
- Alerts and Uptime (they show as "soon" in the sidebar), team invites, project deletion and GitHub links.
- Geo-IP, code syntax highlighting, dark mode and mobile navigation.
- Settings pages other than Setup & API keys and General.
- Live updates for the tab counts and the sidebar issue badge. A regressed issue isn't inserted into an already open Unresolved list.
- Closing open cable subscriptions when a membership is revoked. Re-fetches are still authorised.
- Buffering hot-issue counters in Redis. One extremely noisy issue serialises on its counter rows.

## Architecture overview

Read `docs/ARCHITECTURE.md` (the binding blueprint: schema, encryption, ingest pipeline, routes, caching, authorization, theme) and `docs/INGEST_API.md` (the public payload spec, limits and error codes) before changing these areas. `README.md` covers booting, environment variables and secrets.

- **Ingest path:**
  - `lib/middleware/ingest_body_shield.rb` keeps Rails from parsing or logging the body (single and batch paths).
  - `Api::V1::EventsController` (one event) and `Api::V1::Events::BatchesController` (`/api/v1/events/batch`, 1–100 events, partial accept by index) share the `IngestEndpoint` concern: IP limit, key check through `ApiKeyAuthentication` (digest lookup, cached), key/account limits counted in events (`Ingest::EventRateLimit`, a batch of N takes N), quota, media type, size, JSON.
  - Each event is stored as its own encrypted `InboundEvent` (`InboundEvent.store_for`, one INSERT per request) and enqueued with `ActiveJob.perform_all_later`; `ProcessInboundEventJob` (queue `ingest`) calls `Ingest::Processor#process`.
  - `Api::V1::VerificationsController` (`GET /api/v1/verify`) answers the gem's install check: key valid → `{"ok":true,"environment":…}`, nothing stored, own rate limits.
- **`app/models/ingest/`:** plain Ruby objects such as `Scrubber`, `MessageRedactor`, `Fingerprint`, `IssueTally`, `Rollups`, `TagRows`, `Retention` and `StaleEvents`. Their method names are descriptive, never `call`.
- **Dashboard models:** query and presentation objects such as `IssueQuery` (chip parsing), `IssueList`, `IssueSummary`, `IssueChart`, `OccurrenceNavigator`, `ProjectOverview`, `ProjectHealth`, `SetupProgress` and `LiveFrames`.
- **Model concerns:** `Issue::Searchable`, `Issue::Triage` and `Issue::Broadcasting`, plus `Project::Broadcasting`.
- **Live updates:** `AuthorizedStreamsChannel` checks the signed stream name and account membership. Custom Turbo Stream actions (`reload_frame`, `reload_rows`) are in `app/javascript`. Debouncing is in `LiveUpdateGate`.
- **Theme:** Tailwind v4 `@theme` tokens and component classes are in `app/assets/tailwind/application.css`. Charts and sparklines are server-rendered SVG from helpers, with no chart JS. The CSP uses nonces, so there are no inline scripts or styles.

## Key commands

```sh
bin/setup --skip-server && bin/rails db:seed   # first-time setup + demo data
bin/dev                                        # server + Tailwind watcher, http://localhost:3000
# demo login: philip@example.com / password (owner), jo@example.com / password (member)
bin/rails runner 'puts Project.find_by!(slug: "storefront").api_keys.find_by!(environment: "staging").token'
bin/send_test_event API_KEY http://localhost:3000   # EXCEPTION_CLASS=..., GZIP=1, EVENT_ID=..., BATCH=N, JOB=1
bin/rails goodsorcery:prune                    # retention (daily in production)
bin/rails goodsorcery:requeue_stale            # recover events never processed
```

## Test and lint workflow

Run all of these before committing:

```sh
bin/rails test && bin/rails test:system
bin/rubocop          # enforces Metrics/MethodLength max 20 and Metrics/BlockNesting max 1
bin/brakeman --no-pager -q
bin/bundler-audit && bin/importmap audit
```

- **Parallel runs** (e.g. several agents at once): give each its own test database with `TEST_DB_SUFFIX=_name bin/rails db:test:prepare test`.
- **Fixtures:** every model has fixtures, including an `outsider` user for "other account gets 404" tests. Authorization tests on every new controller action are expected.
- **System tests** click through the DOM via JavaScript (`press`, `type_into`) because headless Chrome on this machine intermittently drops WebDriver input. Keep that pattern.
- **Commits:** commit in logical steps on `main`. Each commit message ends with the Co-Authored-By trailer.

## Gotchas

- **Query cache in jobs:** `UPDATE … RETURNING` run through `select_value`/`find_by_sql` gets served from the query cache inside jobs. Wrap such queries in `uncached { }` (see `allocate_issue_number`, `IssueTally`).
- **Rate-limit store:** Rails reads the `rate_limit` store when the class loads. `Ingest::RateLimitStore` looks up `Rails.cache` per request instead; don't "simplify" it away.
- **Event-weighted limits:** the per-key and per-account ingest limits are `Ingest::RateCounter`s, not Rails' `rate_limit` (which can only add 1). Both ingest endpoints share their counters; keep it that way so a batch of N costs the same as N single requests. Every request takes one unit before its body is read (so malformed batches aren't free); a batch takes the rest after parsing and gives everything back on 429.
- **Ingest lock order:**
  - The issue row is locked with `FOR NO KEY UPDATE`; plain `FOR UPDATE` deadlocks against foreign-key KEY SHARE locks.
  - The project hourly count update must stay the last statement before commit.
  - Issue numbers are reserved before the transaction.
  - `test/models/ingest/concurrent_processing_test.rb` guards this.
- **Never put captured data in:** Sidekiq/job args, Redis, the cache store, logs, broadcasts or exception messages (Postgres errors are re-raised without row values). Dashboard pages send `Cache-Control: no-store`. Never call `raw`/`html_safe` on captured data.
- **Plaintext columns:** only the redacted title, transaction and culprit are plaintext, for search. Everything else captured is in encrypted columns. User identities and tag values are matched by `PrivateDigest` HMAC, which is derived from `secret_key_base`; rotating it breaks digest continuity.
- **Encryption keys:** development and test use fixed, non-secret keys (`config/environments/*.rb`). Production reads `ACTIVE_RECORD_ENCRYPTION_*` and `SECRET_KEY_BASE` from ENV; there is no credentials file.
- **Production boot:** it fails without `GOODSORCERY_PUBLIC_URL`, except for asset builds, where `SECRET_KEY_BASE_DUMMY` is set.
- **Deploy:** CI deploys `main` with Kamal (`docs/DEPLOYMENT.md`). The repo is public: never commit hosts, IPs or secrets; `config/deploy.yml` reads them from ENV via ERB.
- **Email verification:** sign-up sends a link (`User::EmailVerification`, `EmailVerificationsController`); unverified users can browse but `VerifiedEmailRequired` blocks creating apps and API keys. The first account's owner starts verified (self-hosted mail may not be set up). A password reset also verifies.
- **Email templates:** every HTML email uses `layouts/mailer.html.erb` and the inline-styled `MailerHelper` blocks (`email_heading`, `email_text`, `email_button`, `email_note`, `email_link_fallback`); set `content_for :preheader` / `:footer`. Text parts output user values with `raw`.
- **Scheduled jobs:** sidekiq-cron loads `config/schedule.yml` in the Sidekiq process (production only).
- **Debug logs:** SQL logs in dev and test include redacted issue titles. Keep production at `info`.
- **Dev data:** test events overwrite a project's runtime label and use up issue numbers; deleting issues doesn't rewind the sequence. Seeds don't run again once the demo user exists (`bin/rails db:reset` to start over).
- **Port 3917:** something else on this machine has used it. Don't kill processes you didn't start; give dev servers you start their own pid file (`-P tmp/pids/server_PORT.pid`).
- **Bash tool:** in this environment, compound commands starting with `cd dir; …` have returned empty output. Use absolute paths instead.
