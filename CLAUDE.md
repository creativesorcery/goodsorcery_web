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
- **Email alerts** (approved 2026-10-11, `docs/ARCHITECTURE.md` §11): per-app rules (new issue, regression, reached production, still happening, daily digest) and environment scope in Settings › Alerts; each member's per-app switches on the Notifications page (user menu); signed one-click mute links; the `alert_deliveries` throttle table. Delivery (§11.4): ingest flags new issue, regression and reached production after commit; a 5-minute still-happening sweep; an hourly digest run (09:00 local per recipient); a cap of 20 alert emails per user per hour, with the rest folded into one "and N more alerts" summary; `AlertsMailer` with List-Unsubscribe headers.
- **Entitlements** (approved 2026-11-03, `docs/ARCHITECTURE.md` §12.2–12.3): `GOODSORCERY_HOSTED` is read once into `config.x.hosted`. Self-hosted (the default) is unlimited and ignores stored values. Hosted reads `accounts.entitlement_values` (jsonb, values only, never tier names) through the `Entitlements` PORO (`account.entitlements`), falling back per key to `config/entitlements.yml` (intervals 10 and 60 minutes, 1 monitor per account). Enforced in `UptimeMonitor` validations; locked options say "Upgrade to unlock" (`GOODSORCERY_UPGRADE_URL`). The future billing push contract is documented in §12.3, not built. `bin/rails goodsorcery:fit_uptime_monitors` re-fits monitors after the switch or the defaults change.
- **Uptime** (approved 2026-11-03, §12): per-app `UptimeMonitor`s (1/5/10/60-minute intervals) behind the sidebar's Uptime link (a coral dot when one is down): list with status, uptime 24h/7d/30d and status bars; detail page with history and incidents; form; delete; rate-limited Check now. An every-minute cron (`ScheduleUptimeChecksJob`, queue `default`) claims due monitors by `next_check_at` and enqueues one `UptimeCheckJob` each (queue `uptime`); `UptimeProbe` is the SSRF-safe client (10 s budget, one immediate retry). Checks, hourly rollups and incidents are pruned by `goodsorcery:prune`. Down and recovered emails join the alert system: app rules in Settings › Alerts, an Uptime switch per member, mute links, one email per incident and kind, exempt from the hourly cap.

## Ruby client gem

The `goodsorcery` gem (module `GoodSorcery`) lives in a sibling checkout, `../goodsorcery-ruby`. Its `docs/DESIGN.md` is the blueprint for the gem and for the server endpoints it uses (§7: batch and verify). Keep the setup page snippets (`app/views/projects/setups/*`, `SetupHelper`) in step with its configuration API.

## Not built yet (each needs the user's go-ahead)

- Postgres backups (see `docs/DEPLOYMENT.md`).
- Merge/unmerge, Assign and mute rules.
- The billing app and the entitlements push endpoint (contract in `docs/ARCHITECTURE.md` §12.3).
- Team invites, project deletion and GitHub links.
- Geo-IP, code syntax highlighting, dark mode and mobile navigation.
- Settings pages other than Setup & API keys, General and Alerts. A user profile page (name, time zone).
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
- **Model concerns:** `Issue::Searchable`, `Issue::Triage` and `Issue::Broadcasting`, plus `Project::Broadcasting` and `Project::Alerting`.
- **Uptime:** `UptimeMonitor` (+ `Checking`, `Broadcasting`, `Alerting` concerns), `UptimeCheck`, `UptimeHourlyCount`, `UptimeIncident`, `UptimeSchedule` (the claim), `UptimeProbe` with `AddressGuard`, `Deadline` and `Connection`, `UptimeUrl`, `UptimeOverview`/`UptimeReport` (pages), `UptimeAlert` (`UptimeAlertJob`), `Account::UptimeMonitoring` (limit and fitting) and `Entitlements`.
- **Alerts:** `AlertRule` (one row per app and kind), `NotificationPreference` (sparse, per membership and app), `AlertDelivery` (throttle/audit log keyed by `[user_id, dedupe_key]`) and `AlertMute` (the signed mute-link token). The delivery API is in `docs/ARCHITECTURE.md` §11.2. Delivery POROs: `IssueAlert` (instant alerts, `IssueAlertJob`), `StillHappeningCheck`, `DailyDigest` and `AlertSummary`, each driven by a job on the `alerts` queue, and `AlertsMailer` (§11.4).
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
bin/rails goodsorcery:cap_occurrences          # trim each app to 3,000 stored occurrences (every 5 min in production)
bin/rails goodsorcery:fit_uptime_monitors      # after switching GOODSORCERY_HOSTED on or off or editing config/entitlements.yml
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
- **Alert recipients:** never mail an unverified address. Use `project.alert_recipients` / `digest_recipients` and re-check `membership.receives_alerts?` / `receives_digest?` at send time. Muting an app's alerts and turning off its digest are independent switches.
- **Unsaved defaults and `has_many_inversing`:** `Membership#notification_preference_for` and `AlertRule.build_default` build their unsaved defaults by id (`project_id:`), not by association. Built through `belongs_to` they would join the parent's `has_many` target and get autosaved the next time the parent is saved.
- **Alert throttling:** `AlertDelivery.record` is an `INSERT … ON CONFLICT DO NOTHING` on the unique `[user_id, dedupe_key]` index and skips validations; a nil return means "already sent". Keep keys built by `AlertDelivery.issue_key` / `digest_key` / `summary_key`.
- **Alert triggers on the ingest hot path:** `Ingest::Processor#flag_alerts` runs after commit and reads only `tally.created?`, `previous_status` and `just_reached_production` from the counter UPDATE. Never add a query there for ordinary events; `test/models/ingest/alert_flags_test.rb` pins the statement count at 12. Alert jobs take integer ids and the kind; all checks (rule on, unresolved, environment scope, throttle) happen in `IssueAlert` at send time, and again in `AlertsMailer`, which returns without `mail` when the issue or recipient no longer qualifies.
- **Alert cap and clocks:** `AlertDelivery.claim` holds a per-user `pg_advisory_xact_lock` across the cap count and the insert, wrapped in `uncached` (jobs run with the query cache on). `.record` stamps `created_at` with `Time.current`, not the database clock, so the windows match Ruby time and `travel_to` works in tests. Digests and summaries don't count towards the cap.
- **Trailing-hour SQL:** `IssueHourlyCount::TRAILING_HOUR_SUM` casts its binds (`CAST(:previous_share AS double precision)`). In `HAVING`, Postgres otherwise infers an integer parameter and rejects `0.75`.
- **Mute endpoint:** `AlertMutesController` is unauthenticated and skips CSRF for `create` only, because RFC 8058 one-click POSTs carry no CSRF token. The signed `AlertMute` token is the credential; never make it read the session cookie. `show` must stay side-effect free (mail scanners prefetch links), and its form is `data-turbo=false` because `create` answers 200.
- **Browser gate on email links:** `ApplicationController`'s `allow_browser versions: :modern` answers 406 to older browsers (iOS 16 Safari, in-app mail browsers). Any page reached from an email link must override the private `any_browser_allowed?` to return true, as `AlertMutesController` and `EmailVerificationsController#show` do.
- **Still-happening sweep and muted apps:** an app with no recipients records no `alert_deliveries`, so the 6-hour throttle never starts. `StillHappeningCheck` skips apps where `alert_recipients.exists?` is false; keep that check, or every sweep enqueues a no-op job per hot issue.
- **Scheduled jobs:** sidekiq-cron loads `config/schedule.yml` in the Sidekiq process (production only).
- **`UptimeMonitor`, never `Monitor`:** Ruby's stdlib `Monitor` is used by Rails itself; a top-level `Monitor` model breaks the app.
- **Monitor URLs are secret:** they may carry tokens. `url` is encrypted and shown only on the edit form and detail page; lists and emails show `name` and `host`. Never put it in job args (ids only), Redis, the cache, broadcasts, logs, exception or validation messages, check rows or `alert_deliveries`. Probe errors are logged by class name only. The fixture URL carries `uptime-fixture-secret`, and tests assert it never leaks.
- **SSRF client:** every uptime request goes through `UptimeProbe`. `AddressGuard` resolves once and refuses the host if any address is private, loopback, link-local, CGNAT, multicast, ULA or metadata (embedded IPv4 unwrapped); the connection is pinned to that IP (`ipaddr=`, proxy `nil`) while Host/SNI keep the name; every redirect hop is re-vetted. `UptimeProbe::Connection` caps all bytes read per connection (Net::HTTP has no header limit). Never use `Net::HTTP.get`, `open-uri` or another client for monitor URLs. `GOODSORCERY_UPTIME_ALLOW_PRIVATE_ADDRESSES=1` (never in production) is the local-testing escape hatch; tests inject `allowed_ips:`/`resolver:` instead.
- **Hosted mode:** read `Rails.configuration.x.hosted` (or `entitlements.unlimited?`), never `ENV` at request time; tests use `with_hosted_mode`. Views show locked options and "Upgrade to unlock" only when `!entitlements.unlimited?`. Never write a tier name ("free", "premium") anywhere; only entitlement values exist here.
- **Uptime claim SQL:** `UptimeSchedule::CLAIM_SQL` casts its binds (`CAST(:now AS timestamp)`) because Postgres can't infer them inside `extract`/`make_interval`, runs `uncached`, and steps `next_check_at` from the monitor's own minute so late claims don't bunch monitors together. `UptimeCheckJob` drops jobs whose monitor was checked since `enqueued_at`; checks are recorded at their start time for that comparison.
- **Check now gate:** `check_now_gap` is 30 seconds self-hosted and the shortest entitled interval hosted, so Check now can't beat the entitlements.
- **Debug logs:** SQL logs in dev and test include redacted issue titles. Keep production at `info`.
- **Dev data:** test events overwrite a project's runtime label and use up issue numbers; deleting issues doesn't rewind the sequence. Seeds don't run again once the demo user exists (`bin/rails db:reset` to start over).
- **Port 3917:** something else on this machine has used it. Don't kill processes you didn't start; give dev servers you start their own pid file (`-P tmp/pids/server_PORT.pid`).
- **Bash tool:** in this environment, compound commands starting with `cd dir; …` have returned empty output. Use absolute paths instead.
