# Good Sorcery Error Tracker: Architecture Blueprint

This is the binding blueprint for v1. Implementers follow it exactly. If something here turns out to be wrong, raise it with the lead instead of working around it, because other slices depend on the same contract.

Inputs: `CLAUDE.md` (standing guidelines), `~/projects/goodsorcery/design` (DESIGN.md, `index.html`, `projects.html`, `issues.html`, `issue.html`, `settings.html`, `assets/*`).
Stack: Ruby 4.0.7, Rails 8.1.4, Postgres (pg_trgm), Propshaft, importmap, Turbo, Stimulus, tailwindcss-rails 4 (Tailwind v4), Sidekiq and Redis in production, async adapters in development. There are no Solid gems.

---

## 0. Ground rules (all slices)

1. **Old-school Rails.** Use rich models, concerns, RESTful controllers (one resource per controller, CRUD action names only), and server-rendered ERB with Turbo Frames and Streams. Stimulus is only for small sprinkles. There is no SPA framework and no chart JS library.
2. **No `call` service objects.** POROs are welcome when they have domain names and descriptive verbs (`Ingest::Scrubber#scrub`, `Ingest::Fingerprint#digest`, `IssueQuery#issues`). Do not define `call`, `perform` (outside jobs) or `run`.
3. **Methods have a hard limit of 20 lines. Aim for 1–8.** Conditionals nest at most one level. If a method grows, extract a well-named object.
4. **Everything captured with an error is sensitive PII.** That covers backtraces, code context, locals, request, params, headers, session, user, breadcrumbs, context/env and tag values.
   - It is stored only in Active Record–encrypted columns (§1.4), except for the redacted, length-capped issue summary columns justified in §1.5.
   - It never appears in Sidekiq/Redis job arguments, Action Cable payloads, the Rails cache, logs or exception messages.
   - It is always rendered through ERB escaping. `raw`, `html_safe` and `sanitize` are never applied to captured data.
5. **Performance.** No N+1 queries (use `includes`, `inverse_of` and batch queries for histograms). Counters are atomic SQL. The ingest path is bounded and tuned for minimal queries (§2.6).
6. **Tests.** Use Minitest with fixtures. Always run with a private DB:
   `TEST_DB_SUFFIX=_<slice> bin/rails db:test:prepare && TEST_DB_SUFFIX=_<slice> bin/rails test`. Never drop the development database. Run `bin/rubocop` on your files before you finish.
7. **Out of scope (do not build):** deploy tracking/releases UI, keyboard shortcuts, the "needs attention" callout, Merge, "Mute rules", GitHub links ("Link GitHub issue", "Open in GitHub"), alerting (the Alerts nav item shows as "soon"), Uptime ("soon"), team invites, project deletion, the Ruby client gem, geo-IP ("London, GB"), and syntax highlighting of code context (render plain mono text).
8. **Wording.** Every "create project" affordance reads **"Add a new app"**: the projects page header button, the dashed tile and the `projects#new` page title.

---

## 1. Domain model and database schema

### 1.1 Entities

```
Account ─┬─< Membership >── User ──< Session (session.account = current org)
         └─< Project ─┬─< ApiKey (one per environment, ingest-only)
                      ├─< InboundEvent (encrypted raw body, transient queue record)
                      ├─< ProjectHourlyCount (project, environment, hour)
                      └─< Issue ─┬─< Occurrence (encrypted payload)
                                 ├─< IssueHourlyCount (issue, hour)
                                 ├─< IssueTagCount (key, HMAC(value), encrypted value)
                                 ├─< IssueUser (HMAC of user identity, never plaintext)
                                 └─< IssueActivity (triage log and notes; note bodies encrypted)
```

- **Account** is the organisation ("Acme Labs"). A user can belong to several accounts through **Membership** (`role`: `owner` or `member`). Sign-up creates an account, a user and an owner membership.
- **Session** comes from the Rails 8 auth generator, plus `account_id`, which is the account this browser session is working in (`Current.account`). At sign-in it is set to `user.default_account` (the earliest membership). Switching accounts is not in v1, but the schema supports it.
- Every dashboard query is scoped through `Current.account` (§6).

### 1.2 Extensions

`enable_extension "pg_trgm"` (`plpgsql` is the default).

### 1.3 Tables (complete; later slices make NO schema changes)

All `id`s are `bigint`. FKs are real `add_foreign_key` constraints. "cascade" means `on_delete: :cascade`.

**accounts**
| column | type | null | default |
|---|---|---|---|
| name | string | false | |
| monthly_event_quota | bigint | true | nil means unlimited (self-host) |
| created_at / updated_at | datetime | false | |

**users** (generator plus extra columns)
| column | type | null | default |
|---|---|---|---|
| email_address | string | false | | unique index |
| password_digest | string | false | |
| name | string | false | |
| time_zone | string | false | `"UTC"` |
| timestamps | | | |

**memberships**
| column | type | null | default |
|---|---|---|---|
| account_id | references → accounts, cascade | false | |
| user_id | references → users, cascade | false | |
| role | string | false | `"member"` |
| timestamps | | | |
Indexes: unique `[account_id, user_id]`, `[user_id]`.

**sessions** (generator plus `account_id`)
| column | type | null |
|---|---|---|
| user_id | references → users, cascade | false |
| account_id | references → accounts, cascade | false |
| ip_address | string | true |
| user_agent | string | true |
| timestamps | | |

**projects**
| column | type | null | default | notes |
|---|---|---|---|---|
| account_id | references → accounts, cascade | false | | |
| name | string | false | | 1..60 chars |
| slug | string | false | | `name.parameterize`. Unique per account; `-2`, `-3` suffix on collision; immutable |
| platform | string | false | `"rails"` | enum: `rails` ("Ruby on Rails"), `ruby` ("Ruby"); picks the Setup page snippets. Older `rails_api`/`sidekiq` rows were migrated to `rails` |
| runtime_label | string | true | | e.g. "Rails 8.0 · Ruby 3.4". Set when a new issue is created (§2.5) |
| issue_prefix | string | false | | `/\A[A-Z]{1,6}\z/`, unique per account. Default: initials of the slug words, or the first 3 letters when there is one word, with a letter swapped in when taken ("STOB") |
| issues_sequence | integer | false | 0 | per-project short-number counter |
| color | string | false | `"iris"` | enum `iris coral lilac mint`. Rotated by `account.projects.count % 4` on create |
| scrub_fields | string, array | false | `[]` | extra server-side scrub keys |
| retention_days | integer | false | 90 | 1..365 |
| first_event_at | datetime | true | | nil means "Listening…" |
| default_environment | string | true | | the environment the issue list opens on; nil means all environments. Must be one of `environments` (validated, normalised to lowercase, blank → nil). Set to `"production"` once at creation when the new app has a production key (always, given the default keys); later nil is a deliberate "All environments" and is kept. Migration `20261010000003` backfilled `"production"` for apps with a production key |
| timestamps | | | | |
Indexes: unique `[account_id, slug]`.

**api_keys**
| column | type | null | default | notes |
|---|---|---|---|---|
| project_id | references → projects, cascade | false | | |
| environment | string | false | | `/\A[a-z0-9][a-z0-9_-]{0,31}\z/` |
| token | text | false | | **encrypted** (non-deterministic), used for Reveal |
| token_digest | string | false | | `SHA256.hexdigest(token)`, used for lookup |
| token_prefix | string | false | | first 12 chars, e.g. `gs_live_9f2c` |
| token_last4 | string | false | | |
| created_by_id | references → users, `on_delete: :nullify` | true | | |
| last_used_at | datetime | true | | |
| timestamps | | | | |
Indexes: unique `[token_digest]`, unique `[project_id, environment]`.
Token format: `gs_live_` + `SecureRandom.base58(32)` when `environment == "production"`, otherwise `gs_test_` + base58(32). A plain SHA-256 is right here because tokens are high-entropy random values, so no slow KDF is needed and lookups stay O(1). The setup page marks the project's lowest-id key "used in setup" (with a title): it is the key the install steps show. It is unrelated to the app's default environment (`projects.default_environment`).

**inbound_events** (transient: one row per accepted request, deleted when processed)
| column | type | null | notes |
|---|---|---|---|
| project_id | references → projects, cascade | false | |
| api_key_id | references → api_keys, cascade | false | |
| environment | string | false | copied from the key |
| event_uuid | uuid | false | returned to the client |
| body | text | false | **encrypted** raw JSON (compressed by AR encryption) |
| received_at | datetime | false | |
Indexes: `[received_at]` (stale requeue). No `updated_at`.

**issues**
| column | type | null | default | notes |
|---|---|---|---|---|
| project_id | references → projects, cascade | false | | |
| number | integer | false | | short id `"#{prefix}-#{number}"` |
| fingerprint | string(64) | false | | SHA-256 hex |
| exception_class | string | false | | ≤ 255, plaintext (§1.5) |
| message | text | false | `""` | **redacted** and ≤ 1,024 chars, plaintext (§1.5) |
| culprit | string(500) | true | | top app frame `"path:line in method"`, path-normalised |
| transaction_name | string | true | | ≤ 255, e.g. `CheckoutsController#create`, `Orders::PlaceJob` |
| level | string | false | `"error"` | enum `fatal error warning info` |
| status | string | false | `"unresolved"` | enum `unresolved resolved ignored` |
| environments | string, array | false | `[]` | |
| first_seen_at | datetime | false | | |
| last_seen_at | datetime | false | | |
| regressed_at | datetime | true | | set on regression, cleared on resolve |
| reached_production_at | datetime | true | | set once, by the ingest counter UPDATE (§2.5), when an issue first seen only in other environments gets its first production-tone event (`EnvironmentTone`). Never cleared. Issues first seen in production never get it. Migration `20261010000004` added it without a backfill |
| resolved_at | datetime | true | | |
| events_count | bigint | false | 0 | atomic SQL increments |
| users_count | integer | false | 0 | atomic SQL increments |
| assignee_id | references → users, `on_delete: :nullify` | true | | |
| search_text | virtual **stored** text | — | | `lower(exception_class \|\| ' ' \|\| message \|\| ' ' \|\| coalesce(culprit,'') \|\| ' ' \|\| coalesce(transaction_name,''))` |
| timestamps | | | | `updated_at` bumped by every ingest UPDATE |
Indexes: unique `[project_id, fingerprint]`, unique `[project_id, number]`, `[project_id, status, last_seen_at]`, `[project_id, status, events_count]`, `[project_id, first_seen_at]`, `[assignee_id]`, GIN `environments`, GIN `search_text gin_trgm_ops`.
Migration: `t.virtual :search_text, type: :text, as: "...", stored: true` and `t.index :search_text, using: :gin, opclass: :gin_trgm_ops`.

**occurrences**
| column | type | null | notes |
|---|---|---|---|
| issue_id | references → issues, cascade | false | |
| project_id | references → projects, cascade | false | denormalised for pruning |
| uuid | uuid | false | event id. Unique per project, used as `to_param` |
| occurred_at | datetime | false | clamped (§2.5) |
| received_at | datetime | false | |
| environment | string | false | |
| release | string | true | ≤ 64 (a version or SHA, not personal) |
| level | string | false | |
| user_digest | string(64) | true | HMAC (§1.6) |
| payload | text | false | **encrypted** normalised JSON (§3.3) |
| created_at | datetime | false | |
Indexes: unique `[project_id, uuid]`, `[issue_id, id]` (navigator and trim), `[project_id, received_at]` (retention).

**issue_hourly_counts**: `create_table ..., primary_key: [:issue_id, :hour]`
| issue_id | bigint FK → issues, cascade | false |
| hour | datetime | false | UTC hour start |
| count | integer | false | 0 |

**project_hourly_counts**: `primary_key: [:project_id, :environment, :hour]`
| project_id | bigint FK → projects, cascade | false |
| environment | string | false |
| hour | datetime | false |
| count | bigint | false | 0 |
Extra index: `[project_id, hour]`.

**issue_tag_counts**: `primary_key: [:issue_id, :key, :value_digest]`
| issue_id | bigint FK → issues, cascade | false |
| key | string(32) | false | plaintext key (`/\A[a-z0-9_.\-]{1,32}\z/i`) |
| value_digest | string(64) | false | `PrivateDigest.hexdigest("tag.#{key}", value)` |
| value | text | false | **encrypted** |
| count | bigint | false | 0 |

**issue_users**: `primary_key: [:issue_id, :user_digest]`
| issue_id | bigint FK → issues, cascade | false |
| project_id | bigint FK → projects, cascade | false |
| user_digest | string(64) | false | primary identity HMAC |
| identity_digests | string, array | false | `[]` HMACs of id, email and username (whichever are present) |
| events_count | integer | false | 0 |
| first_seen_at / last_seen_at | datetime | false | |
Indexes: `[project_id, last_seen_at]`, GIN `identity_digests`.

**issue_activities**
| issue_id | references → issues, cascade | false |
| user_id | references → users, `on_delete: :nullify` | true | nil = system |
| kind | string | false | enum `regressed reached_production resolved reopened ignored assigned unassigned note`; `regressed` and `reached_production` are system entries written by ingest |
| subject_user_id | references → users, nullify | true | assignee for assigned/unassigned |
| body | text | true | **encrypted**, notes only (≤ 2,000 chars) |
| created_at | datetime | false |
Indexes: `[issue_id, created_at]`.

### 1.4 Active Record Encryption

- Encrypted attributes are all non-deterministic with default compression: `InboundEvent#body`, `Occurrence#payload`, `ApiKey#token`, `IssueTagCount#value`, `IssueActivity#body`.
- Keys:
  - development.rb and test.rb set fixed, clearly-labelled non-secret keys:
    ```ruby
    config.active_record.encryption.primary_key = "dev-and-test-only-primary-key-not-secret"
    config.active_record.encryption.deterministic_key = "dev-and-test-only-deterministic-key-not-secret"
    config.active_record.encryption.key_derivation_salt = "dev-and-test-only-key-derivation-salt-not-secret"
    ```
  - production.rb uses `ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]` (and the same for the other two keys). There is no credentials file.
- test.rb: `config.active_record.encryption.encrypt_fixtures = true`.
- All environments: `config.active_record.encryption.support_unencrypted_data = false`.
- Rails 8.1 `insert_all`/`upsert_all` serialise through `model.type_for_attribute`, so bulk inserts encrypt automatically (verified in `activerecord-8.1.4/lib/active_record/insert_all.rb`). Slice A adds a model test asserting that the raw column value (`Model.connection.select_value`) is not the plaintext.

### 1.5 What stays plaintext, and why

Search (`class`, `message`, `culprit`) needs substring and trigram matching, which is impossible on randomised ciphertext. Issue list pages also render 25+ rows and must not decrypt anything. So these **issue-level summary columns** stay plaintext, under strict controls:

| Column | Why it is acceptable |
|---|---|
| `exception_class` | A code identifier, not user data. |
| `transaction_name` | Controller#action or job class: code identifiers. |
| `culprit` | Code location. Paths are normalised by `Ingest::PathNormalizer`: absolute prefixes are stripped to app-relative, home dirs (`/Users/x/`, `/home/x/`) become `~/`, and gem paths become `gems/<name>-<ver>/…`. |
| `message` | **Redacted** by `Ingest::MessageRedactor`: emails → `[email]`, UUIDs → `[uuid]`, IPv4 → `[ip]`, URL query strings → `?[query]`, hex/base64-like tokens of 16+ chars → `[token]`, `\b\d{2,}\b` → `[n]`. Capped at 1,024 chars. The full original message lives only in the encrypted occurrence payload. Residual risk (for example a bare first name in a message) is accepted and documented. |
| `environment`, `release`, `level` | Deployment metadata. |
| tag **keys** | Schema-like names. Tag **values** are encrypted. |

Never plaintext: anything else in the payload. User identifiers are stored only as HMACs (§1.6).

### 1.6 Digests

- `PrivateDigest.hexdigest(namespace, value)` (A, `app/models/private_digest.rb`) is `OpenSSL::HMAC.hexdigest("SHA256", KEY, "#{namespace}:#{value}")`. `KEY = Rails.application.key_generator.generate_key("goodsorcery private digest v1", 32)`. Rotating `secret_key_base` breaks continuity; this is documented and accepted.
- User identity namespaces are `user.id`, `user.email` (downcased and stripped) and `user.username`. The primary `user_digest` uses the first present of id, email, username. `identity_digests` holds all present ones.
- Tags use namespace `tag.<key>`.

### 1.7 Models (slice A): public API contract

Associations use `inverse_of`, so `@project.issues` sets `issue.project` without a query. Short-ID rendering depends on this.

- **Current** (`ActiveSupport::CurrentAttributes`): `session`, `delegate :user, to: :session, allow_nil: true`, `def account = session&.account`.
- **Account**: `has_many :memberships, :users (through), :projects`. `#accessible_by?(user)` checks `memberships.exists?(user_id: user.id)`. `#events_this_month` returns the cached (5 min) sum of `project_hourly_counts` for this month. `#event_quota_fraction` returns 0..1 or nil.
- **User**: `has_secure_password`, `normalizes :email_address`, `has_many :sessions, :memberships, :accounts`. `#default_account`, `#initials`, `#first_name`.
- **Membership**: `enum :role, { owner: "owner", member: "member" }`.
- **Session**: `belongs_to :user, :account`.
- **Signup** (ActiveModel PORO): attributes `account_name, name, email_address, password, time_zone`. `#save` creates the account, user and owner membership in one transaction and returns the user, or false with errors.
- **Project**:
  - `belongs_to :account`; `has_many :api_keys, :issues, :occurrences, :inbound_events, :project_hourly_counts`.
  - `to_param` returns `slug`. Callbacks `before_validation` set slug, issue_prefix and color on create. `after_create :create_default_api_keys` creates `production` and `staging` keys with `created_by: Current.user`, then sets `default_environment` to `"production"` when it is still nil and a production key exists.
  - `#accessible_by?(user)` delegates to account. `#listening?` is `first_event_at.nil?`. `#environments` returns the api_keys environments in id order.
  - `#allocate_issue_number` runs `UPDATE projects SET issues_sequence = issues_sequence + 1 WHERE id = $1 RETURNING issues_sequence`. `#record_first_event(runtime_label:, at:)` runs `UPDATE … SET first_event_at = COALESCE(first_event_at, :at), runtime_label = :label`.
  - `#unresolved_count(environment = nil)` and `#cached_unresolved_count(environment = nil)` (10 s, a number only; `#expire_unresolved_counts` on triage).
  - `include Project::Broadcasting` (stub, §4.6).
- **ApiKey**:
  - `belongs_to :project, :created_by (User, optional)`; `encrypts :token`.
  - `.authenticate(token)` returns an `ApiKey::Credential` (`Data.define(:id, :project_id, :environment)`) or nil. It is cached in `Rails.cache` under `["api_key", digest]` for 5 minutes and stores only ids and the environment.
  - `#rotate` sets a new token, digest, prefix and last4, deletes the old cache entry, and returns self.
  - `#masked_token` returns `"#{token_prefix}••••••••••••#{token_last4}"`.
  - `.record_usage(id)` updates `last_used_at` (`update_all`) at most once per minute per key, gated by `Rails.cache.write(["api_key_used", id], 1, unless_exist: true, expires_in: 1.minute)`.
  - `#default?`.
- **InboundEvent**: `belongs_to :project, :api_key`; `encrypts :body`; `scope :stale, -> { where(received_at: ...10.minutes.ago) }`.
- **Issue**:
  - `belongs_to :project` (inverse), `belongs_to :assignee, class_name: "User", optional: true`; `has_many :occurrences, :hourly_counts, :tag_counts, :issue_users, :activities`.
  - `enum :status` and `enum :level` (string-backed, `validate: true`).
  - `to_param`/`short_id` return `"#{project.issue_prefix}-#{number}"`. `.find_by_short_id!(param)` does `find_by!(number: param.to_s[/\d+\z/])`.
  - `#new?` is `unresolved? && first_seen_at >= 24.hours.ago`. `#regressed?` is `unresolved? && regressed_at.present?`. `#reached_production?` is `reached_production_at.present?`.
  - `#accessible_by?(user)` delegates to project. `#fingerprint_label` returns `fingerprint.first(12)`.
  - Includes `Issue::Searchable`, `Issue::Triage` and `Issue::Broadcasting` (stub).
- **Issue::Searchable** (scopes):
  - `unresolved`, `resolved`, `ignored` come from the enum. `newly_seen` is `unresolved.where(first_seen_at: 24.hours.ago..)`. `regressed` is `unresolved.where.not(regressed_at: nil)`. `for_review` is `unresolved.where("issues.first_seen_at >= :t OR issues.regressed_at IS NOT NULL", t: 24.hours.ago)`.
  - `in_environment(env)` is `where(":env = ANY(issues.environments)", env:)`. `at_level(level)`.
  - `assigned_to(user)`, `unassigned`.
  - `matching(text)` adds one `search_text LIKE '%term%'` per whitespace term, downcased and escaped with `sanitize_sql_like`.
  - `affecting(digests)` is `where(id: IssueUser.where("identity_digests && ARRAY[?]::varchar[]", digests).select(:issue_id))`.
  - `sorted_by(key)`: `last_seen` (default), `first_seen`, `events`, `users`, all descending with an `id desc` tie-break.
- **Issue::Triage**:
  - Instance methods: `resolve(by:)`, `ignore(by:)`, `reopen(by:)`, `assign(user, by:)`, `unassign(by:)`. Each one updates status/timestamps, records an `IssueActivity` and calls `broadcast_changes_later` and `project.broadcast_changes_later`. `resolve` clears `regressed_at`.
  - Class methods on relations: `resolve_all(by:)`, `ignore_all(by:)`, `reopen_all(by:)`, `assign_all(user, by:)`. Each plucks ids (max 100), runs `update_all` and `IssueActivity.insert_all`, then broadcasts.
- **Occurrence**:
  - `belongs_to :issue, :project`; `encrypts :payload`; `to_param` returns `uuid`.
  - `scope :latest_first, -> { order(id: :desc) }`. `.latest` and `.oldest`.
  - `#data` returns the memoized `JSON.parse(payload)`.
  - Readers: `#exception_message`, `#frames` (array of hashes), `#request`, `#params`, `#headers`, `#session_data`, `#job`, `#user`, `#breadcrumbs`, `#context`, `#tags`, `#transaction_name`. All read from `data` with `{}`/`[]` defaults.
  - `RETAINED_PER_ISSUE = 1_000`.
- **IssueHourlyCount**:
  - `.histograms(issue_ids, hours: 24)` returns `{ issue_id => [Integer] * hours }` in one grouped query, zero-filled via `TimeSeries`.
  - `.series(issue, period)` takes period `"24h"` (24 hourly buckets), `"7d"` (28 six-hour buckets) or `"30d"` (30 daily buckets, the viewer's local days via `DATE((hour AT TIME ZONE 'UTC') AT TIME ZONE zone)`) and returns `[[bucket_start, count], …]`. One query using `date_bin`/`date_trunc`.
- **ProjectHourlyCount**:
  - `.daily_series_by_environment(project_ids, days: 14)` returns `{ project_id => { environment => [Integer]*14 } }` of UTC days in one query grouped by project, environment and day (the `[project_id, environment, hour]` primary key). Only environments with events in the window appear; a project with none maps to `{}`.
  - `.hourly_totals(project_ids, hours: 24)` returns `{ project_id => [Integer]*24 }`.
  - `.total(project, from:, to:, environment: nil)`.
  - `.series(project, from:, buckets:, environment: nil)` serves the summary sparkline.
- **IssueTagCount**: `encrypts :value`. `.distribution(issue, per_key: 5)` returns `[TagDistribution::Key(key, distinct_count, total, values: [Value(value, count, share)])]` from one window-function query (`ROW_NUMBER() OVER (PARTITION BY key ORDER BY count DESC)`, `COUNT(*) OVER (PARTITION BY key)`, `SUM(count) OVER (PARTITION BY key)`), ordered by key. `TagDistribution` is a small `Data` value in the same file.
- **IssueUser**: `.count_for(issue, digest)`. `.distinct_users(project, since:, environment: nil)` counts distinct `user_digest`; with an environment, only users of issues seen in it.
- **IssueActivity**: `enum :kind`; `encrypts :body`; `belongs_to :user, :subject_user` (optional). `scope :recent`.
- **TimeSeries** (PORO): `TimeSeries.new(counts_by_time, from:, step:, buckets:)#values` and `#points`. Zero-fills and aligns buckets.
- **PrivateDigest** (§1.6).

---

## 2. Ingest pipeline

### 2.1 Endpoint

All `< ActionController::API` (no cookies, sessions or CSRF):

- `POST /api/v1/events` → `Api::V1::EventsController#create` (one event).
- `POST /api/v1/events/batch` → `Api::V1::Events::BatchesController#create` (1–100 events, §2.1.1).
- `GET /api/v1/verify` → `Api::V1::VerificationsController#show` (key check for client install checks, §2.1.2).

The two ingest controllers include the `IngestEndpoint` concern, which holds every shared check (in this order) plus storage and enqueueing; the error bodies come from `IngestErrorResponses`.

- **Auth:** `Authorization: Bearer <api key>` (`ApiKeyAuthentication`). Any other scheme or a missing header returns 401.
- **Content-Type:** must be `application/json` (415 otherwise). `Content-Encoding: gzip` is supported.
- **Size cap:** 512 KiB (2 MiB for a batch) for both the compressed and the decompressed body. `Ingest::RequestBody#read` (`max:`) rejects early when `Content-Length` > cap and reads gzip with `Zlib::GzipReader#read(cap + 1)` to defend against zip bombs. Oversized bodies return 413.
- **Rate limits** (store = `Ingest::RateLimitStore`, i.e. `Rails.cache`, so Redis in production; fixed one-minute windows):
  1. `rate_limit to: 6_000, within: 1.minute, by: -> { request.remote_ip }, name: "ip", scope: "api/v1/events"` (Rails 8 `rate_limit`, declared first; it counts requests and the scope makes the counter shared by both ingest endpoints)
  2. `before_action :authenticate_api_key`
  3. `before_action :limit_event_rate`: `Ingest::EventRateLimit` takes events from two `Ingest::RateCounter`s, per key (1,200/min) and per account (6,000/min), with the keys `rate-limit:api/v1/events:key:<id>` and `…:account:<id>`. Rails' `rate_limit` can only add 1, so these counters `increment` by N (`expires_in` = window). Admission is all or nothing; a rejected amount is given back. Both endpoints take 1 here (`IngestEndpoint#limit_event_rate`), so every request that reaches the body costs at least one unit. The batch endpoint takes the other N − 1 in `#create` once the body is parsed and the `events` array checked; if they don't fit it gives the first unit back too, so a 429 uses up nothing.
  All return 429 with `Retry-After: 60` and `{"error":"rate_limited"}` (`render_rate_limited`).
- **Check order:** per-IP limit, key (401), key/account limits (one unit), quota (429 `quota_exceeded`), media type (415), body size (413), JSON (400), shape (422), then for a batch the remaining event-weighted key/account units (429) and per-event validation.
- **Responses:**
  - `202 {"id":"<event uuid>"}`
  - `400 {"error":"invalid_json"}`
  - `401 {"error":"invalid_api_key"}`
  - `413 {"error":"payload_too_large"}`
  - `415 {"error":"unsupported_media_type"}`
  - `422 {"error":"invalid_payload","messages":[…]}`
  - `429`

  Error messages never echo payload content.

#### 2.1.1 Batch endpoint

`Ingest::Batch` parses the body once and checks `{"events":[…]}` with 1–100 entries (`422 invalid_payload` with messages otherwise). Each entry becomes an `Ingest::BatchItem`, validated by `Ingest::Envelope.new(data:, subject: "event")` and re-serialised with `Ingest::BatchItem::ENCODER` (a `JSON::Coder` that writes out-of-range numbers parsed as Infinity as `null`, as processing a single event does); an item over 512 KiB is rejected as `payload_too_large`. Accepted items are stored with `InboundEvent.store_for` (one multi-row `insert_all!`, which casts through the encrypted attribute type, so bodies are ciphertext exactly as with `save`) and enqueued with one `ActiveJob.perform_all_later` (Sidekiq `push_bulk`). The processor is unchanged: every InboundEvent holds one event's JSON. Duplicate `event_id`s are stored and deduplicated by processing, as for single events. `ApiKey.record_usage` runs once per request. Response: `202 {"accepted":[{"index":0,"id":"…"}],"rejected":[{"index":3,"error":"invalid_payload","messages":[…]}]}`, or `422` with the same shape when nothing was accepted.

#### 2.1.2 Verify endpoint

`GET /api/v1/verify` authenticates the key and returns `200 {"ok":true,"environment":"<key env>"}`. It creates nothing and uses its own Rails `rate_limit` counters (6,000/min per IP, 60/min per key, scope `api/v1/verifications`), so it never touches the ingest allowances or the quota.

### 2.2 Keeping PII out of Redis, Sidekiq and logs

1. **Request (fast path):** authenticate (cached key lookup), check the size, `JSON.parse` once for validation via `Ingest::Envelope` (requires a JSON object with a non-empty `exception.class` string; reads or generates `event_id` with `SecureRandom.uuid_v7`), then `InboundEvent.store_for` with the **encrypted** raw body (a batch stores each event's re-serialised JSON, one row per event, in one INSERT), `ActiveJob.perform_all_later` with one `ProcessInboundEventJob` per row and `ApiKey.record_usage(current_api_key.id)`. Respond 202.
2. **The job argument is only the GlobalID of `InboundEvent`.** Sidekiq/Redis never sees payload bytes, and retry or dead sets hold ids only. Postgres gives the payload durability, a size bound and encryption at rest. Encrypting the job argument was rejected because 512 KiB blobs would sit in Redis memory and in the retry and dead sets for weeks.
3. **Logs:** `IngestBodyShield` middleware (`lib/middleware/ingest_body_shield.rb`, slice A) sets `env["action_dispatch.request.request_parameters"] = {}` for `POST /api/v1/events` and `POST /api/v1/events/batch` (any spelling the router accepts: duplicate or trailing slashes, a format suffix). Rails therefore never parses the body into `params`, and the request log line shows `Parameters: {}`. The controller reads only `request.raw_post`/`request.body`. `config/initializers/filter_parameter_logging.rb` also adds `:q, :text, :chips, :body, :payload, :token, :authorization`.
   ```ruby
   class IngestBodyShield
     PATH = %r{\A/api/v1/events(?:/batch)?(?:\.[^/]*)?\z}  # matched against the normalised path
     def initialize(app) = @app = app
     def call(env)
       env["action_dispatch.request.request_parameters"] = {} if ingest_path?(env["PATH_INFO"])  # normalize_path + PATH
       @app.call(env)
     end
   end
   ```
   In `config/application.rb`: `config.autoload_lib(ignore: %w[assets tasks middleware])`, `require_relative "../lib/middleware/ingest_body_shield"` and `config.middleware.use IngestBodyShield`. (Rack middleware must define `call`; this is the one sanctioned exception to the no-`call` rule.)
4. **Exceptions:** never interpolate payload content into exception messages, because Sidekiq stores error messages in Redis. `JSON::ParserError` is rescued and turned into a discard (§2.4) without its message.

### 2.3 Processing objects (slice C, `app/models/ingest/`)

| Class | Responsibility | Public methods |
|---|---|---|
| `Ingest::RequestBody` | gzip and size cap (`max:`) | `#read` → String (raises `Ingest::PayloadTooLarge`) |
| `Ingest::Envelope` | request-time validation of one event (body, or `data:` from a batch) | `.parse(body)`, `#valid?`, `#errors`, `#event_uuid` |
| `Ingest::Batch` | request-time validation of a batch body | `#valid?`, `#errors`, `#size`, `#items`, `#accepted_items`, `#rejected_items` |
| `Ingest::BatchItem` | one batch event, re-serialised | `#rejected?`, `#rejection`, `#acceptance`, `#event_uuid`, `#body` |
| `Ingest::RateCounter` | weighted fixed-window counter in `Ingest::RateLimitStore` | `#take(amount)`, `#give_back(amount)` |
| `Ingest::EventRateLimit` | per-key and per-account event allowances | `#admit?(events)`, `#give_back(events)` |
| `Ingest::Limits` | constants (§3.4) | — |
| `Ingest::Event` | normalised, scrubbed, truncated event (value object) | `.from_json(json, project:, environment:, received_at:)` (raises `Ingest::MalformedPayload`). Readers: `exception_class`, `message`, `redacted_message`, `frames`, `top_app_frame`, `culprit`, `transaction_name`, `level`, `occurred_at`, `release`, `user_identity`, `tags`, `runtime_label`, `fingerprint`, `request` (`Ingest::RequestSection`), `job` (`Ingest::JobSection#to_h`), `#to_payload_json` |
| `Ingest::Frame` | backtrace frame value (`Data.define`) | `file`, `line`, `method_name`, `in_app?`, `gem_name`, `location` |
| `Ingest::PathNormalizer` | path redaction | `#normalize(path)` |
| `Ingest::MessageRedactor` | §1.5 rules | `#redact(message)` |
| `Ingest::Scrubber` | server-side scrubbing (§2.4) | `#scrub(value)` (deep) |
| `Ingest::Fingerprint` | grouping | `#digest` |
| `Ingest::UserIdentity` | HMACs | `#primary_digest`, `#digests`, `present?` |
| `Ingest::Processor` | orchestration (§2.5) | `#process` |
| `Ingest::IssueTally` | issue upsert and atomic counters | `#find_or_create_issue_id`, `#count(new_user:)` → `Issue` (from `find_by_sql … RETURNING`) |
| `Ingest::Rollups` | hourly, project, tag and user upserts | `#increment` → `new_user?` |
| `ProcessInboundEventJob` | queue `ingest` | `perform(inbound_event)` → `Ingest::Processor.new(inbound_event).process` |
| `TrimOccurrencesJob` | keep newest 1,000 per issue | `perform(issue)` |

### 2.4 Normalisation, scrubbing and fingerprinting

- **Normalisation** (`Ingest::Event`):
  - Apply the limits in §3.4: truncate strings, cap arrays and nesting depth, and coerce scalars to strings in tags.
  - Clamp `occurred_at` to `[received_at − 30.days, received_at + 5.minutes]`, falling back to `received_at`.
  - Use `level` if valid, otherwise `error`.
  - Mark frames `in_app` when the client says so. Otherwise a path is in-app when it starts with `app/`, `lib/` or `config/` and contains neither `/gems/` nor `vendor/bundle`.
  - Take `gem_name` from `gems/<name>-<version>/` or a `<name>-<version>/lib/` path segment.
  - Server-added tags: `environment` (from the key), `release` when present and `host` when `context.host` is present. Client tags win on key conflicts except `environment`.
- **Scrubbing** (`Ingest::Scrubber.new(extra_keys: project.scrub_fields)`) runs over request, params, headers, session, job (fields and arguments), user (except `id`, `email`, `username` and `name`, which are needed and stored encrypted), breadcrumbs, frame locals, context and tags:
  - A hash key matching `/passw|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|authorization|cookie|csrf|xsrf|credit[_-]?card|card[_-]?number|\bcvv\b|\bcvc\b|\bssn\b|\botp\b|session[_-]?id/i`, or listed in `extra_keys` (case-insensitive substring), gets the value `"[FILTERED]"`.
  - String values anywhere (including messages, breadcrumb messages, locals and URLs):
    - Luhn-valid card-shaped digit runs (`(?:\d[ -]?){13,19}`) → `[FILTERED]`; identifiers are matched first and left whole (UUIDs, and words of 20+ hex characters with a letter: Sidekiq jids, Mongo ids, git SHAs)
    - `Bearer \S+` → `Bearer [FILTERED]`
    - JWT-like `eyJ[\w-]+\.[\w-]+\.[\w-]+` → `[FILTERED]`
    - URL query parameters whose names match the key pattern → `[FILTERED]`
- **Fingerprint** (`Ingest::Fingerprint#digest`, SHA-256 hex of the parts joined by `"\x1F"`):
  1. A client `fingerprint` array (≤ 10 strings, each ≤ 200 chars) gives `["custom", *parts]`.
  2. Otherwise, with a top app frame: `["v1", exception_class, frame.file, frame.method_name]`. Line numbers are excluded so edits don't split issues.
  3. Otherwise: `["v1", exception_class, redacted_message]`.
- **Culprit:** the top app frame as `"#{file}:#{line} in #{method}"`, or the first frame, or nil. **runtime_label** is `"Rails 8.0 · Ruby 3.4"`, built from `context.runtime` (major.minor).

### 2.5 `Ingest::Processor#process`: one transaction, short locks

```
load inbound_event (job) + project (1 query)
event = Ingest::Event.from_json(...)            # MalformedPayload → inbound_event.destroy; log id only; return
issue = nil
tally = Ingest::IssueTally.new(project, event).prepare   # SELECT id …; if none: allocate the number now, in its own statement
ApplicationRecord.transaction do
  issue_id = tally.find_or_create_issue_id     # if none: INSERT … ON CONFLICT DO NOTHING RETURNING id; reselect on conflict
  Occurrence.insert(…, unique_by: %i[project_id uuid], returning: %i[id])  → empty result ⇒ duplicate ⇒ raise ActiveRecord::Rollback
  rollups  = Ingest::Rollups.new(issue_id, project, event)
  new_user = rollups.increment_issue           # issue hourly, tags (multi-row, sorted, bounded), issue_users
  issue    = tally.count(new_user:)            # the ONLY lock on the issue row (FOR NO KEY UPDATE), held until commit
  IssueActivity regressed row if issue.previous_status == "resolved"
  IssueActivity reached_production row if issue.just_reached_production   # system rows, issue row still locked
  project.record_first_event(...) if tally.created?   # writes only when something changes
  inbound_event.destroy!
  rollups.increment_project                    # project hourly: the hottest row, locked last
end
after commit (only if issue): issue.broadcast_changes_later(created: tally.created?); project.broadcast_changes_later;
                               TrimOccurrencesJob.perform_later(issue) if (issue.events_count % 250).zero?
```

**Issue creation** (only when the plain `SELECT id FROM issues WHERE project_id = ? AND fingerprint = ?` finds nothing):
`project.allocate_issue_number` (in `IssueTally#prepare`, before the transaction, so the projects row is not locked for the whole transaction), then `Issue.insert({ …, events_count: 0, users_count: 0, status: "unresolved", environments: [env], first_seen_at:, last_seen_at: }, unique_by: %i[project_id fingerprint], returning: %i[id])`. If that loses a race (empty result), reselect the id. The burnt number leaves a harmless gap.

**Counting** (`IssueTally#count`): a single statement via `Issue.find_by_sql`, so it needs no extra query and returns an `Issue` with the extra attributes `previous_status` and `just_reached_production`:
```sql
WITH previous AS (
  SELECT id, status, reached_production_at FROM issues WHERE id = :issue_id FOR NO KEY UPDATE
)
UPDATE issues SET
  events_count  = issues.events_count + 1,
  users_count   = issues.users_count + :new_user,
  first_seen_at = LEAST(issues.first_seen_at, :occurred_at),
  last_seen_at  = GREATEST(issues.last_seen_at, :occurred_at),
  environments  = CASE WHEN :env = ANY(issues.environments) THEN issues.environments
                       ELSE array_append(issues.environments, :env) END,
  status        = CASE WHEN issues.status = 'resolved' THEN 'unresolved' ELSE issues.status END,
  regressed_at  = CASE WHEN issues.status = 'resolved' THEN :now ELSE issues.regressed_at END,
  resolved_at   = CASE WHEN issues.status = 'resolved' THEN NULL ELSE issues.resolved_at END,
  reached_production_at = CASE
    WHEN :production AND issues.reached_production_at IS NULL
         AND NOT (issues.environments && ARRAY[:production_names]::varchar[]) THEN :now
    ELSE issues.reached_production_at END,
  updated_at    = :now
FROM previous WHERE issues.id = previous.id
RETURNING issues.*, previous.status AS previous_status,
  (previous.reached_production_at IS NULL AND issues.reached_production_at IS NOT NULL) AS just_reached_production
```
Ignored issues stay ignored. Only `resolved` regresses.

**Reached production:** `:production` is `EnvironmentTone.production?(event.environment)` and `:production_names` is its coral group (`production prod live`). Environment names are lowercase (ApiKey validates them), so the array overlap is exact. The `environments` tested are the pre-update ones, so an issue created by a production event (environments `[production]`) never qualifies, and the stamp happens once: later events see a production environment and a non-null column. The issue row lock makes concurrent production events of a staging-only issue stamp it exactly once (`concurrent_processing_test.rb`). The processor then inserts one system `reached_production` activity, before the project hourly row as for `regressed`. The issue's existing pointer broadcast refreshes open pages; no new broadcast. The lock is `FOR NO KEY UPDATE`, not `FOR UPDATE`: the occurrence, rollup and activity inserts take `FOR KEY SHARE` on the issue through their foreign keys, and `FOR UPDATE` conflicts with that, which deadlocked concurrent events of one issue (`test/models/ingest/concurrent_processing_test.rb`).

**Rollups** (`Ingest::Rollups#increment_issue`, then `#increment_project` last), all `upsert`/`upsert_all` with `on_duplicate: Arel.sql(...)` and `record_timestamps: false`:
- `issue_hourly_counts (issue_id, hour)`: `count = issue_hourly_counts.count + 1`
- `project_hourly_counts (project_id, environment, hour)`: `count + 1`
- `issue_tag_counts`: one multi-row upsert, rows **sorted by `[key, value_digest]`** to avoid deadlocks; `count + 1`. The encrypted `value` is written only on insert. `Ingest::TagRows` bounds the table per issue: at most `IssueTagCount::VALUES_PER_KEY` (100) values per key, later new values counting towards one "Other values" row (`value_digest = "other"`), and at most `KEYS_PER_ISSUE` (40) keys, later new keys being dropped. Known values cost one indexed lookup.
- `issue_users` (when the event has an identity): `on_duplicate: "events_count = issue_users.events_count + 1, last_seen_at = GREATEST(issue_users.last_seen_at, EXCLUDED.last_seen_at)"`, `returning: Arel.sql("(xmax = 0) AS inserted")`, so `new_user? = inserted`.

**Lock ordering and concurrency:**
- Hot rows are touched last and in a fixed order: per-issue rollups, then the issue counter UPDATE, then the project hourly row (shared by every event of the project, environment and hour) as the last statement before COMMIT. A new issue's number is reserved before the transaction. Transactions stay short.
- The job uses `retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5` and `discard_on ActiveJob::DeserializationError` (the inbound event was already processed).
- Redelivery is safe: the `inbound_event.destroy!` commits atomically with the counts, and occurrence uniqueness on `(project_id, uuid)` drops client retries.
- Known ceiling: a single extremely hot issue serialises on its counter rows. Buffering counters in Redis is future work and is not built in v1.

### 2.6 Query budget

- **Request:** 1 INSERT (multi-row for a batch), plus at most 1 throttled UPDATE (`last_used_at`), plus cache reads and counter increments, plus one (bulk) enqueue.
- **Job, existing issue:** inbound + project + select issue + occurrence + 4 upserts + issue UPDATE + delete, about 10 statements. A new issue adds 3 more. A regression, and the one event that takes an issue to production, each add one activity INSERT.

### 2.7 Maintenance (slice C, `lib/tasks/goodsorcery.rake`)

- `goodsorcery:prune` deletes occurrences older than `project.retention_days` (`in_batches(of: 1_000).delete_all`), `issue_users` rows and `issue_tag_counts` of issues not seen within it, `issue_hourly_counts` / `project_hourly_counts` older than 90 days (one `hour` slice per DELETE, using the `hour` indexes) and inbound events still unprocessed after a day (deleted unread, logged by id). Schedule it daily with cron or a Kamal accessory, as documented in `docs/INGEST_API.md` › Operating.
- `goodsorcery:requeue_stale` re-enqueues `InboundEvent.stale`.
- `TrimOccurrencesJob` keeps the newest `Occurrence::RETAINED_PER_ISSUE` per issue. The cutoff id is `issue.occurrences.latest_first.offset(1_000).pick(:id)`.
- `config/sidekiq.yml` queues: `[ingest, 3]`, `[default, 2]`, `[mailers, 1]`.

---

## 3. Ingest API payload format

The full public doc is `docs/INGEST_API.md` (written now, maintained by slice C). The summary follows.

### 3.1 Request

```http
POST /api/v1/events
Authorization: Bearer gs_live_9f2c…
Content-Type: application/json
Content-Encoding: gzip          (optional)
User-Agent: goodsorcery-ruby/0.1.0
```

### 3.2 Body (only `exception.class` is required)

```json
{
  "event_id": "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1",
  "occurred_at": "2026-10-04T09:14:03.112Z",
  "level": "error",
  "release": "a1b2c3d",
  "transaction": "CheckoutsController#create",
  "exception": {
    "class": "NoMethodError",
    "message": "undefined method `price_cents' for nil",
    "backtrace": [
      {
        "file": "app/services/cart_total.rb", "line": 42, "method": "line_total", "in_app": true,
        "context": { "start_line": 39, "lines": ["def line_total(item)", "  variant = item.variant || item.product.default_variant", "  # TODO", "  variant.price_cents * item.quantity", "end"] },
        "locals": { "item": "#<CartItem id: 88123, variant_id: 4410>", "variant": "nil" }
      },
      { "file": "gems/activerecord-8.0.1/lib/active_record/relation.rb", "line": 338, "method": "records", "in_app": false }
    ]
  },
  "request": {
    "url": "https://shop.acme.dev/checkout", "method": "POST", "format": "text/html",
    "request_id": "7d4c2a91-1e0f-4b8e-a2d1-55f0c8e1b0aa", "remote_ip": "81.2.69.160",
    "params": { "cart_id": 88123, "coupon": "FALL25", "card_token": "[FILTERED]" },
    "headers": { "Accept": "text/html", "User-Agent": "Mozilla/5.0 …", "Referer": "https://shop.acme.dev/cart" },
    "session": { "user_id": 5521, "cart_id": 88123 }
  },
  "user": { "id": "5521", "email": "mara@example.com", "username": "mara", "name": "Mara Lindqvist" },
  "breadcrumbs": [
    { "timestamp": "2026-10-04T09:14:02.700Z", "category": "request", "message": "POST /checkout" },
    { "timestamp": "2026-10-04T09:14:02.741Z", "category": "sql", "message": "User Load (0.6ms)", "data": { "sql": "SELECT \"users\".* FROM \"users\" WHERE \"id\" = $1" } },
    { "timestamp": "2026-10-04T09:14:02.822Z", "category": "http", "message": "GET api.taxjar.com/v2/rates/94107", "data": { "status": 200, "duration_ms": 212 } },
    { "timestamp": "2026-10-04T09:14:03.091Z", "category": "log", "level": "warning", "message": "Cart 88123 contains discontinued variant 4410" }
  ],
  "context": {
    "runtime": { "ruby": "3.4.1 (YJIT on)", "rails": "8.0.1" },
    "host": "web-7f9c-2",
    "process": "puma · pid 4412 · thread 23",
    "env": { "RAILS_ENV": "production" }
  },
  "tags": { "browser": "Mobile Safari", "coupon": "FALL25" },
  "fingerprint": ["optional", "custom", "grouping"],
  "notifier": { "name": "goodsorcery-ruby", "version": "0.1.0" }
}
```

The environment always comes from the API key, so environment keys in the payload are ignored. Breadcrumb `category` is one of `request controller sql http cache log job custom`; anything else becomes `custom`. Breadcrumb `level` is `debug info warning error`. An error raised in a background job (Active Job, `deliver_later` mailers, Sidekiq) sends a top-level `job` object instead of `request` (fields in `docs/INGEST_API.md` › Background jobs); unknown job keys are dropped and `job.arguments` is bounded and scrubbed like `params`.

### 3.3 Stored (normalised) occurrence payload: `Occurrence#payload` JSON

```json
{ "exception": { "class": "...", "message": "...(scrubbed, ≤10k)",
                 "backtrace": [{ "file","line","method","in_app","gem","context":{"start_line","lines"},"locals":{} }] },
  "transaction": "...", "request": { "url","method","format","request_id","remote_ip" },
  "params": {}, "headers": {}, "session": {},
  "job": { "framework","class","mailer","action","id","provider_job_id","queue","priority","executions","retry_count",
           "enqueued_at","scheduled_at","arguments": [] },
  "user": { "id","email","username","name" },
  "breadcrumbs": [{ "offset_ms": -412, "category","level","message","data":{} }],
  "context": {}, "tags": {}, "notifier": {} }
```
`offset_ms` is computed server-side relative to `occurred_at`. Slice F reads only this shape, through the `Occurrence` readers.

### 3.4 Limits (`Ingest::Limits`)

| Item | Limit |
|---|---|
| body | 512 KiB (compressed and decompressed) |
| exception.class | 1–255 chars |
| exception.message | 10,000 chars stored; issue title 1,024 after redaction |
| backtrace | first 250 frames; context ≤ 11 lines × 500 chars; locals ≤ 25 × 500 chars |
| breadcrumbs | last 100; message ≤ 1,000; data ≤ 20 keys |
| tags | 25 pairs; key `/\A[a-z0-9_.\-]{1,32}\z/i` (others dropped); value ≤ 200 chars |
| request/params/headers/session/context/job.arguments | depth ≤ 6, arrays ≤ 50 items, hashes ≤ 100 keys, strings ≤ 4,096 chars |
| job fields | ≤ 255 chars each (`JOB_FIELD`), stored as strings; unknown job keys dropped |
| user fields | ≤ 255 chars each |
| fingerprint | ≤ 10 strings × 200 chars |
| release | ≤ 64 chars; transaction ≤ 255 |
| batch | body 2 MiB (compressed and decompressed); 1–100 events; each ≤ 512 KiB re-serialised |
| rate | 1,200 events/min per key; 6,000 events/min per account (a batch of N counts N); 6,000 req/min per IP; `/verify` 60/min per key |

---

## 4. Web layer

### 4.1 `config/routes.rb` (final; slice A writes exactly this)

```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :events, only: :create
      namespace :events do
        resource :batch, only: :create
      end
      get "verify", to: "verifications#show", as: :verification
    end
  end

  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :registration, only: %i[new create]

  resource :search, only: :show
  resource :recent_issues, only: :show

  resources :projects, only: %i[index new create edit update] do
    scope module: :projects do
      resource :setup, only: :show
      resource :card, only: :show
      resource :listening, only: :show
      resource :summary, only: :show
      resource :bulk_triage, only: :create
      resources :api_keys, only: %i[show create] do
        scope module: :api_keys do
          resource :reveal, only: :show
          resource :rotation, only: :create
        end
      end
    end

    resources :issues, only: %i[index show] do
      scope module: :issues do
        resource :row, only: :show
        resource :stats, only: :show
        resource :chart, only: :show
        resource :resolution, only: %i[create destroy]
        resource :ignore, only: %i[create destroy]
        resource :assignment, only: %i[update destroy]
        resources :occurrences, only: :show
        resources :notes, only: :create
      end
    end
  end

  root "projects#index"
end
```
Params: project `:project_id`/`:id` is the slug. Issue `:issue_id`/`:id` is the short id `GS-1042`. Occurrence `:id` is a uuid or one of `latest`, `oldest`, `random`.

### 4.2 Controllers

Shared (slice A):
- `ApplicationController`:
  - `include Authentication`, `allow_browser versions: :modern`, `stale_when_importmap_changes`.
  - `around_action :use_user_time_zone` (`Time.use_zone(Current.user&.time_zone || "UTC")`).
  - `after_action :forbid_caching`, which sets `Cache-Control: no-store` for every dashboard response.
- `Authentication` is the generator concern, changed so that `start_new_session_for(user)` creates the session with `account: user.default_account`. Sessions expire 30 days after sign-in or after 7 idle days (`Session.active`; activity is recorded at most hourly), and the cookie expires with them. Sign-in and reset requests are also rate-limited per email address (`EmailRateLimited`, keyed by an HMAC of the address). The password reset token travels as `?token=` (`/password/edit`) and a form field, never in the path, so the request log filters it.
- `ProjectScoped`: `before_action :set_project`, which runs `@project = Current.account.projects.find_by!(slug: params[:project_id])`.
- `RemembersEnvironment` (included by `ApplicationController`): the issue list's environment choice per project.
  - `choose_environment(project, query)` builds an `EnvironmentChoice` (model) from the query's `env:` chip, `params[:env]` and the remembered cookie, and writes the cookie when the choice is explicit and known (`EnvironmentChoice#remember?`).
  - One cookie for all projects: `cookies.signed[:issues_environments]`, a hash of project id (string) => environment name, `""` for all environments (`EnvironmentChoice::ALL`). Each new choice moves its project to the end and only the last `REMEMBERED_PROJECTS` (20) are kept, so the Cookie header stays small however many apps a viewer opens (one cookie per project would grow to ~18KB at 100 apps and could push the session cookie past the browser's per-domain cap). 1 year, `httponly`, `same_site: :lax` (and `secure` through `force_ssl`). The signature stops tampering, the project id key binds each value to its project, and remembered values are also checked against the project's environments.
  - **Hover prefetch:** Turbo 8 prefetches a link after ~100ms of hover (`X-Sec-Purpose: prefetch`) and reuses that response on click. Every link on the issues page states an environment, so a prefetch would otherwise rewrite the remembered choice. The filter bar, tabs and switch section, the scope bar and the load-more frame carry `data-turbo-prefetch="false"` (a real click is then always a fresh request that remembers), and `choose_environment` never remembers on a request whose `X-Sec-Purpose`/`Sec-Purpose` says prefetch. Issue row links keep prefetch.
  - `issues_environment_for` is memoised per project for the request (the switcher subtitle and the badge both read it).
  - `issues_environment_for(project)` (a helper method) is the environment the project's issue list shows: this request's choice on the issue list, otherwise remembered > `default_environment` > all. The sidebar badge counts for it.
- `IssueScoped`: includes `ProjectScoped`; `@issue = @project.issues.find_by_short_id!(params[:issue_id])`.
- `SessionsController`, `PasswordsController` (generator, `layout "auth"`), `RegistrationsController` (`new`/`create` via `Signup`; `rate_limit to: 10, within: 3.minutes, only: :create`; `allow_unauthenticated_access`). Sign-up (`Signup.open?`) is open only until the first account exists, unless `GOODSORCERY_ENABLE_SIGNUPS=1`; `GOODSORCERY_DISABLE_SIGNUPS=1` closes it completely. Closed sign-up redirects to sign-in.

| Controller | Slice | Actions | Notes |
|---|---|---|---|
| `Api::V1::EventsController` | C | create | §2.1 |
| `Api::V1::Events::BatchesController` | C | create | §2.1.1 |
| `Api::V1::VerificationsController` | C | show | §2.1.2 |
| `ProjectsController` | D | index, new, create, edit, update | index = overview; create → `redirect_to project_setup_path`; edit/update = Settings › General (name, platform, issue_prefix, scrub_fields as comma list, retention_days, default_environment: a select of "All environments" (blank) plus `project.environments`) |
| `Projects::SetupsController` | D | show | Setup & API keys page |
| `Projects::CardsController` | D | show | live frame `dom_id(project, :card)` |
| `Projects::ListeningsController` | D | show | live frame `dom_id(project, :listening)` |
| `Projects::ApiKeysController` | D | show (masked row frame), create (new environment key → turbo_stream append) | |
| `Projects::ApiKeys::RevealsController` | D | show | frame `dom_id(api_key, :token)` with the full token and Copy/Hide |
| `Projects::ApiKeys::RotationsController` | D | create | `button_to … data: { turbo_confirm: "The old key stops working immediately." }`; turbo_stream replaces the row in revealed state |
| `RecentIssuesController` | D | show | live frame `dom_id(Current.account, :recent_issues)` |
| `IssuesController` | E | index, show | `index` scopes the parsed `IssueQuery` to the resolved environment (`query.with_environment(choose_environment(@project, query).environment)`), so the `env:` chip is the one filter the list, tab counts and summary frame read. `show` is exactly: `@occurrence = @issue.occurrences.latest` and renders `issues/show` (template owned by F). Uses its own `set_issue` with `params[:id]` |
| `Projects::SummariesController` | E | show | live frame `dom_id(project, :summary)`, `period` param |
| `Projects::BulkTriagesController` | E | create | params `issue_ids[]` (max 100, scoped `@project.issues.where(id:)`), `triage` ∈ resolve/ignore/reopen or `assignee_id` (must be an account member). Redirects back to the list with a notice |
| `Issues::RowsController` | E | show | live frame `dom_id(issue, :row)` |
| `SearchesController` | E | show | global search. A short id like `/\A[A-Z]{1,6}-\d+\z/i` redirects to that issue in the account; otherwise shows projects by name plus issues across the account (limit 20, `includes(:project)`) |
| `Issues::OccurrencesController` | F | show | `OccurrenceNavigator#find(params[:id])`, renders `issues/show` |
| `Issues::ChartsController` | F | show | frame `dom_id(issue, :chart)`, `period` ∈ 24h/7d/30d |
| `Issues::StatsController` | F | show | live frame `dom_id(issue, :stats)` |
| `Issues::ResolutionsController` | F | create (resolve), destroy (reopen) | redirect to issue |
| `Issues::IgnoresController` | F | create, destroy (reopen) | redirect |
| `Issues::AssignmentsController` | F | update (`assignee_id`, members only), destroy | redirect |
| `Issues::NotesController` | F | create | turbo_stream prepends the activity item and resets the form |

All dashboard controllers inherit `ApplicationController`. Feature controllers `include ProjectScoped` or `IssueScoped`. Frame endpoints render `layout false` partials wrapped in the matching `turbo_frame_tag`. Turbo-rails already uses its frame layout for `Turbo-Frame` requests.

### 4.3 Turbo Frames

| Frame id | Where | Purpose |
|---|---|---|
| `dom_id(issue, :row)` | issue list row (`target="_top"`) | live reload of one row |
| `dom_id(project, :new_issues)`, or `"#{dom_id(project, :new_issues)}_<env>"` when the list is scoped to one environment | a container (plain `div`) above the rows, rendered only in the default list state (Unresolved tab, no extra chips apart from `env:`, default sort, page 1; `IssueQuery#default_view?`) | live prepend target, per environment scope (`LiveFrames#new_issues_target(environment)`) |
| `dom_id(project, :summary)` | list summary strip | live and period switch |
| `issues_page_<n>` | list pagination ("Showing 25 of 230 · load more") | lazy "load more" |
| `occurrence` (`data-turbo-action="advance"`) | detail: wraps the whole two-column grid below the hero | occurrence navigator |
| `dom_id(issue, :chart)` | detail occurrences chart | 24h/7d/30d tabs and live reload |
| `dom_id(issue, :stats)` | detail stat ribbon | live reload |
| `dom_id(project, :card)` | overview card | live reload |
| `dom_id(account, :recent_issues)` | overview "Across all projects, last hour" feed | live reload |
| `dom_id(project, :listening)` | setup page step-3 panel (and its stepper) | live reload |
| `dom_id(api_key, :token)`, `dom_id(api_key)` | setup page key row | reveal/hide/rotate |

### 4.4 Live updates (slice G): pointer broadcasts over Action Cable

**The rule:** broadcasts never carry captured data. They carry Turbo Stream *pointers*, and each client re-fetches the fragment over HTTPS with its own session, so normal authorisation applies. Redis pub/sub therefore only ever sees dom ids and paths.

- **Custom stream action `reload_frame`** (slice B, `app/javascript/stream_actions.js`, imported by `application.js`):
  ```js
  import { Turbo } from "@hotwired/turbo-rails"
  Turbo.StreamActions.reload_frame = function () {
    const src = this.getAttribute("src")
    this.targetElements.forEach((frame) => {
      frame.getAttribute("src") === src ? frame.reload() : frame.setAttribute("src", src)
    })
  }
  ```
  Setting `src` on an existing frame swaps its content in place without a flash.
- **Streams and subscriptions.** Views place these with `live_stream_from` (B helper), which is `turbo_stream_from(*streamables, channel: "AuthorizedStreamsChannel")`:
  | Stream | Placed in (slice) |
  |---|---|
  | `[account, :projects]` | `projects/index` (D) |
  | `[project, :issues]` | `issues/index` (E) |
  | `[issue]` | `issues/show` (F) |
  | `[project, :setup]` | `projects/setups/show` (D) |
- **`AuthorizedStreamsChannel`** (G) is the custom channel from the turbo-rails docs:
  ```ruby
  class AuthorizedStreamsChannel < ApplicationCable::Channel
    extend Turbo::Streams::Broadcasts, Turbo::Streams::StreamName
    include Turbo::Streams::StreamName::ClassMethods
    STREAMABLES = [ Account, Project, Issue ].freeze

    def subscribed
      stream_name = verified_stream_name_from_params
      if stream_name && streamable(stream_name)&.accessible_by?(current_user)
        stream_from stream_name
      else
        reject
      end
    end

    private
      def streamable(stream_name)
        GlobalID::Locator.locate(stream_name.split(":").first, only: STREAMABLES)
      rescue ActiveRecord::RecordNotFound
        nil
      end
  end
  ```
  The signature stops tampering, and the membership check also rejects stale signed names after a user loses access. `ApplicationCable::Connection` (A, from the generator) identifies `current_user` from the signed `session_id` cookie and rejects anonymous connections.
- **Broadcasting.** G replaces the A stubs `Issue::Broadcasting` and `Project::Broadcasting`:
  - `Issue#broadcast_changes_later(created: false)`:
    - When `created`, it runs `BroadcastIssueChangesJob.perform_later(self, created: true)` immediately: a prepend of `turbo_frame_tag(dom_id(issue, :row), src: project_issue_row_path(project, issue), target: "_top")` into the all-environments container `dom_id(project, :new_issues)` and into the container of each environment in `issue.environments` (one at creation), so a list scoped to staging never gets a new production issue. Environment names come from API keys (`[a-z0-9_-]`), not from captured data.
    - Otherwise it is debounced. When `Rails.cache.write(["live", "issue", id], 1, unless_exist: true, expires_in: 2.seconds)` succeeds, it runs `BroadcastIssueChangesJob.set(wait: 2.seconds).perform_later(self)`, which sends `reload_frame` for stats and chart on `[issue]`. List rows are reloaded by the project broadcast below.
  - `Project#broadcast_changes_later` uses the same debounce with key `["live", "project", id]`, then `BroadcastProjectChangesJob`. That job sends `reload_frame` for summary on `[project, :issues]`, for card on `[account, :projects]` and for listening on `[project, :setup]`, plus one `reload_rows` action on `[project, :issues]` (target `dom_id(project, :issues)`, src `project_rows_path`): each browser fetches all its visible row frames in one request (`?ids=…`, at most 200, answered with `turbo_stream.replace` per row and a fixed number of queries). The account-wide recent feed is debounced per account (`["live", "recent_issues", account_id]`) and sent by `BroadcastRecentIssuesJob`, so N busy projects send one feed reload per window, not N.
  - Use `Turbo::StreamsChannel.broadcast_action_to(*streamables, action: :reload_frame, target:, attributes: { src: path })`. Paths come from `Rails.application.routes.url_helpers` inside a small PORO `LiveFrames` (G), which has `#row_path`, `#stats_path` and so on. Job arguments are GlobalIDs only.
- **Selection survives reloads:** `bulk_selection_controller` (E) keeps selected ids in a Set and re-applies them on `turbo:frame-load`.

### 4.5 Stimulus controllers

| Controller | Slice | Purpose |
|---|---|---|
| `dropdown` | B | menus: project switcher, sort, filters, resolve split ▾, assign, user menu. Closes on outside click and Escape |
| `tabs` | B | client-side tabs (`aria-selected`, `hidden` panels): install snippets, context tabs |
| `clipboard` | B | copy `source` target text; label shows "Copied ✓" for 1.2 s |
| `toggle` | B | `aria-pressed` switch showing/hiding targets (framework frames) |
| `timezone` | B | fills the hidden `time_zone` field on sign-up from `Intl.DateTimeFormat().resolvedOptions().timeZone` |
| `flash` | B | auto-dismiss notices after 5 s |
| `bulk_selection` | E | checkboxes, select-all, floating bar visibility and count, Set persistence |
| `breadcrumb_filter` | F | all/sql/http/log chips filter the timeline |

Delete `hello_controller.js` (B). There is no chart JS, because all charts are server-rendered SVG (§7.4).

### 4.6 Cross-slice stubs (A creates, G replaces)

A creates `app/models/issue/broadcasting.rb` and `app/models/project/broadcasting.rb`, each with `def broadcast_changes_later(...) = nil` and a comment `# Implemented by slice G`. These are the only files whose ownership transfers.

---

## 5. Caching plan

**Store:** memory store in development, null store in test, Redis cache store in production. Fragment caching applies when `perform_caching` is on.

| What | Key | TTL | Owner |
|---|---|---|---|
| API key credential (ids and environment only, nil cached too) | `["api_key", digest]` | 5 min; deleted on rotate | A |
| Rate-limit counters | Rails `rate_limit` | 1 min | C |
| `last_used_at` throttle gate | `["api_key_used", id]` | 1 min | A |
| Live-update debounce gates | `["live", "issue"/"project", id]` | 2 s | G |
| Account events-this-month | `[account, :events_this_month, month]` | 5 min | A |
| Issue list summary numbers | `["summary", project.id, env, period]` | 30 s | E |
| Unresolved counts (sidebar badge, list heading), per environment or all (nil) | `["unresolved_count", project.id, env]` | 10 s; triage deletes the all and per-key-environment entries | A |
| Issue chart series 7d/30d (numbers only) | `["issue_chart", issue.id, period]` | 5 min (24h is uncached so live reloads are fresh) | F |

**Counter caches:** `issues.events_count` and `issues.users_count` are maintained by atomic SQL. There are deliberately **no** project-level counter caches, because they would be a hot row on every event and would drift on bulk triage. Unresolved and new counts per project come from one grouped query on `[project_id, status, …]` indexes. Last error time comes from `MAX(last_seen_at)` grouped.

**Never cached in any shared store:**
- decrypted data of any kind (occurrence payload, tag values, notes, tokens)
- issue text columns (message, culprit), even though they are redacted
- user identifiers
- rendered HTML containing any of the above

Only ids, numbers and SVG series data are cached.

**HTTP:** all dashboard responses send `Cache-Control: no-store`. The setup page adds `<meta name="turbo-cache-control" content="no-cache">` so a revealed key is never restored from Turbo's snapshot cache.

---

## 6. Authorization

- **Dashboard:**
  - Every lookup starts from `Current.account` (`Current.account.projects…`, then `@project.issues…`, `@issue.occurrences…`).
  - `find_by!` misses give 404. Never call `Project.find`, `Issue.find` or `Occurrence.find` unscoped in controllers.
  - Bulk ids are filtered through `@project.issues.where(id:)`. Assignees are validated as members of `Current.account`.
  - Search is limited to `Current.account`'s projects.
  - The account's own data is not role-gated in v1 (`member` and `owner` have equal rights).
- **Action Cable:** an authenticated connection is required, plus a signed stream name **and** `accessible_by?(current_user)` (§4.4).
- **Ingest:** the API key identifies `project_id` and `environment` and nothing else. Keys cannot read data. CORS is not enabled (server-to-server only).
- **Tests (every feature slice):** for each controller, add a test showing that a user from another account (`users(:outsider)`) gets 404 for the slice's project, issue and key URLs.

---

## 7. Theme, layout and shared UI (slice B)

### 7.1 Tailwind v4: `app/assets/tailwind/application.css`

```css
@import "tailwindcss";

@theme {
  --color-paper-950: #f7f6f3; --color-paper-900: #ffffff; --color-paper-850: #f4f3ef; --color-paper-800: #efeee9;
  --color-paper-700: #e7e5df; --color-paper-600: #d7d4cc; --color-paper-500: #b5b1a7;
  --color-ink-50: #23253a; --color-ink-100: #34374d; --color-ink-200: #4b4e66; --color-ink-300: #62667e; --color-ink-400: #80849a;
  --color-iris-100: #e6e7ff; --color-iris-200: #4b50c4; --color-iris-300: #5a5fd6; --color-iris-400: #7f85ea; --color-iris-500: #8f94ee; --color-iris-600: #6f75e0;
  --color-coral-100: #ffe3e5; --color-coral-300: #cf4657; --color-coral-400: #f2818c; --color-coral-500: #ef6f7c; --color-coral-600: #d9525f;
  --color-mint-100: #daf4e9; --color-mint-300: #23865f; --color-mint-400: #6fcca6; --color-mint-500: #5cc29a;
  --color-lilac-100: #efe8ff; --color-lilac-300: #7353c9; --color-lilac-400: #b39cf2;
  --font-sans: "Figtree", ui-sans-serif, system-ui, sans-serif;
  --font-mono: "JetBrains Mono", ui-monospace, monospace;
  --radius-panel: 16px;
}

@utility font-display { font-family: "Bricolage Grotesque", ui-sans-serif, sans-serif; font-weight: 650; letter-spacing: -0.02em; }
```

Then `@layer base`:
- `html`/`body` get the paper background, ink-100 text, Figtree and antialiasing.
- `::selection` and scrollbar styles.
- `[hidden] { display: none !important }`.
- `turbo-frame { display: block }`.

`@layer components` ports `theme.css` one-to-one, with these changes:
- `.panel`, `.btn`, `.btn-primary`, `.input`, `.tab` (`[aria-selected=true]`), `.chip`, `.code`, `.tok-k/.tok-s/.tok-c/.tok-sym/.tok-n`, `.rise` and `.rise-1…5` (keyframes), `.coral-dot` (keyframes), `.rune-rule`, and `.toggle .track/.knob` (`[aria-pressed=true]`) are ported directly.
- `.nav-link` uses `[aria-current=page]` instead of `.active`.
- The mockup's `!`-override combinations are replaced by tone variants: `.chip-coral`, `.chip-lilac`, `.chip-mint`, `.chip-iris`, `.chip-muted`, `.chip-sm`, `.btn-mint`, `.btn-sm`, and `.segmented` with `[aria-current=true]` for the 1h/24h/7d/30d switchers.

Other rules:
- Use utility classes from the mockups as written (e.g. `bg-iris-500/10`, `w-[248px]`). Class names must be complete literal strings, never interpolated.
- `app/assets/stylesheets/application.css` stays an empty manifest.

### 7.2 Fonts and CSP

- The layout `<head>` loads Google Fonts: two preconnect links (`fonts.googleapis.com`, and `fonts.gstatic.com` with `crossorigin`) plus the stylesheet URL from `theme.css` line 1.
- `config/initializers/content_security_policy.rb` (B) is enabled:
  - `default_src :self`; `script_src :self`; `style_src :self, "https://fonts.googleapis.com"`; `font_src :self, "https://fonts.gstatic.com"`; `img_src :self, :data`; `connect_src :self`; `object_src :none`; `base_uri :self`; `form_action :self`; `frame_ancestors :none`.
  - `content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }` and `nonce_directives = %w[script-src style-src]` (importmap and the Turbo progress bar use the nonce via `csp_meta_tag`).
- **Consequence:** no inline `style=""` attributes anywhere. All dynamic geometry (bars, sparklines, tag bars, quota meter) is SVG attributes produced by `ChartHelper`.

### 7.3 Layouts and shared partials

- `layouts/application.html.erb` is the authenticated shell:
  - `<body class="min-h-screen">` → `div.flex` → sidebar `<aside class="hidden lg:flex w-[248px] shrink-0 flex-col border-r border-iris-500/10 bg-paper-900/60 backdrop-blur sticky top-0 h-screen">` + `<main class="flex-1 min-w-0">`.
  - `main` holds the topbar, then flash, then `yield`.
  - `<title>` is `"#{yield(:title)} — Good Sorcery"`.
- `layouts/_sidebar.html.erb`:
  - logo (`shared/_sigil`) and the "Good Sorcery / Error Tracker" wordmark
  - `layouts/_project_switcher` (dropdown of `Current.account.projects`; the button shows name and `sidebar_project_subtitle`: the environment the project's issue list shows (`issues_environment_for`) in its tone, or a muted "all environments", then `runtime_label || platform`)
  - nav section "Grimoire": Projects; Issues with an unresolved badge for `sidebar_project` (`sidebar_issues_badge`), counted for the environment its issue list shows (`issues_environment_for`, §4.2), tinted in that environment's tone (`environment_bar_classes`; coral for all environments) with a title such as "23 unresolved in staging"; Alerts as "soon" (not a link)
  - "Coming from the suite": Uptime ("soon")
  - "Project": "Settings & setup" → `project_setup_path(sidebar_project)`; Docs → `docs_url` (external)
  - `layouts/_usage_meter` (events this month / quota, hidden when quota is nil)
  - `layouts/_user_menu` (initials, name, "Account name · Hosted" or "Self-hosted" by `ENV["GOODSORCERY_HOSTED"]`, dropdown with Sign out)
- `layouts/_topbar.html.erb` is a sticky `h-14` bar with the breadcrumb trail on the left and the global search form (GET `search_path`, `name="q"`, placeholder "Search projects and issues…") on the right.
- `layouts/auth.html.erb` is a centred single panel with the sigil, used by sessions, passwords and registrations.
- `layouts/_flash.html.erb` shows notices as `chip-mint` and alerts as `chip-coral`, inside a `.panel`.
- `shared/_sigil.html.erb` is the SVG from `shell.js`. `shared/_empty_state.html.erb` takes locals `title`, `body` and an optional `action`.
- Views declare `provide :title`, `provide :nav, "issues"` and `breadcrumb "Acme Labs", projects_path` calls.

### 7.4 Shared helpers (B)

- `ApplicationHelper`: `docs_url`, `hosted?`.
- `NavigationHelper`:
  - `breadcrumb(label, path = nil)` collects crumbs; `breadcrumbs` returns them.
  - `nav_link_to(label, path, key:, icon:, badge: nil)` sets `aria-current="page"` when `content_for(:nav) == key`.
  - Issue page helpers are split by section: `IssueDetailHelper` (hero, chart, navigator, backtrace), `BreadcrumbsHelper`, `IssueContextHelper` (context tabs, affected user), `IssueTagsHelper`, `IssueActivityHelper`, and `CapturedDataHelper` (rendering any captured value, `pretty_json`). The affected user's hit count comes from `OccurrenceNavigator#user_hits`.
  - Browser tests (`test/system`, headless Chrome, run by `bin/rails test:system`) cover the Stimulus controllers and the `reload_frame` / `reload_rows` stream actions.
  - `sidebar_project` returns `@project`, else the project last viewed (`session[:last_project_id]`, set by `ProjectScoped`, resolved within `Current.account.projects`), else the project with the most recent `issues.last_seen_at`.
  - `live_stream_from(*streamables)`.
- `IconHelper`: `icon(name, classes: "w-[17px] h-[17px]")` covers projects, issues, alerts, uptime, settings, book, search, filter, chevron_updown, check, plus.
- `ChartHelper` (pure SVG built with `tag`, numbers formatted to 1 dp, each bar has a `<title>`):
  - `sparkline_svg(values, color:, width: 120, height: 28, fluid: false)`: area at 0.18 opacity, 2px line and an end dot. The geometry matches `theme.js`.
  - `stacked_sparkline_svg(layers, width: 120, height: 28)`: `layers` is `[{ values:, color: }]`, bottom first. Each layer is an area (0.22 opacity) between its running total and the layer below (the chart floor for the first), all scaled to the largest total. The 1.5px lines along each layer's top are drawn after the areas, top layer first, so where an upper layer is zero (its top equals the one below) the lower layer's colour shows on the shared edge. One end dot on the total, in the colour of the topmost layer with a value on the last day (the bottom layer's when all are zero). Same point geometry as `sparkline_svg`.
  - `histogram_svg(values, color:, width: 150, height: 30, highlight_last: false, fluid: false, titles: nil)`: bars at opacity 0.8, with the last bar at 1.0 when highlighted, minimum height 1.5.
  - `stacked_bar_svg(segments, height: 8)`: `segments` is `[{ share:, color:, opacity: }]` with 1px gaps and rounded ends.
  - `meter_svg(fraction, height: 6)`.
  - Colour constants: `CORAL "#ef6f7c"`, `IRIS "#8f94ee"`, `IRIS_SOFT "#b7baf3"`, `IRIS_DEEP "#6f75e0"`, `LILAC "#b39cf2"`, `MINT "#5cc29a"`, `PAPER "#b5b1a7"`.
- `ChipHelper`: `chip(text, tone: :neutral, dot: false, mono: false)`, where `dot` adds a `coral-dot`.
- **Environment colours.** `EnvironmentTone` (model, `app/models/environment_tone.rb`) maps an environment name, case-insensitively, to a tone: `production|prod|live` → `:coral`, `staging|stage|preview|qa|uat` → `:lilac`, `development|dev|test|local` → `:muted`, anything else → `:iris`. `EnvironmentTone.production?(name)` means "coral". It is plain Ruby with no view code, so models and ingest can use it too. `EnvironmentsHelper` draws names in their tone and is the only place views pick environment colours:
  - `environment_chip(name, small: false)` (the chip tones above), `environment_dot(name)` (a 2×2 swatch, `aria-hidden`), `environment_text(name)` (the name in the tone's text colour, for running text), `environment_text_classes(name)` (that text colour class alone), `environment_bar_classes(name)` (border/background/text for a full-width strip) and `environment_color(name)` (hex for SVG charts: CORAL, LILAC, PAPER, IRIS).
  - Used everywhere an environment is shown: issue hero chips, issue rows, project cards, the occurrence navigator line, the Filters menu entries and `env:` query chips, the environment switch and scope bar on the issues page, the issues eyebrow, the project switcher subtitle and the API key rows on the setup page (a swatch before the label).
- `TimeHelper`:
  - `time_ago_compact(time)` gives "just now", "2 min ago", "3h ago", "12d ago", "9mo ago" or "1y ago".
  - `first_seen_label(time)` gives "first 3h ago".
  - `clock_label(time)` gives "Today 09:14" or "Oct 3 09:14" in the user's zone.
- `NumberHelper`: `delimited(n)` and `compact_count(n)` ("412k", "1.2M").
- `AvatarHelper`:
  - `initials_avatar(name, size: :sm|:md|:lg)` renders a ring avatar, as in the mockup.
  - `empty_avatar` is a dashed circle.
  - `project_tile(project, size: :md|:lg)` draws a tile tinted by `project.color`. Listening projects get a dashed iris outline.

Auth view styling (B owns the views): sessions/new, passwords/new, passwords/edit, registrations/new (fields `account_name, name, email_address, password, time_zone`(hidden)), and the passwords_mailer views. All use `.panel`, `.input` and `.btn-primary`.

### 7.5 Screen specs (feature slices follow the mockups; deviations listed here)

- **Projects overview (D)**:
  - Header: eyebrow with the account name, then "Projects — N" and an "Add a new app" `btn-primary`.
  - A 3-column grid of `_card` partials, followed by the dashed "Add a new app" tile ("One gem, one key, two minutes.").
  - Each card shows the tile, name, `runtime_label || platform label`, a status chip, the unresolved count, "unresolved · N new" (coral when > 0), the per-environment split, a 14-day sparkline, environment chips (`project.environments`) and "last error X ago".
  - **Per-environment split:** under the caption, "● 9 production  ● 3 staging" (no separator, so nothing dangles when the line wraps) (`ProjectsHelper#project_environment_breakdown`), each entry with its `environment_dot` and in its tone's text colour, from `Card#unresolved_by_environment` (environments with unresolved issues only). An issue seen in several environments counts in each, so the parts can add up to more than the total. Hidden when nothing is unresolved.
  - **Sparkline:** `stacked_sparkline_svg` of `Card#series_by_environment` (events per UTC day per environment), each layer in `environment_color`. Order, for the split and the stack alike (`Card#in_display_order`): production-tone environments first (so production is the bottom layer), then the project's key order, then other names alphabetically. A project with no events in the 14 days falls back to the flat `sparkline_svg` in the health colour.
  - **Status (`ProjectHealth`, D):**
    - "Listening…" when `listening?` (the card links to setup and shows the ping dot)
    - "✦ All clear" (mint) when 0 unresolved, with the subtitle "N days clean"
    - "Spiking" (coral and dot) when last-hour events are ≥ 10 and ≥ 3× the average hourly count of the previous 23 hours. Last-hour events are the trailing 60 minutes: the current clock hour plus the unelapsed share of the previous one. The summary strip's events use the same trailing-window estimate for every period, so "1h" early in an hour is not just a few minutes.
    - otherwise "Steady" (iris)
  - The fallback sparkline's colour is coral when spiking, mint when all clear, and IRIS otherwise.
  - `ProjectOverview` (D) runs six grouped queries for all cards, however many there are: unresolved and new counts together (`COUNT(*)` plus `COUNT(*) FILTER (WHERE first_seen_at >= now − 24h)` grouped by project), unresolved counts per environment (`CROSS JOIN LATERAL unnest(issues.environments)` grouped by project and environment), last seen, environments (key names only), daily series per environment and hourly totals. `Card#daily_series` is the per-environment series summed. The card fragment cache key (`Card#cache_key`) includes the split and the per-environment series, so it changes whenever either does.
  - **Recent feed (`RecentFeed`, D):** issues seen in the last hour across the account (8 newest, `includes(:project)`), merged with `resolved` activities from the last hour (4 newest). The dot is coral-pulsing for new, lilac for regressed, solid coral otherwise, and mint for resolved.
- **Issue list (E)**:
  - Heading: eyebrow "project · env-chip-or-all environments", then "Issues — N unresolved" and the period `segmented` control (1h/24h/7d/30d, which drives **only** the summary strip).
  - **Environment scope (`EnvironmentChoice`, `RemembersEnvironment`).** The list shows one environment or all of them, resolved per request in this order: an explicit choice in the request (the `env:` chip in `q`/`chips`, else the `env` param, where blank means all) > the viewer's remembered choice for this project (signed cookie, §4.2) > `project.default_environment` > all. Remembered and default values count only while they are among `project.environments`. The resolved environment becomes the query's `env:` chip (`IssueQuery#with_environment`), which is the single source of truth for the rows, tab counts, heading count and the summary frame's `env` param. Explicit choices of a known environment or of all are remembered; an unknown `env:` chip filters but is not remembered.
    - Every list link (`issues_query_path`: tabs, sort, Filters, chip ×, switch, load more) states its environment, as an `env:` chip or as `env=` (blank) for all, and the filter bar form carries a blank `env` hidden field when no `env:` chip is set, so following a link never falls back to the remembered choice. Entry links without either (sidebar, cards, breadcrumbs, switcher, search results, "all their errors") land in the remembered/default scope.
    - **Environment switch:** a `segmented` nav (`aria-label="Environment"`) at the right of the tabs row (the row is `flex-wrap-reverse`, so when the switch doesn't fit it moves above the tabs and the active tab's underline stays on the divider), reading "All · <env> · <env>" from `project.environments`, each with its `environment_dot`; the current segment has `aria-current="true"`. Links keep the other chips, text and sort.
    - **Scope bar:** while the scope is one non-production environment (`EnvironmentChoice#outside_production?`), a thin full-width strip directly under the topbar in that environment's tone (`environment_bar_classes`) reads "Viewing <env> · Back to production" (the project's first production-tone environment), or "· Show all environments" when it has none. It is a scope indicator (`role="status"`), not a callout.
    - The empty state of a scoped default view reads "No unresolved <env> issues in <project>."
  - **Summary strip (`IssueSummary`):**
    - Events in the period with a sparkline and the delta against the previous period (coral ▲ / mint ▼)
    - New issues, with "N in the last hour"
    - Regressions (unresolved with `regressed_at`), with "Resurfaced after being resolved"
    - Users affected (distinct `issue_users.user_digest` with `last_seen_at` in the period), with "in the selected period" (no delta)
  - **Filter bar:**
    - Chips are parsed from `q` and rendered as pills with × remove links.
    - A text input `text` and a hidden `chips`. `IssueQuery.from_params` composes `q = chips + text`.
    - The "Filters" dropdown lists `env:<each project environment>` (with its swatch) and `level:<each>` links. `env:` pills take their environment's chip tone.
    - The "Sort:" dropdown offers last seen, first seen, events and users.
  - **Query language (`IssueQuery`):**
    - `is:unresolved|resolved|ignored|for_review|new|regressed`
    - `env:<name>`, `level:<level>`, `assigned:me|none`
    - `user:<value>` (a 64-hex digest is used directly; otherwise HMAC it under all three user namespaces)
    - `class:<ExceptionClass>`
    - everything else is free text (`matching`)
    - The default `q` is `is:unresolved`.
  - **Tabs** (links that rewrite only the `is:`/`assigned:` chips): Unresolved (count), For review (coral count), Assigned to me (count), Ignored, Resolved.
  - **Table:**
    - 25 rows per page via OFFSET, plus a `issues_page_<n+1>` "load more" frame.
    - Columns `[28px_1fr_150px_90px_90px_110px_44px]`. A row is a `div` grid, **not** an `<a>`: the title link uses `after:absolute after:inset-0`, and the checkbox (`form="bulk_triage"`, `name="issue_ids[]"`) is `relative z-10`.
    - The left stripe and class colour are coral with a "New" chip (dot) when `new?`, lilac with "↺ Regressed" when `regressed?`, and neutral otherwise.
    - **Reached production:** a small coral "▲ Reached production" chip after that badge when `issue.reached_production?` (`IssuesHelper#issue_reached_production_chip`; a column, so no extra query), titled "First seen in production X ago".
    - The 24h histogram (`IssueHourlyCount.histograms`, one query per page) is coral, LILAC or IRIS_SOFT, with the last bar highlighted for new and regressed issues.
    - Events, users, "seen" (`time_ago_compact` plus "first …"), and the assignee avatar or `empty_avatar`. Rows not seen for over an hour get `opacity-80`.
    - **Environments:** small `environment_chip`s from `issue.environments` (a column, so no extra query) open the transaction/culprit line: the first three, then a muted "+N" (`IssuesHelper#issue_environment_chips`). Issues seen only outside production (`Issue#only_outside_production?`: environments present, none production-tone) draw their title in `text-ink-300` instead of `text-ink-50` (`issue_title_classes`) so production issues stand out. Colour, not opacity: the text stays readable (about 5.6:1) and the hover quick actions in the title block stay at full strength. This depends on the issue alone, never on the list's scope, so live row reloads render the same.
    - **Row grid:** `IssuesHelper::ROW_GRID` shows the Last 24h histogram column from `xl` up only (`HISTOGRAM_CELL`), so the issue column keeps a usable width at ~1024px; the transaction/culprit line clips (`overflow-hidden`) rather than spilling into the next column.
  - **Bulk bar** (shown by `bulk_selection` when count > 0): "N selected", ✓ Resolve (`btn-mint`), Ignore, Assign ▾ (members). There is no Merge.
- **Issue detail (F)**:
  - **Hero:**
    - status chip ("New · unresolved" coral, "Regressed" lilac, "Resolved" mint, "Ignored" muted, "Unresolved" neutral), the coral "▲ Reached production" chip when `reached_production?` (full size, same helper as the row), environment chips, then the class in mono (coral when new, otherwise ink)
    - `issue.message` in `font-display`
    - `transaction_name · culprit` in mono
  - **Hero actions:**
    - The ✓ Resolve split button. ▾ opens a menu with Reopen (when not unresolved) and Assign to… (members).
    - Ignore.
    - ⋯ menu: Copy link, Copy short ID (`clipboard`).
    - "Assigned to <avatar name>" or "Unassigned".
  - **Stat ribbon frame:** Events, Users, First seen (`clock_label` · ago), Last seen, Fingerprint (`fingerprint_label`).
  - **Occurrences chart frame:** fluid `histogram_svg` 860×120, with dashed grid lines and 5 axis labels from `IssueChart` (F).
  - **Backtrace:** `Backtrace` (F PORO).
    - It splits `occurrence.frames` into segments: individual app frames, and runs of consecutive non-app frames folded into "N framework frames hidden (gem names…)".
    - The first app frame is expanded with code context (the error line highlighted coral) and locals.
    - Other app frames are rows that expand with a native `<details>`.
    - "Show framework frames" uses `toggle`. "Raw" uses `<details>` with the plaintext trace, the first line being `"#{class}: #{occurrence.exception_message}"`. "Copy" copies the raw text.
  - **Breadcrumbs timeline:** `offset_ms` label, dot colour per category (sql lilac, http mint, log iris, others paper-500), ending with the coral "error" node. Filter chips use `breadcrumb_filter`.
  - **Context tabs** (`tabs`): Request (URL, Method, Controller, Format, Request ID, Remote IP; empty without a request section), Params (pretty JSON), Headers, Session, Job (Framework, Job class, Mailer, Mailer action, Job ID, Provider job ID, Queue, Priority, Executions, Retry count, Enqueued at, Scheduled at, then Arguments as pretty JSON; "No job was captured with this occurrence." when absent), Environment (flattened `context` with dotted keys). An occurrence with a job and no request opens on Job (`IssueContextHelper#initial_context_tab`). `"[FILTERED]"` renders muted.
  - **Right rail:**
    - **Navigator** (`OccurrenceNavigator`, F): ‹ / › links to the previous and next occurrence by id; "N of M" (M = stored occurrences count, plus a "stored" suffix when M < events_count); Latest / Oldest / Random.
    - **Affected user:** from `occurrence.user`. Shows the name, `id … · local@…` (the email domain is masked), "Hit this N×" (`IssueUser.count_for`), and "all their errors" → issues index with `q=user:<digest>`.
    - **Tags:** `IssueTagCount.distribution` with `stacked_bar_svg`. The top value turns coral and is labelled "← suspicious" when its share is ≥ 0.8 and there are ≥ 2 distinct values. Otherwise it shows the top 2 shares. The `environment` key (set from the API key, never captured) colours each segment with `environment_color` unless it is suspicious.
    - **Activity:** `issue.activities.recent.includes(:user, :subject_user).limit(20)` (system entries: lilac "↺ Regressed: seen again after being resolved" and coral "▲ Reached production: first seen there after other environments"), plus a final "First seen" line, plus the note form ("Leave a note for the coven…").
- **Setup & settings (D)**:
  - The settings sub-nav lists only "Setup & API keys" and "General".
  - The hero runs the stepper from `SetupProgress` (D). Step 1 is always done. Step 2 is current while listening. Step 3 is done once `first_event_at` is set, and the hero then becomes "✦ <name> is connected", with a link to issues.
  - The install steps and right rail depend on `project.platform`: `show` renders `projects/setups/<platform>/_steps` and `projects/setups/<platform>/_rail`. Shared pieces: `_snippet` (copyable code pane), `_install_env` (the "ENV only" tab), `_test_error` (a layout around the platform's test command, with the listening frame) and `_self_hosting`. Step numbers come from `SetupHelper#setup_step_heading` and stay sequential per platform.
  - **Ruby on Rails** (`rails/`): i. "Add the gem" tabs Generator / Manual / ENV only; ii. "Cast a test error" with `bin/rails goodsorcery:test`. The rail mentions `filter_parameters`, ActiveSupport breadcrumbs and `current_user`.
  - **Ruby** (`ruby/`): i. "Add the gem" tabs Manual (`bundle add goodsorcery`, `export GOODSORCERY_API_KEY`, a `config/goodsorcery.rb` boot file reading ENV, leaving `config.environment` to the gem's lookup and showing it only as a comment) / ENV only (with a note to `require "goodsorcery"` at boot, since nothing else loads it outside Rails); ii. "Hook it in" tabs Rack / Sinatra (`GoodSorcery::Rack::Middleware`), Sidekiq (automatic when Sidekiq is required first, else `GoodSorcery::Integrations::Sidekiq.install`), Rake (`require "goodsorcery/tasks"`) and Anywhere (`GoodSorcery.notify`); iii. "Cast a test error" with `bundle exec rake goodsorcery:test`. The rail makes no Rails-only claims.
  - Snippets show the **masked** default key with the note "Reveal your key under API keys below". Copy copies the snippet text, with a `YOUR_<ENV>_KEY` placeholder instead of the masked key.
  - API keys panel:
    - Each row shows the masked key with Reveal → a frame with the full key, Copy and Hide.
    - "Created X ago by Name · last used X ago" or "· never used", and Rotate….
    - "+ New key" opens an inline form (environment name).
  - Right rail: "What gets captured", "Scrubbed by default" (per platform) and the Self-hosting card.
  - `projects/new` shows the "Add a new app" form panel (name, platform select: "Ruby on Rails" or "Ruby"; Settings › General can switch it).

---

## 8. Work split: file ownership slices

**Phases:**
1. A (data) and B (shell) run in parallel. B runs its tests after A has landed the schema.
2. C, D, E, F and G run in parallel.
3. Integration review.

Never edit a file you don't own. If you need a change in another slice's file, report it instead of making it.

### A: foundation-data
- `Gemfile`, `Gemfile.lock` (uncomment `bcrypt`)
- `config/application.rb`, `config/environments/development.rb`, `config/environments/test.rb`, `config/environments/production.rb` (encryption keys §1.4; production `assume_ssl`/`force_ssl = true` with `/up` excluded)
- `config/initializers/filter_parameter_logging.rb`
- `config/routes.rb` (exactly §4.1)
- `lib/middleware/ingest_body_shield.rb`
- `db/migrate/*`, `db/schema.rb`, `db/seeds.rb`. Seeds build "Acme Labs", `philip@example.com`/`password`, the five mockup projects with issues, occurrences, rollups, tags, users and activities created directly through models.
- `app/models/application_record.rb`, `current.rb`, `account.rb`, `user.rb`, `membership.rb`, `session.rb`, `signup.rb`, `project.rb`, `project/broadcasting.rb` (stub → G), `api_key.rb`, `inbound_event.rb`, `issue.rb`, `issue/searchable.rb`, `issue/triage.rb`, `issue/broadcasting.rb` (stub → G), `occurrence.rb`, `issue_hourly_count.rb`, `project_hourly_count.rb`, `issue_tag_count.rb`, `issue_user.rb`, `issue_activity.rb`, `time_series.rb`, `private_digest.rb`
- `app/controllers/application_controller.rb`, `app/controllers/concerns/authentication.rb`, `app/controllers/concerns/project_scoped.rb`, `app/controllers/concerns/issue_scoped.rb`, `app/controllers/sessions_controller.rb`, `passwords_controller.rb`, `registrations_controller.rb`
- `app/mailers/passwords_mailer.rb`
- `app/channels/application_cable/connection.rb`, `app/channels/application_cable/channel.rb`
- `test/test_helper.rb` (also defines `FIXTURE_TOKENS`), `test/test_helpers/session_test_helper.rb`, `test/fixtures/*.yml`, `test/models/**` (except `test/models/ingest/**` and G's files listed below), `test/controllers/sessions_controller_test.rb`, `passwords_controller_test.rb`, `registrations_controller_test.rb`, `test/mailers/**`
- Run `bin/rails generate authentication` (accept the generator's views; B restyles them), then adapt.

**Fixtures contract** (other slices rely on these names). Passwords are all `"password"`.
- accounts: `acme`, `umbrella`
- users: `philip` (acme owner), `jo` (acme member), `outsider` (umbrella owner)
- projects:
  - `storefront` (acme, prefix GS, has events)
  - `billing` (acme, prefix BA, steady)
  - `marketing` (acme, prefix MS, `first_event_at: nil`)
  - `umbrella_app` (umbrella)
- api_keys: `storefront_production`, `storefront_staging`, `marketing_production`, `umbrella_production`. Raw tokens are exposed as `FIXTURE_TOKENS[:storefront_production]` etc. in `test_helper.rb`, and `token_digest` is computed with ERB.
- issues (storefront unless noted):
  - `nomethod` (new, unresolved, assigned philip)
  - `regressed` (regressed_at set)
  - `card_error` (steady, old)
  - `resolved_issue`
  - `ignored_issue`
  - `billing_timeout` (billing)
  - `umbrella_issue` (umbrella_app)
- occurrences: `nomethod_latest`, `nomethod_oldest` (full realistic payload per §3.3, including `[FILTERED]` values), `regressed_latest`, `umbrella_occurrence`
- `issue_hourly_counts` and `project_hourly_counts` for the last 24h/14d (ERB-relative times); `issue_tag_counts` for nomethod (browser, coupon); `issue_users` for nomethod; `issue_activities` (resolved, note)

### B: foundation-shell
- `app/assets/tailwind/application.css`, `app/assets/stylesheets/application.css`
- `app/views/layouts/application.html.erb`, `auth.html.erb`, `_sidebar.html.erb`, `_topbar.html.erb`, `_project_switcher.html.erb`, `_usage_meter.html.erb`, `_user_menu.html.erb`, `_flash.html.erb`, `mailer.html.erb`, `mailer.text.erb`
- `app/views/shared/_sigil.html.erb`, `app/views/shared/_empty_state.html.erb`
- `app/views/sessions/new.html.erb`, `app/views/passwords/new.html.erb`, `app/views/passwords/edit.html.erb`, `app/views/registrations/new.html.erb`, `app/views/passwords_mailer/reset.html.erb`, `reset.text.erb`
- `app/helpers/application_helper.rb`, `navigation_helper.rb`, `icon_helper.rb`, `chart_helper.rb`, `chip_helper.rb`, `time_helper.rb`, `number_helper.rb`, `avatar_helper.rb`
- `app/javascript/application.js`, `app/javascript/stream_actions.js`, `app/javascript/controllers/{dropdown,tabs,clipboard,toggle,timezone,flash}_controller.js` (delete `hello_controller.js`), `config/importmap.rb` (pin `stream_actions`)
- `config/initializers/content_security_policy.rb`, `public/icon.svg` (sigil)
- `test/helpers/**`, `test/integration/shell_test.rb` (layout renders, signed-in nav, CSP header present)

### C: ingest
- `app/controllers/api/v1/events_controller.rb`, `app/controllers/concerns/api_key_authentication.rb`
- `app/models/ingest/*.rb` (§2.3)
- `app/jobs/process_inbound_event_job.rb`, `app/jobs/trim_occurrences_job.rb`
- `lib/tasks/goodsorcery.rake`, `config/sidekiq.yml`
- `docs/INGEST_API.md`
- `test/controllers/api/v1/events_controller_test.rb`, `test/models/ingest/**`, `test/jobs/process_inbound_event_job_test.rb`, `test/jobs/trim_occurrences_job_test.rb`, `test/integration/ingest_flow_test.rb`, `test/fixtures/files/events/*.json`
- Required tests:
  - scrubbing (keys, cards, bearer, JWT, URL query)
  - redaction
  - fingerprint stability
  - regression
  - duplicate event_id
  - race-safe creation (two processors with the same fingerprint)
  - raw columns are ciphertext
  - log/params shield (`Parameters: {}`)
  - 401/413/415/422/429 (use `ActionController::Base.cache_store = :memory_store` in that test)

### D: projects, setup and API keys
- `app/controllers/projects_controller.rb`, `app/controllers/projects/{setups,cards,listenings,api_keys}_controller.rb`, `app/controllers/projects/api_keys/{reveals,rotations}_controller.rb`, `app/controllers/recent_issues_controller.rb`
- `app/models/project_overview.rb`, `project_health.rb`, `recent_feed.rb`, `setup_progress.rb`
- `app/views/projects/**` (index, new, edit, `_card`, `_new_app_tile`, `_form`, `_settings_nav`, `setups/show` + partials, `cards/show`, `listenings/show` + `_listening`, `api_keys/_api_key`, `api_keys/show`, `api_keys/create.turbo_stream.erb`, `api_keys/reveals/show`, `api_keys/rotations/create.turbo_stream.erb`), `app/views/recent_issues/**`
- `app/helpers/projects_helper.rb`, `app/helpers/setup_helper.rb`
- `test/controllers/projects_controller_test.rb`, `test/controllers/projects/**` (except `summaries` and `bulk_triages`), `test/controllers/recent_issues_controller_test.rb`, `test/models/{project_overview,project_health,recent_feed,setup_progress}_test.rb`

### E: issue list and search
- `app/controllers/issues_controller.rb`, `app/controllers/projects/summaries_controller.rb`, `app/controllers/projects/bulk_triages_controller.rb`, `app/controllers/issues/rows_controller.rb`, `app/controllers/searches_controller.rb`
- `app/models/issue_query.rb`, `issue_query/chip.rb`, `issue_list.rb` (pagination, histogram preload, tab counts), `issue_summary.rb`
- `app/views/issues/index.html.erb`, `_row`, `_rows`, `_filter_bar`, `_tabs`, `_bulk_bar`, `_page`, `app/views/issues/rows/**`, `app/views/projects/summaries/**`, `app/views/searches/**`
- `app/helpers/issues_helper.rb` (row tone, chips, histogram colour), `app/helpers/issue_query_helper.rb`
- `app/javascript/controllers/bulk_selection_controller.js`
- `test/controllers/issues_controller_test.rb` (index only), `test/controllers/projects/{summaries,bulk_triages}_controller_test.rb`, `test/controllers/issues/rows_controller_test.rb`, `test/controllers/searches_controller_test.rb`, `test/models/{issue_query,issue_list,issue_summary}_test.rb`

### F: issue detail
- `app/controllers/issues/{occurrences,charts,stats,resolutions,ignores,assignments,notes}_controller.rb`
- `app/models/backtrace.rb`, `backtrace/segment.rb`, `occurrence_navigator.rb`, `issue_chart.rb`
- `app/views/issues/show.html.erb` and partials `_hero`, `_stats`, `_chart`, `_backtrace`, `_app_frame`, `_framework_run`, `_breadcrumbs`, `_context_tabs`, `_navigator`, `_affected_user`, `_tags`, `_activity`; `app/views/issues/{stats,charts,occurrences,notes}/**`
- `app/helpers/issue_detail_helper.rb`
- `app/javascript/controllers/breadcrumb_filter_controller.js`
- `test/controllers/issues/{occurrences,charts,stats,resolutions,ignores,assignments,notes}_controller_test.rb`, `test/integration/issue_detail_test.rb` (also hits `issues#show`), `test/models/{backtrace,occurrence_navigator,issue_chart}_test.rb`

### G: live updates
- `app/channels/authorized_streams_channel.rb`
- `app/models/issue/broadcasting.rb`, `app/models/project/broadcasting.rb` (replacing A's stubs), `app/models/live_frames.rb`
- `app/jobs/broadcast_issue_changes_job.rb`, `app/jobs/broadcast_project_changes_job.rb`
- `test/channels/authorized_streams_channel_test.rb` (accepts members; rejects outsiders, tampered names and anonymous connections), `test/jobs/broadcast_*_test.rb` (`assert_broadcast_on`, which also asserts the payload has no message text), `test/models/issue/broadcasting_test.rb`
- G checks (it does not edit) that D/E/F views contain the stream sources and frame ids in §4.3/§4.4, and reports any mismatch.

---

## 9. Security checklist (every slice, every change)

- [ ] Every query is scoped via `Current.account` → project → issue, with an outsider 404 test.
- [ ] No captured data in job args, cable payloads, cache, logs or exception messages.
- [ ] No `raw`/`html_safe` on captured data; JSON is pretty-printed through escaping.
- [ ] Encrypted columns stay encrypted (no `insert` of pre-decrypted copies elsewhere).
- [ ] No inline styles or scripts (CSP).
- [ ] Revealed keys are never cached, and `no-store` is applied.
- [ ] Brakeman clean (`bin/brakeman --no-pager`).

## 10. Performance checklist

- [ ] Lists: one query per concern (rows, histograms, counts), `includes(:assignee)`, `inverse_of` for `project`.
- [ ] No per-row queries in partials, including the sidebar badge, which is one count.
- [ ] Ingest: within the §2.6 budget; hot-row updates last; multi-row upserts sorted.
- [ ] Indexes exist for every `where`/`order` used (§1.3).
