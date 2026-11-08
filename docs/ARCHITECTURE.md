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
7. **Out of scope (do not build):** deploy tracking/releases UI, keyboard shortcuts, the "needs attention" callout, Merge, "Mute rules", GitHub links ("Link GitHub issue", "Open in GitHub"), team invites, project deletion, the Ruby client gem, geo-IP ("London, GB"), and syntax highlighting of code context (render plain mono text). Email alerts were out of scope for v1; they were approved later and are built (§11). Uptime was also out of scope for v1 (a "soon" placeholder); uptime monitoring and account entitlements were approved on 2026-11-03 (§12). Performance monitoring (APM) was approved on 2026-11-04 (§13).
8. **Wording.** Every "create project" affordance reads **"Add a new app"**: the projects page header button, the dashed tile and the `projects#new` page title.

---

## 1. Domain model and database schema

### 1.1 Entities

```
Account ─┬─< Membership >── User ──< Session (session.account = current org)
         │      └─< NotificationPreference >── Project (per member per app, §11)
         └─< Project ─┬─< ApiKey (one per environment, ingest-only)
                      ├─< AlertRule (one per kind, §11)
                      ├─< AlertDelivery >── User (throttle/audit log, §11)
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

The uptime build (§12.1) adds `accounts.entitlement_values`, the `uptime_monitors`, `uptime_checks`, `uptime_hourly_counts` and `uptime_incidents` tables, and `notification_preferences.uptime_alerts_muted`. The APM build (§13.2) adds the `apm_transactions`, `apm_minute_stats`, `apm_hourly_stats`, `apm_traces` and `apm_inbound_batches` tables.

All `id`s are `bigint`. FKs are real `add_foreign_key` constraints. "cascade" means `on_delete: :cascade`.

**accounts**
| column | type | null | default |
|---|---|---|---|
| name | string | false | |
| created_at / updated_at | datetime | false | |

The `monthly_event_quota` column of v1 became the `monthly_event_quota` entitlement in `entitlement_values` (§12.2.2; migration `move_monthly_event_quota_to_entitlements`). The column (bigint, null) is still in the table for one release, ignored by `Account` (`ignored_columns`), and a later release drops it.

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
| retention_days | integer | false | 30 | 30, 60 or 90 (`Project::RETENTION_CHOICES`, so `Project::MAX_RETENTION_DAYS` is 90), within the account's `retention_days` entitlement (§12.2.3) |
| first_event_at | datetime | true | | nil means "Listening…" |
| alert_scope | string | false | `"default"` | which environments alert rules watch (§11): `default` follows `default_environment` (nil there = all), `all`, or `selected` |
| alert_selected_environments | string, array | false | `[]` | the environments for `selected`; normalised to lowercase, must be non-empty and among `environments` while `selected`; cleared (`before_validation`) when the scope is anything else. Migration `20261011000002` |
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

**alert_rules** (§11; migration `20261011000001` backfilled the default set for existing apps)
| column | type | null | default | notes |
|---|---|---|---|---|
| project_id | references → projects, cascade | false | | |
| kind | string | false | | enum `new_issue regression reached_production still_happening daily_digest` |
| enabled | boolean | false | true | defaults per kind: all on except `daily_digest` |
| threshold | integer | true | | `still_happening` only (default 100), else nil. Check constraint `threshold IS NULL OR threshold BETWEEN 1 AND 100000` |
| timestamps | | | | |
Indexes: unique `[project_id, kind]`, `[kind, enabled]`.

**notification_preferences** (§11; sparse: no row = alerts on, digest on)
| column | type | null | default |
|---|---|---|---|
| membership_id | references → memberships, cascade | false | |
| project_id | references → projects, cascade | false | |
| alerts_muted | boolean | false | false |
| digest_enabled | boolean | false | true |
| timestamps | | | |
Indexes: unique `[membership_id, project_id]`, `[project_id]`.

**alert_deliveries** (§11; ids, kind and key only, never captured data)
| column | type | null | default | notes |
|---|---|---|---|---|
| user_id | references → users, cascade | false | | recipient |
| project_id | references → projects, cascade | false | | for a summary row, the first app it covers |
| issue_id | references → issues, cascade | true | | nil for digests and summaries |
| kind | string | false | | `AlertRule::KINDS` plus `summary` |
| dedupe_key | string | false | | `AlertDelivery.issue_key` / `.digest_key` / `.summary_key` |
| status | string | false | `"sent"` | `sent` or `folded` (over the hourly cap, awaiting the summary) |
| summarized_at | datetime | true | | set on folded rows once the summary email covered them |
| created_at | datetime | false | | set from the app clock (`Time.current`) by `.record`; no `updated_at`; pruned after 30 days |
Indexes: unique `[user_id, dedupe_key]` (the race-safe throttle), `[user_id, status, created_at]` (hourly cap, folded lookup), `[issue_id, kind, created_at]` ("alerted recently?", FK cascade), `[project_id]`, `[created_at]` (pruning), and the partial `index_alert_deliveries_awaiting_summary` on `[user_id, created_at] WHERE status = 'folded' AND summarized_at IS NULL` (migration `20261011000005`, built concurrently), so the hourly summary run reads only rows awaiting a summary (normally none) instead of scanning the 30-day table.

### 1.4 Active Record Encryption

- Encrypted attributes are all non-deterministic with default compression: `InboundEvent#body`, `Occurrence#payload`, `ApiKey#token`, `IssueTagCount#value`, `IssueActivity#body`; later builds add `UptimeMonitor#url` (§12.1), `ApmTrace#payload` and `ApmInboundBatch#body` (§13.2).
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
- **Account**: `has_many :memberships, :users (through), :projects`. `#accessible_by?(user)` checks `memberships.exists?(user_id: user.id)`. `Account::EventQuota` (§12.2.2): `#events_this_month` returns the cached (5 min) sum of `project_hourly_counts` for this month, `#over_quota?` compares it with `entitlements.monthly_event_quota`, `.over_quota?(id)` is ingest's cached gate and `#event_quota_fraction` returns 0..1 or nil.
- **User**: `has_secure_password`, `normalizes :email_address`, `has_many :sessions, :memberships, :accounts, :alert_deliveries`. `#default_account`, `#initials`, `#first_name`, `scope :email_verified`, `#alert_mute_token(project, stream: "alerts")` (§11).
- **Membership**: `enum :role, { owner: "owner", member: "member" }`. Alert preferences (§11): `has_many :notification_preferences`; scopes `with_verified_email`, `receiving_alerts_for(project)`, `receiving_digest_for(project)`; `#receives_alerts?(project)`, `#receives_digest?(project)`, `#notification_preference_for(project)` (saved row or an unsaved default, built by id), `#update_notification_preference(project, **attributes)`.
- **Session**: `belongs_to :user, :account`.
- **Signup** (ActiveModel PORO): attributes `account_name, name, email_address, password, time_zone`. `#save` creates the account, user and owner membership in one transaction and returns the user, or false with errors.
- **Project**:
  - `belongs_to :account`; `has_many :api_keys, :issues, :occurrences, :inbound_events, :project_hourly_counts`.
  - `to_param` returns `slug`. Callbacks `before_validation` set slug, issue_prefix and color on create. `after_create :create_default_api_keys` creates `production` and `staging` keys with `created_by: Current.user`, then sets `default_environment` to `"production"` when it is still nil and a production key exists.
  - `#accessible_by?(user)` delegates to account. `#listening?` is `first_event_at.nil?`. `#environments` returns the api_keys environments in id order.
  - `#allocate_issue_number` runs `UPDATE projects SET issues_sequence = issues_sequence + 1 WHERE id = $1 RETURNING issues_sequence`. `#record_first_event(runtime_label:, at:)` runs `UPDATE … SET first_event_at = COALESCE(first_event_at, :at), runtime_label = :label`.
  - `#unresolved_count(environment = nil)` and `#cached_unresolved_count(environment = nil)` (10 s, a number only; `#expire_unresolved_counts` on triage).
  - `include Project::Broadcasting` (stub, §4.6) and `Project::Alerting` (§11: `has_many :alert_rules, :alert_deliveries, :notification_preferences`, the `alert_scope` enum, default rules `after_create`, `#alert_rule(kind)`, `#alert_environments`, `#saved_alert_environments` (from the saved columns, for labels on a rejected form), `#alerts_cover?`, `#alert_recipients`, `#digest_recipients`).
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
  - `RETAINED_PER_ISSUE = 100`, `RETAINED_PER_PROJECT = 3_000` (stored copies only; every event is still counted).
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
- **Alert delivery** (§11.4): `IssueAlert` (`.transitions`, `#due?`, `#deliver`), `StillHappeningCheck` (`#hot_issue_ids`, `#alert_hot_issues`), `DailyDigest` (`.deliver_due`, `#deliver`, `#due_recipients`, `#issues`, `#issue_count`, `#more_count`) and `AlertSummary` (`.deliver_due`, `#deliver`). `IssueHourlyCount.trailing_hour(issue)` and `TRAILING_HOUR_SUM` give the trailing-60-minute estimate.

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
| `TrimOccurrencesJob` | keep newest 100 per issue | `perform(issue)` |
| `CapStoredOccurrencesJob` | every 5 minutes (sidekiq-cron): hold each project to 3,000 stored occurrences | `perform` → `Ingest::OccurrenceCap.enforce_all` |
| `IssueAlertJob` | queue `alerts`, enqueued after commit for an alert transition (§11.4) | `perform(issue_id, kind, occurrence_id = nil)` → `IssueAlert#deliver` |

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
                               TrimOccurrencesJob.perform_later(issue) if (issue.events_count % TRIM_EVERY).zero?  # TRIM_EVERY = 50
                               IssueAlert.transitions(issue, created:).each { IssueAlertJob.perform_later(issue.id, kind, occurrence_id) }  # §11.4
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
- **Job, existing issue:** inbound + project + select issue + occurrence + 4 upserts + issue UPDATE + delete, about 10 statements. A new issue adds 3 more. A regression, and the one event that takes an issue to production, each add one activity INSERT. Alert flagging (§11.4) adds no statement: it reads `tally.created?`, `previous_status` and `just_reached_production`, which the counter UPDATE already returned, and only a transition enqueues a job (`test/models/ingest/alert_flags_test.rb` asserts the 12 statements of an ordinary event).

### 2.7 Maintenance (slice C, `lib/tasks/goodsorcery.rake`)

- `goodsorcery:prune` deletes occurrences older than `project.retention_days` (`in_batches(of: 1_000).delete_all`), `issue_users` rows and `issue_tag_counts` of issues not seen within it, `issue_hourly_counts` older than 31 days and `project_hourly_counts` older than 90 days (one `hour` slice per DELETE, using the `hour` indexes; project counts are kept longer for the 30d summary comparison and the monthly quota), inbound events still unprocessed after a day (deleted unread, logged by id) and `alert_deliveries` older than `AlertDelivery::KEPT_FOR` (30 days). Schedule it daily with cron or a Kamal accessory, as documented in `docs/INGEST_API.md` › Operating.
- `goodsorcery:requeue_stale` re-enqueues `InboundEvent.stale`.
- `TrimOccurrencesJob` keeps the newest `Occurrence::RETAINED_PER_ISSUE` per issue. The cutoff id is `issue.occurrences.latest_first.offset(100).pick(:id)`.
- `CapStoredOccurrencesJob` (`Ingest::OccurrenceCap`) holds each project to `Occurrence::RETAINED_PER_PROJECT` (3,000) stored occurrences. One grouped `COUNT` finds the projects over the cap. For each, it computes the level: the most copies every issue can keep, at least 1, with the total within the cap. A `ROW_NUMBER() OVER (PARTITION BY issue_id ORDER BY id DESC)` query picks the ids past each issue's newest level, deleted 1,000 at a time. The issues with the most copies lose their oldest first, and every issue keeps its newest. A project with more issues than the cap stays a little over it. Counters and rollups are unaffected.
- `config/sidekiq.yml` queues: `[ingest, 3]`, `[default, 2]`, `[alerts, 2]` (alert jobs and sweeps, §11.4), `[mailers, 1]`.

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

  resource :email_verification, only: %i[show create]
  resource :alert_mute, only: %i[show create]       # §11, token in ?token=, no sign-in
  resource :notifications, only: :show              # §11

  resource :search, only: :show
  resource :recent_issues, only: :show

  resources :projects, only: %i[index new create edit update] do
    scope module: :projects do
      resource :setup, only: :show
      resource :card, only: :show
      resource :listening, only: :show
      resource :summary, only: :show
      resource :bulk_triage, only: :create
      resource :alerts, only: %i[show update]                  # Settings › Alerts (§11)
      resources :alert_rules, only: :update, param: :kind      # /alert_rules/still_happening
      resource :slack_connection, only: %i[update destroy] do  # Slack alerts (§11.5)
        scope module: :slack_connections do
          resource :test_message, only: :create
        end
      end
      resource :notification_preference, only: :update        # the member's own switches
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
  - `include Authentication`, `allow_browser versions: :modern, unless: :any_browser_allowed?`, `stale_when_importmap_changes`. Pages opened from an email link override the private `any_browser_allowed?` to return true (`AlertMutesController`, `EmailVerificationsController#show`), because mail apps open links in whatever (often old, in-app) browser they have; the dashboard keeps the gate.
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
- `SessionsController`, `PasswordsController` (generator, `layout "auth"`), `RegistrationsController` (`new`/`create` via `Signup`; `rate_limit to: 10, within: 3.minutes, only: :create`; `allow_unauthenticated_access`). Sign-up (`Signup.open?`) is open only until the first account exists, unless `GOODSORCERY_ENABLE_SIGNUPS=1`; `GOODSORCERY_DISABLE_SIGNUPS=1` closes it completely. Closed sign-up redirects to sign-in. Under the submit button, `RegistrationsHelper#signup_agreement` renders "By signing up you agree to the Terms of Service and Privacy Policy.", naming only the pages whose URL is set (`GOODSORCERY_TERMS_URL`, `GOODSORCERY_PRIVACY_URL`, read once at boot into `config.x.terms_url` / `config.x.privacy_url` through `HttpUrl.parse`, http(s) only; links open with `target="_top"`), and nothing at all when neither is set.

| Controller | Slice | Actions | Notes |
|---|---|---|---|
| `Api::V1::EventsController` | C | create | §2.1 |
| `Api::V1::Events::BatchesController` | C | create | §2.1.1 |
| `Api::V1::VerificationsController` | C | show | §2.1.2 |
| `ProjectsController` | D | index, new, create, edit, update | index = overview; create → `redirect_to project_setup_path`; edit/update = Settings › General (name, platform, issue_prefix, scrub_fields as comma list, retention_days: a select of 30 / 60 / 90 days (§12.2.3), default_environment: a select of "All environments" (blank) plus `project.environments`) |
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
| `Projects::AlertsController` | Alerts A | show, update | Settings › Alerts (§11.3). `update` saves `alert_scope` and `alert_selected_environments` only; 422 re-renders with the error |
| `Projects::AlertRulesController` | Alerts A | update | one rule by kind (`@project.alert_rules`, unknown kind 404): `enabled` and/or `threshold`; redirects to Settings › Alerts, 422 re-renders it with the threshold error |
| `Projects::SlackConnectionsController` | Slack | update, destroy | §11.5: `update` connects or replaces the webhook URL and/or sets `enabled` (`slack_connection[webhook_url, enabled]`); 422 re-renders Settings › Alerts without echoing the URL; `destroy` disconnects. Any member |
| `Projects::SlackConnections::TestMessagesController` | Slack | create | rate limited per user (5/min) and per connection (`claim_test_message`, 30 s); enqueues `SlackTestMessageJob(connection_id)`; no connection is a 404 |
| `NotificationsController` | Alerts A | show | the signed-in member's switches per app of `Current.account` (§11.3), fixed query count |
| `Projects::NotificationPreferencesController` | Alerts A | update | `alerts_muted` / `digest_enabled` for `Current.user`'s membership; doesn't touch `session[:last_project_id]` |
| `AlertMutesController` | Alerts A | show, create | unauthenticated, `layout "auth"`, rate-limited 30/min per IP. Any browser (`any_browser_allowed?`, §4.2). Token → `AlertMute`, else 404 "This link no longer works". `show` confirms (never mutes, so link scanners are harmless); `create` mutes and renders 200 (RFC 8058). `skip_forgery_protection only: :create`: mail providers POST without a CSRF token, and no cookie is involved; the token is the credential |

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
| Over the monthly event quota (hosted only, a boolean; §12.2.2) | `["account_over_quota", account.id]` | 1 min; rewritten after a commit that changes `entitlement_values` (a miss writes only into an empty key) | A |
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
  - The account's own data is not role-gated in v1 (`member` and `owner` have equal rights). That includes Settings › General and Settings › Alerts.
  - Notification switches belong to the signed-in member: they are looked up through `Current.account.memberships.find_by!(user: Current.user)`, never by a membership id from params.
  - The one-click mute endpoint (`/alert_mute?token=`) is the only dashboard-side endpoint without sign-in: an `AlertMute` token (signed by `Rails.application.message_verifier(:alert_mute)`, purpose `:alert_mute`, 60 days) names the user, app and stream, and is honoured only while the user is a member of the app's account.
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
  - nav section "Grimoire": Projects; Issues with an unresolved badge for `sidebar_project` (`sidebar_issues_badge`), counted for the environment its issue list shows (`issues_environment_for`, §4.2), tinted in that environment's tone (`environment_bar_classes`; coral for all environments) with a title such as "23 unresolved in staging"; Alerts → Settings › Alerts of `sidebar_project` (`key: "alerts"`; a plain non-link row when there is no project)
  - Uptime → the app's Uptime page (§12.8). This replaces the old "Coming from the suite: Uptime (soon)" placeholder.
  - "Project": "Settings & setup" → `project_setup_path(sidebar_project)`; Docs → `docs_url` (external)
  - `layouts/_usage_meter` (events this month / `entitlements.monthly_event_quota`, hidden when that is nil, so always self-hosted)
  - `layouts/_user_menu` (initials, name, "Account name · Hosted" or "Self-hosted" by `ENV["GOODSORCERY_HOSTED"]`, dropdown with Notifications (`notifications_path`) and Sign out)
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
  - The settings sub-nav lists "Setup & API keys", "General" and "Alerts" (§11.3).
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

---

## 11. Email alerts (approved 2026-10-11)

Built in two slices. **Slice A** (data model and UI, §11.1–§11.3) and **slice B** (ingest triggers, jobs, `AlertsMailer`, sidekiq-cron, §11.4) are both done. Slack alerts (§11.5) were added on 2026-11-08.

### 11.1 Rules, scope and recipients

| rule (`AlertRule#kind`) | default | fires |
|---|---|---|
| `new_issue` | on | first occurrence of a brand-new issue |
| `regression` | on | a resolved issue happens again (`regressed_at`, §2.5) |
| `reached_production` | on | `reached_production_at` is stamped (§2.5) |
| `still_happening` | on, `threshold` 100 | an issue's events in the last hour reach the app's threshold (1..100,000); at most once per issue per 6 hours |
| `daily_digest` | off | 09:00 in each recipient's `users.time_zone`: open issues of the app with events in the last 24h |

- **Rules** are rows (`alert_rules`, one per app and kind), created by `Project::Alerting` `after_create` (`insert_all` of `AlertRule.default_rows_for`) and backfilled for older apps by migration `20261011000001`. `Project#alert_rule(kind)` returns the row (one query loads all five) or an unsaved default if a row is missing.
- **Environment scope** is per app (`projects.alert_scope`): `default` follows `default_environment` (nil there means all environments), `all`, or `selected` (`alert_selected_environments`, at least one of the app's environments). `Project#alert_environments` is the effective list, or nil for all; `#alerts_cover?(environments)` tests an event's environment or an issue's `environments`.
- **Recipients** are the members of the app's account (memberships) with a confirmed address (`User#email_verified?`; unverified addresses are never mailed), minus those who switched the stream off for that app:
  - `NotificationPreference#alerts_muted` stops the instant rules (`AlertRule::INSTANT_KINDS`: everything but the digest);
  - `NotificationPreference#digest_enabled = false` stops the digest.
  - The two switches are independent: muting an app's alerts keeps its digest. Rows are sparse; no row means both on.

### 11.2 Model API for delivery (slice B)

- `AlertRule.enabled.still_happening.includes(:project)` / `.daily_digest` — apps to check on a schedule. `project.alert_rule(kind).enabled?`, `project.alert_rule_enabled?(kind)`, `project.still_happening_threshold`, `rule.instant?`.
- `project.alert_environments`, `project.alerts_cover?(environments)`.
- `project.alert_recipients` / `project.digest_recipients` → `User` relations (one subquery each: verified members not opted out). `membership.receives_alerts?(project)` / `#receives_digest?(project)` re-check one person at send time.
- `AlertDelivery` (throttle and audit log; ids, kind and key only):
  - `AlertDelivery.record(user:, project:, kind:, dedupe_key:, issue: nil, status: "sent")` → new id, or nil when the user already has that key (INSERT … ON CONFLICT DO NOTHING on unique `[user_id, dedupe_key]`, so concurrent jobs can't double-send). It skips validations.
  - Keys: `AlertDelivery.issue_key(kind, issue, at:)` — `new_issue:<id>` and `reached_production:<id>` (once per issue), `regression:<id>:<regressed_at epoch>` (once per regression), `still_happening:<id>:<6h window index>`; `AlertDelivery.digest_key(project, local_date)` (once per user, app and local day); `AlertDelivery.summary_key(at)` (one overflow summary per user per clock hour).
  - Cap: `AlertDelivery::HOURLY_CAP` (20) sent instant-alert emails per user per hour (digests and summaries are exempt), `AlertDelivery.sent_in_last_hour(user)` / `.cap_reached?(user)`. `AlertDelivery.claim(user:, project:, kind:, dedupe_key:, issue:)` records one instant alert as `"sent"` under the cap or `"folded"` at it, and returns that status or nil for a used key; the count and the insert run in one transaction under a per-user advisory lock (`pg_advisory_xact_lock(CAP_LOCK, hashint8(user_id))`), so concurrent jobs can't overshoot. The summary email ("and N more alerts", `AlertSummary`) reads `where(user:).awaiting_summary` and sets `summarized_at`.
  - `created_at` is set from `Time.current` (the app clock the cap and throttle windows are measured with), not the database's `CURRENT_TIMESTAMP`.
  - `AlertDelivery.alerted_recently?(issue, kind, within: AlertDelivery::STILL_HAPPENING_WINDOW)` checks across recipients before any per-user work.
  - Deliveries are pruned after `AlertDelivery::KEPT_FOR` (30 days, `Ingest::Retention#prune_alert_deliveries`): every key's window is shorter, and new_issue/reached_production can't fire twice.
- Mute links: `user.alert_mute_token(project, stream: "alerts" | "digest")` → `alert_mute_url(token:)` for both `List-Unsubscribe: <…>` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`. `AlertMute.find_by_token(token)` returns nil for tampered, expired (`AlertMute::EXPIRES_IN`, 60 days), wrong-purpose or unknown-stream tokens, deleted apps and ex-members; `#apply` turns that stream off for that app only. The token is signed, not encrypted, and carries only the user id, project id and stream.

### 11.3 Screens

- **Settings › Alerts** (`projects/alerts/show`, `Projects::AlertsController`, sidebar "Alerts" and the settings sub-nav): an intro naming who gets the emails and pointing at Notifications; a **Rules** panel with one row per kind (title, one-line description, a muted "off" chip when off, and an `aria-pressed` `.toggle` that is a one-button PATCH form, `AlertsHelper#switch_button_to`); the `still_happening` row has a threshold number field (fixed `w-32`, since Rails wraps an invalid field in `div.field_with_errors`) with Save and an inline error, "Threshold must be a whole number from 1 to 100,000" (`AlertRule::THRESHOLD_MESSAGE`), with `aria-invalid` and a coral border; an **Environments** panel with three radios (follow the default environment, naming it in its tone; all environments; only these) and a checkbox per `project.environments` with `environment_dot` and `environment_text`, plus "The rules above watch …" in tone, built from the saved settings (`saved_alert_environments`) so a rejected form doesn't change it. An empty "only these" shows "Pick at least one environment." (errors are whole sentences, shown without the attribute name). Switching away from "only these" clears the ticked environments. Any account member can change it, like Settings › General.
- **Notifications** (`notifications/show`, user menu → Notifications): the address alerts go to, the time zone digests use (`users.time_zone`), and a row per app of `Current.account` with two switches, "Email alerts" (pressed = not muted) and "Daily digest", plus "Watching <environments>". When the app's digest rule is off, the digest cell shows an "Off for this app" link to Settings › Alerts instead of a switch (the person's saved choice is kept and applies again once the rule is on). An unverified member sees that alerts start once they confirm. Fixed query count however many apps.
- **Mute link pages** (`alert_mutes/*`, auth layout): `show` asks "Mute email alerts?" / "Mute the daily digest?" naming the app and address, or says "Already off"; the button is a plain (`data-turbo=false`) POST because `create` answers 200 as RFC 8058 expects; `create` confirms "Muted"; `invalid` (404) says "This link no longer works" (expired after 60 days, left the account, or the app was deleted) and links to Notifications. Any browser may open these pages. All three link to Notifications for turning things back on.

### 11.4 Delivery (slice B)

Every alert email is decided in a job, never on the request or in the ingest transaction. Job arguments are integer ids, kind strings and (for the summary) counts; mail jobs get GlobalIDs. Nothing captured goes into Redis, logs or exceptions.

**Flow**

```
ingest (after commit) ──► IssueAlertJob(issue_id, kind, occurrence_id)  ─┐
CheckStillHappeningJob (*/5) ──► IssueAlertJob(issue_id, "still_happening") ─┤
                                                                         ├► IssueAlert#deliver ─► AlertDelivery.claim per recipient ─► AlertsMailer.issue_alert.deliver_later ("sent" only)
SendDailyDigestsJob (hourly) ──► DailyDigest#deliver ─► AlertDelivery.record(digest_key) ─► AlertsMailer.digest.deliver_later
SendAlertSummariesJob (hourly, :02) ──► AlertSummary#deliver ─► summary row + folded rows marked ─► AlertsMailer.summary.deliver_later
```

**Ingest triggers** (`Ingest::Processor#flag_alerts`, after the transaction commits, §2.5). `IssueAlert.transitions(issue, created:)` reads what the counter UPDATE already returned: `new_issue` when `tally.created?`, `regression` when `previous_status == "resolved"`, `reached_production` when `just_reached_production`. Each enqueues one `IssueAlertJob` with the issue id, the kind and the new occurrence's id (the `returning: id` of the occurrence insert). An ordinary event of an existing issue enqueues nothing and runs no extra statement. A resolved staging-only issue that regresses in production flags both rules. Duplicates (rolled back) and ignored issues flag nothing. The issue row lock makes `reached_production` flag exactly once under concurrent events (`concurrent_processing_test.rb`).

**`IssueAlert`** (`app/models/issue_alert.rb`) decides at send time (`#due?`):
- the app's rule for the kind is on (`project.alert_rule_enabled?`);
- the issue is still `unresolved` (resolved and ignored issues never alert);
- the scope covers the triggering occurrence's environment (`project.alerts_cover?([occurrence.environment])`); without an occurrence (still_happening) any of `issue.environments`. So with the default scope (production), a new staging issue doesn't alert, and its first production event alerts as `reached_production`;
- still_happening only: `AlertDelivery.alerted_recently?(issue, kind)` is false (6 hours, across recipients).
`#deliver` then claims a delivery per `project.alert_recipients` user (`AlertDelivery.claim` with `issue_key`): `"sent"` → `AlertsMailer.issue_alert(user, issue, kind).deliver_later`; `"folded"` → nothing now (summary); nil (key used) → nothing. Returns the users mailed.

**still_happening sweep** (`StillHappeningCheck`, `CheckStillHappeningJob` every 5 minutes). One query across all apps: unresolved issues joined to their project's enabled `still_happening` rule and their `issue_hourly_counts` of the last two clock hours, `last_seen_at` in that window, grouped by issue and threshold, `HAVING` the trailing-hour estimate `>= alert_rules.threshold`. The estimate (`IssueHourlyCount::TRAILING_HOUR_SUM`, as `ProjectHealth`) is the current hour's count plus the not-yet-elapsed share of the previous hour's; its bind values are cast (`CAST(:previous_share AS double precision)`) because Postgres otherwise infers an integer. Issues alerted in the last 6 hours (one batched `alert_deliveries` query), issues outside their app's scope, and issues of apps with nobody to mail (`project.alert_recipients.exists?`, one EXISTS per app per sweep) are dropped, and the rest are enqueued with one `ActiveJob.perform_all_later`. The recipients check matters because an app every member muted records no delivery, so the 6-hour throttle would never start and each sweep would enqueue a no-op job per hot issue. The 6-hour throttle is the sweep's pre-filter, `IssueAlert#due?` again, and the per-user key (`still_happening:<id>:<6h window>`).

**Daily digest** (`DailyDigest`, `SendDailyDigestsJob` hourly at :00). For each app with the `daily_digest` rule on (`AlertRule.enabled.daily_digest.includes(:project)`), `#due_recipients` is `project.digest_recipients` whose local time (`users.time_zone`) is in the 09:00 hour. Nothing happens unless someone is due and `#issue_count` (unresolved, `last_seen_at` in the last 24 hours, `environments && ARRAY[scope]` unless the scope is all) is positive. Each due user gets `AlertDelivery.record(kind: daily_digest, dedupe_key: digest_key(project, local_date))` and, if it inserted, `AlertsMailer.digest(user, project).deliver_later`. Dedupe per local date makes repeated or late runs within the hour harmless; DST changes move 09:00 between UTC hours but never onto another local date, so each local day gets one digest (tests cover Europe/London across 2026-10-25 and Asia/Kolkata's half-hour offset, where the :00 run lands at 09:30). `#issues` lists up to `LISTED` (10) issues with `recent_events` (sum of `issue_hourly_counts` since the hour containing 24 hours ago), busiest first, in one grouped query; `#more_count` is the rest. Digests don't count towards the cap.

**Hourly cap and summary** (`AlertSummary`, `SendAlertSummariesJob` at :02). Instant alerts over `AlertDelivery::HOURLY_CAP` are recorded `folded` by `AlertDelivery.claim`. After each clock hour, every user with folded rows created before that hour gets one summary: in one transaction, the summary row (`kind: summary`, `summary_key(now)`, `project_id` = the app of the earliest folded row, since the column is required) is recorded first (a nil insert means this hour's summary already went), the folded rows are counted per app and kind, and they're marked `summarized_at`. The mailer gets `{ "project_id" => { "kind" => count } }`. Folded rows from the current hour wait for the next run. Finding the users is an index-only scan of the partial `index_alert_deliveries_awaiting_summary` (§1.3).

**`AlertsMailer`** (`app/mailers/alerts_mailer.rb`, views in `app/views/alerts_mailer/`, `helper :alert_emails, :number`):
- `issue_alert(user, issue, kind)`: subject `"<Rule> in <app>: <redacted title>"` (squished, ≤ 100 chars). Body: heading, one-line intro per kind, exception class, redacted title, then details (short id, environments as pills in their `EnvironmentTone`, transaction · culprit, last-hour events vs threshold for still_happening, events and users, first and last seen), an "Open GS-1042" button to `project_issue_url` and the link fallback.
- `digest(user, project)`: subject `"Daily digest for <app>: N open issues in the last 24 hours"`; one block per listed issue (short id · class, linked title, environment pills, 24h events and last seen), "And N more issues", and a button to the app's issue list.
- `summary(user, counts)`: subject `"And N more alerts from Good Sorcery"`; one row per app ("New issue: 3 · Regression: 1"), apps limited to the user's accounts, then a button and link fallback to the app's issue list (one app) or the projects page (`@open_url`).
- Send-time checks in the mailer itself (it returns without `mail`, so nothing is sent): the issue is unresolved; `project.account.memberships.find_by(user:)` exists and `receives_alerts?` / `receives_digest?` (verified address, stream not switched off); the summary needs a verified user and at least one app of theirs.
- Times render in the recipient's zone (`Time.use_zone(user.time_zone)` around `mail`), as `"Oct 11, 2026 09:14 BST"`.
- Headers: `List-Unsubscribe: <alert_mute_url(token: user.alert_mute_token(project, stream:))>` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`, stream `alerts` for alerts, `digest` for digests; the summary carries them only when it covers one app. The footer repeats the mute link and links to `notifications_url`.
- Content rule: only the issue's redacted summary columns (`message`, `exception_class`, `transaction_name`, `culprit`), environment names, numbers, times and links. Never occurrence payloads, tag values or user identities (`test/mailers/alerts_mailer_test.rb` asserts the fixture payload's locals, params, headers, user and context are absent from subject, parts and headers). HTML is ERB-escaped; text parts output values with `raw`, per the email template rule.
- `MailerHelper` gained `email_code`, `email_title`, `email_title_link`, `email_environment(s)` (`EMAIL_TONES`), `email_details` (label column a fixed 110px, so stacked detail tables line up) and `email_footer_link`. Previews: `test/mailers/previews/alerts_mailer_preview.rb`; they pick an unresolved issue inside its app's alert scope and render with `travel_to` one minute after its `last_seen_at`, so aged demo data still yields a digest and a non-zero "Last hour".

**Jobs and schedule.** `IssueAlertJob`, `CheckStillHappeningJob`, `SendDailyDigestsJob` and `SendAlertSummariesJob` run on the `alerts` queue (`config/sidekiq.yml` weight 2); the emails go through `mailers`. `config/schedule.yml` (sidekiq-cron, UTC): `check_still_happening` `*/5 * * * *`, `send_daily_digests` `0 * * * *`, `send_alert_summaries` `2 * * * *`.

**Cost.** Per instant alert: the rule, scope and issue checks (2–3 queries), one recipients query, then per recipient a short transaction (advisory lock, cap count on `[user_id, status, created_at]`, insert). The sweep is one grouped query plus one throttle query every 5 minutes, and one EXISTS per app that has hot issues. The digest run is one recipients query per app with the rule on, per hour, and two issue queries only when someone is at 09:00.

### 11.5 Slack alerts (approved 2026-11-08)

Each app can post its alerts to one Slack channel through an incoming webhook that a member pastes in Settings › Alerts. Slack follows the app's email rules and environment scope exactly: new issue, regression, reached production, still happening, monitor down and recovered. There is no daily digest in Slack. Each event gets one post, not one per recipient, and it doesn't depend on anyone's email switches.

**Schema** (migration `20261108000001`).
- `slack_connections`: `project_id` (unique, FK cascade), `webhook_url` text NOT NULL (**encrypted**), `enabled` boolean default true, `disabled_at` / `disabled_reason` (set when Slack rejects the webhook; the reason is Slack's error code from `SlackWebhook::REJECTION_CODES` or `http_404`/`http_410`, never response text or the URL), `test_sent_at`, timestamps. `Project has_one :slack_connection`; `project.slack_alerts_enabled?`.
- `slack_deliveries` is the Slack counterpart of `alert_deliveries`, keyed per app. Columns: `project_id`, `issue_id` / `uptime_incident_id` (nullable, FK cascade), `kind` (the instant and uptime kinds plus `summary`), `dedupe_key`, `status` (`sent`/`folded`, check constraint), `summary_counts` jsonb (summary rows: `{ kind => count }`), `posted_at`, `summarized_at` and `created_at`.
- Its indexes: unique `[project_id, dedupe_key]`; `[project_id, status, created_at]` for the cap count; `[issue_id, kind, created_at]` for the still_happening throttle; the partial `index_slack_deliveries_awaiting_summary`; `created_at` for pruning. Rows hold ids, kinds, keys and counts only.
- Pruned with `alert_deliveries` after `AlertDelivery::KEPT_FOR` (`Ingest::Retention#prune_slack_deliveries`), keeping an open incident's down row for its recovered post.

**Decision** (no new trigger points, no ingest queries). `IssueAlertJob` runs `IssueAlert#deliver` (email) and then `SlackIssueAlert#post_later`; `UptimeAlertJob` runs `UptimeAlert#deliver` and then `SlackUptimeAlert#post_later`. `Ingest::Processor#flag_alerts` is unchanged (`alert_flags_test.rb` still pins 12 statements, with storefront's Slack connection on, and asserts no `slack` table is touched).
- `SlackIssueAlert#due?`: an enabled connection, the rule on (`AlertRule::INSTANT_KINDS` only), the issue unresolved, the scope covering the triggering occurrence's environment (`IssueAlert::TriggeringEnvironments`, which `IssueAlertJob` shares with `IssueAlert`: the occurrence is looked up at most once, and not at all when neither channel gets that far), and for still_happening no Slack post for the issue in the last 6 hours (`SlackDelivery.posted_recently?`). `#post_later` then calls `SlackDelivery.claim`, and enqueues `SlackPostJob(delivery_id)` only for a `sent` row.
- `SlackUptimeAlert#due?`: an enabled connection, the rule on, the incident open (down) or resolved (recovered); recovered also needs this incident's Slack down row, unless the down rule is off (as for email). Recorded with `SlackDelivery.record`, never `.claim`: uptime posts skip the cap.
- **Still-happening sweep.** `StillHappeningCheck` treats each channel separately. An issue is enqueued while it is due on either channel: not emailed in the window and the app has recipients, or not posted in the window and the app's Slack is on. It is dropped only when both are done, so an app whose members all muted email but which posts to Slack still gets its job. The Slack row starts the Slack throttle, so there is still no job every sweep. Issues emailed in the window are narrowed in SQL to apps with Slack on (`slack_due`) before any issue is loaded, so throttled issues of apps without Slack cost no row loads.

**Throttle and cap.**
- Keys are `"slack:" + AlertDelivery.issue_key / incident_key / summary_key` (`SlackDelivery.dedupe_key`), inserted `ON CONFLICT DO NOTHING`, so retries, duplicate jobs and repeated sweeps never post twice.
- `SlackDelivery::HOURLY_CAP` allows 30 issue-alert posts per app per hour. `claim` counts under a per-app `pg_advisory_xact_lock(4712, hashint8(project_id))` inside `uncached`, and over the cap it records the row as `folded`.
- `SlackSummary.post_due` runs from `SendAlertSummariesJob` at :02, after `AlertSummary`. For each app with folded rows from before the hour, it records one `summary` row with the counts per kind, marks the folded rows `summarized_at`, and enqueues the post ("And N more alerts in <app> in the last hour", `SlackMessage::Summary`).

**Delivery.** `SlackPostJob(slack_delivery_id)` (queue `alerts`) calls `SlackPost#deliver`, which checks again at send time:
- the connection still exists and is enabled;
- the row isn't posted yet;
- the alert still qualifies: `SlackIssueAlert#still_due?` (the rule on, the issue unresolved, the scope covering any of the issue's environments), `SlackUptimeAlert#still_due?`, and summaries always.

`SlackWebhook#post`:
- Net::HTTP via `UptimeProbe::Connection` (caps every byte read), with `verify_mode` PEER, a 5 s connect, 10 s read and write timeout, a 20 s `Timeout` backstop, no proxy from ENV, `max_retries = 0`, and redirects never followed (a 3xx is a failure). At most 4 KB of the body is kept. It refuses any URL outside `SlackConnection::WEBHOOK_URL`.
- 2xx sets `posted_at`.
- 429 calls `retry_job(wait: Retry-After)`: an integer clamped to 1..900 s, else 60 s.
- 5xx or a network error retries with backoff: 30 s, 2 min, 10 min, 30 min. At most `SlackPostJob::MAX_ATTEMPTS` (5) posts in all.
- 404, 410, or a 4xx whose body is in `REJECTION_CODES` (`invalid_token`, `action_prohibited`, `channel_not_found`, `channel_is_archived`, `no_service`, `no_team`, `team_disabled`, …) calls `SlackConnection#turn_off_after_rejection(reason)`.
  - One atomic `UPDATE … WHERE disabled_at IS NULL` sets `enabled = false`, `disabled_at` and `disabled_reason`.
  - Only the call that wins mails each verified owner: `AlertsMailer.slack_disabled`, "Slack alerts for <app> were turned off because Slack rejected the webhook". Its send-time checks: the connection is still rejected and the recipient is still a verified owner.
- Any other 4xx (such as `invalid_payload`) is dropped without a retry.
- Logs: `SlackPostJob delivery=<id> kind=<kind> outcome=<outcome> status=<HTTP status or error class>`. Never the URL, and never an exception message.

**Message** (`SlackMessage::IssueAlert`, `UptimeAlert`, `Summary`, `TestMessage`): Block Kit `blocks` plus a plain `text` fallback (≤ 400 chars).
- Issue alerts carry:
  - the kind label and the app;
  - the redacted title (`message`, else `exception_class`, ≤ 300 chars);
  - environments, and events and users;
  - the last hour against the threshold (still_happening only);
  - first and last seen as `<!date^…>` tokens, shown in each reader's own zone with a UTC fallback;
  - an "Open GS-1042" button.
- Uptime alerts carry the monitor's name and host, the cause, since or back up, the interval, and an "Open monitor" button. Never the monitor URL.
- Links come from `config.action_mailer.default_url_options`, which is `GOODSORCERY_PUBLIC_URL` in production.
- Captured data never appears: no occurrence payloads, params, headers, backtraces, culprit, transaction or user identities.
- Every dynamic string is escaped (`&`, `<`, `>` become entities), so nothing can form a link, mention or `<!channel>`. Every mrkdwn text object is `verbatim: true`.

**Screen** (Settings › Alerts, the last panel, `projects/alerts/_slack`):
- The heading has a status chip: Connected (mint), Off (muted), or Turned off by Slack (coral). A rejected connection also shows "Turned off because Slack rejected the webhook on <date>: <reason in words>".
- A connected app shows "Post alerts to Slack" with only the masked URL (`masked_webhook_url`: the first 4 characters of the team and bot ids, then `••••••••`) and an `aria-pressed` switch. Next to it are "Send test message", "Disconnect" (with a Turbo confirm) and when the last test was sent.
- Below is the webhook URL form: "Connect Slack" before connecting, "Replace" after. The field is `value: nil`, so it never echoes a URL, even after a rejected submit. Errors don't repeat the value either.
- A `<details>` "How to get a webhook URL" (open until connected) gives the four steps and links to https://api.slack.com/messaging/webhooks.
- Who can change it follows the rest of Settings › Alerts: any account member. Outsiders get 404.

**Security.**
- The webhook URL is the credential. It is encrypted at rest and decrypted only to post and to build the mask.
- It never appears in job arguments (ids only), Redis, `Rails.cache`, broadcasts, logs (request params are filtered by `:url`; client errors are logged by class), validation or exception messages, `slack_deliveries`, emails or other pages.
- Validation accepts only `https://hooks.slack.com/services/T…/B…/<alphanumeric secret>`. No other host or lookalike, no userinfo, port, query, fragment, trailing path or encoded characters.
- Fixtures: storefront's URL carries `SlackFixtureSecret`. Tests assert it never reaches the raw column, job arguments, logs, rendered pages or emails.


---

## 12. Uptime monitoring and entitlements (approved 2026-11-03)

This section is the binding blueprint for the uptime build. It comes in four slices (§12.12) that run in order: slice 1, then slice 2, then slices 3 and 4 in parallel, then an integration review. Everything in §0 (ground rules), §6 (authorization) and the §9/§10 checklists applies. **Monitor URLs are treated like captured data:** they may carry tokens in their query strings (§12.6).

### 12.0 Decisions (binding)

- goodsorcery_web never knows about plan tiers. The words "free", "premium" or any tier name never appear in code, config, copy or tests. It stores entitlement **values** per account and nothing else.
- Entitlements are stored per account, but `max_monitors` is a limit **per app**: each app of the account may have that many uptime monitors (changed from per account on 2026-11-07).
- **Hosted mode** is `GOODSORCERY_HOSTED`, read once at boot into `config.x.hosted`.
  - **Self-hosted** (the default, switch off): every entitlement is unlimited, meaning all four intervals, no monitor cap, no app cap, no monthly event quota and every retention choice (30, 60 and 90 days). Stored values are ignored, and the UI never shows a locked option or "Upgrade to unlock".
  - **Hosted:** stored values win. Any key the account lacks falls back to the hosted defaults in `config/entitlements.yml`: `uptime_intervals: [10, 60]`, `max_monitors: 1` (one monitor per app), `max_projects: 2` (two apps per account), `monthly_event_quota: 3000` (error events per UTC month) and `retention_days: [30]` (the error retentions its apps may choose).
- **Apps per account** (`max_projects`, approved 2026-11-07, §12.2.1): hosted accounts may create up to `max_projects` apps. Accounts already over it keep every app they have; they just can't add more.
- **Monthly event quota** (`monthly_event_quota`, approved 2026-11-07, §12.2.2): the v1 `accounts.monthly_event_quota` column became an entitlement. Hosted accounts get 3,000 error events per UTC month unless a value is stored; ingest answers `429 quota_exceeded` past it. Self-hosted instances never have a quota.
- **Error retention** (`retention_days`, approved 2026-11-07, §12.2.3): each app keeps occurrences 30, 60 or 90 days; the entitlement lists which of those its account's apps may choose (hosted default `[30]`, self-hosted all three). Apps on a retention their account no longer allows move to the nearest allowed one (§12.3.2).
- Entitlements are enforced in model validations, so a crafted POST can't get past them, and they are also reflected in the views.
- Locked options say **"Upgrade to unlock"**, linking to `GOODSORCERY_UPGRADE_URL` (`config.x.upgrade_url`), when that is set. When it isn't, no upgrade text renders anywhere: locked options stay visible, greyed out and unselectable, titled **"Coming soon"** (a native hover tooltip, on a span rather than a disabled button so every browser shows it), and an add button at a limit becomes the greyed-out sentence "Cannot add more yet, but it's coming soon" (for apps: "Cannot add more apps yet, but it's coming soon"). `UpgradeOffer` is the one place that decides between the two (approved 2026-11-07).
- **Monitors** belong to an app (project), and every lookup is scoped through `Current.account`.
  - Intervals are 1, 5, 10 or 60 minutes, and the default is 10. Entitlements narrow the allowed set further.
  - A check is an HTTP(S) GET with a 10-second total budget. "Up" means a 2xx or 3xx response arrived in time. A failed check is retried once at once before the monitor is marked down. Response bodies are never stored.
- **Alerts:** two new kinds, `monitor_down` and `monitor_recovered`, are added to the §11 email system. They are exempt from the 20-per-hour cap and are never folded into the "and N more" summary.
- The model is called **`UptimeMonitor`**, never `Monitor`. Ruby's stdlib `Monitor` class is used by Rails itself, so a top-level `Monitor` model would break the app.

### 12.1 Schema

```
Account ──< Project ──< UptimeMonitor ─┬─< UptimeCheck        (raw results, short-lived)
   │                                   ├─< UptimeHourlyCount  (rollups for uptime % and bars)
   └ entitlement_values (jsonb)        └─< UptimeIncident     (down periods; alert dedupe unit)
```

All ids are `bigint`. FKs are real constraints with `on_delete: :cascade`, so deleting a monitor deletes its history. Models declare `has_many … inverse_of:` without `dependent:`, as `Project` does.

**accounts** (slice 1, migration `add_entitlement_values_to_accounts`)
| column | type | null | default | notes |
|---|---|---|---|---|
| entitlement_values | jsonb | false | `{}` | Values pushed by the billing app (§12.3). Only known keys (`Entitlements::KEYS`) are stored. Ignored when self-hosted |

The column is `entitlement_values`, not `entitlements`, so the column reader doesn't clash with `Account#entitlements`, which returns the PORO.

**uptime_monitors** (slice 2)
| column | type | null | default | notes |
|---|---|---|---|---|
| project_id | references → projects, cascade | false | | |
| name | string | false | | 1..60 chars, plaintext label. Blank means the URL's host is filled in `before_validation` |
| url | text | false | | **encrypted** (non-deterministic). ≤ 2,048 chars, validated by `UptimeUrl` (§12.5) |
| interval_minutes | integer | false | 10 | check constraint `interval_minutes IN (1, 5, 10, 60)` |
| status | string | false | `"pending"` | enum `pending up down`; check constraint |
| next_check_at | datetime | false | | Set to `Time.current` on create and whenever the URL or interval changes. Then bumped by the scheduler's claim (§12.4) |
| last_checked_at | datetime | true | | |
| last_response_time_ms | integer | true | | |
| last_http_status | integer | true | | |
| last_error_kind | string | true | | `UptimeCheck::ERROR_KINDS` |
| down_since | datetime | true | | Set when the monitor goes down and cleared on recovery |
| paused_at | datetime | true | | Set only by `fit_uptime_monitors_to_entitlements` (§12.3) when its app is over the monitor limit. The scheduler skips paused monitors |
| timestamps | | | | |

Indexes: `[project_id, name]`, and the partial `index_uptime_monitors_due` on `[next_check_at] WHERE paused_at IS NULL`, which is the scheduler's only access path.

**uptime_checks** (slice 2; one row per scheduled or requested check, with the retry folded in)
| column | type | null | notes |
|---|---|---|---|
| uptime_monitor_id | references → uptime_monitors, cascade | false | |
| checked_at | datetime | false | |
| status | string | false | `up` or `down` (check constraint) |
| response_time_ms | integer | true | Time to the final response's headers, or nil when no response arrived |
| http_status | integer | true | The final response's status code |
| error_kind | string | true | `UptimeCheck::ERROR_KINDS`, nil when up |

There is no `updated_at`, no body, no URL, no headers and no exception message. Index: `[uptime_monitor_id, checked_at]`, used for history and pruning.

**uptime_hourly_counts**: `create_table …, primary_key: [:uptime_monitor_id, :hour]` (slice 2)
| column | type | null | default | notes |
|---|---|---|---|---|
| uptime_monitor_id | bigint FK → uptime_monitors, cascade | false | | |
| hour | datetime | false | | UTC hour start |
| checks_count | integer | false | 0 | |
| up_count | integer | false | 0 | |
| response_time_ms_sum | bigint | false | 0 | Up checks only, so the average is `sum / up_count` |

Extra index: `[hour]`, used for pruning by hour slice like the other rollups.

**uptime_incidents** (slice 2)
| column | type | null | notes |
|---|---|---|---|
| uptime_monitor_id | references → uptime_monitors, cascade | false | |
| started_at | datetime | false | `checked_at` of the check that went down |
| resolved_at | datetime | true | nil while the incident is open |
| error_kind | string | true | The cause at the start |
| http_status | integer | true | |

Indexes: `[uptime_monitor_id, started_at]`, `[resolved_at]` (pruning), and the unique partial `index_uptime_incidents_one_open` on `[uptime_monitor_id] WHERE resolved_at IS NULL`. That index guarantees at most one open incident per monitor.

**notification_preferences** (slice 4): adds `uptime_alerts_muted boolean, null: false, default: false`.

**alert_rules** (slice 4): no column change. A data migration inserts `monitor_down` and `monitor_recovered` rows, both enabled, for every existing project (`INSERT … SELECT … ON CONFLICT (project_id, kind) DO NOTHING`).

**Encryption (§1.4):** `UptimeMonitor#url` joins the list of encrypted attributes. Slice 2 adds the raw-ciphertext model test.

### 12.2 Entitlements (slice 1)

**Configuration** (`config/application.rb`, read once at boot):

```ruby
config.x.hosted = ActiveModel::Type::Boolean.new.cast(ENV["GOODSORCERY_HOSTED"]) || false
config.x.upgrade_url = ENV["GOODSORCERY_UPGRADE_URL"].presence
config.x.entitlements = config_for(:entitlements)          # config/entitlements.yml
# Local testing of uptime checks against private addresses; never honoured in production.
config.x.uptime.allow_private_addresses = ENV["GOODSORCERY_UPTIME_ALLOW_PRIVATE_ADDRESSES"] == "1" && !Rails.env.production?
```

`config/entitlements.yml`:
```yaml
# Hosted mode only (GOODSORCERY_HOSTED=1). An account's stored values
# (accounts.entitlement_values) win; these fill in any key it lacks.
# Self-hosted instances ignore this file: every entitlement is unlimited.
shared:
  hosted_defaults:
    uptime_intervals: [10, 60]
    max_monitors: 1        # per app
    apm_retention_days: 1  # §13.7
    max_projects: 2        # apps per account (§12.2.1)
    monthly_event_quota: 3000 # error events per UTC month (§12.2.2)
    retention_days: [30]   # error retentions an app may choose (§12.2.3)
```

`ApplicationHelper#hosted?` returns `Rails.configuration.x.hosted`. Existing tests that set `ENV["GOODSORCERY_HOSTED"]` switch to the `with_hosted_mode` test helper.

**`Entitlements`** (`app/models/entitlements.rb`) is a plain value object, built per call, that never queries:

```ruby
Entitlements::UPTIME_INTERVALS        # => [1, 5, 10, 60]  every interval uptime supports
Entitlements::DEFAULT_UPTIME_INTERVAL # => 10
Entitlements::RETENTION_CHOICES       # => [30, 60, 90]  every error retention an app can choose (Project::RETENTION_CHOICES)
Entitlements::KEYS                    # => %w[uptime_intervals max_monitors apm_retention_days max_projects monthly_event_quota retention_days]
Entitlements::CAP_KEYS                # => %w[max_monitors max_projects]  nil or an integer >= 0

entitlements = account.entitlements   # Entitlements.new(account.entitlement_values)
Entitlements.new(values, hosted: Rails.configuration.x.hosted,
                 hosted_defaults: Rails.configuration.x.entitlements.hosted_defaults)

entitlements.unlimited?                      # true when self-hosted
entitlements.uptime_intervals                # sorted subset of UPTIME_INTERVALS
entitlements.allows_uptime_interval?(5)      # true/false
entitlements.locked_uptime_intervals         # UPTIME_INTERVALS - uptime_intervals ([] when self-hosted)
entitlements.default_uptime_interval         # 10 if allowed, else the smallest allowed above 10, else the largest allowed
entitlements.nearest_uptime_interval(1)      # smallest allowed >= minutes, else the largest allowed (used by fitting)
entitlements.max_monitors                    # Integer (monitors per app), or nil for no cap
entitlements.monitor_limit_reached?(count)   # count is one app's monitors; false when max_monitors is nil
entitlements.monitors_left(count)            # nil when uncapped, else [max - count, 0].max
entitlements.max_projects                    # Integer (apps per account), or nil for no cap
entitlements.project_limit_reached?(count)   # count is the account's apps; false when max_projects is nil
entitlements.monthly_event_quota             # Integer (error events per UTC month), or nil for no quota
entitlements.retention_days                  # sorted subset of RETENTION_CHOICES (all of them self-hosted)
entitlements.allows_retention_days?(60)      # true/false
entitlements.locked_retention_days           # RETENTION_CHOICES - retention_days ([] when self-hosted)
entitlements.nearest_retention_days(45)      # the closest allowed; a tie goes to the longer (used by fitting)
entitlements.default_retention_days          # nearest_retention_days(30): a new app's retention
Entitlements.problems(values)                # => [] or whole-sentence messages, for Account validation
```

Resolution per key: self-hosted gives the unlimited value. Hosted gives the stored value if the key is present and valid, otherwise the hosted default. A present but invalid stored value (impossible through `Account` validation, but possible if the column is edited by hand) falls back to the default. It is logged as `"Ignoring invalid entitlement #{key} for account #{id}"`, with the key name only. In stored JSON, `"max_monitors": null` (or `"max_projects": null`, `"monthly_event_quota": null`) explicitly means no cap, which is different from a missing key.

Valid values: `uptime_intervals` is a non-empty array of distinct integers from `UPTIME_INTERVALS`. `max_monitors` and `max_projects` are each `null` or an integer ≥ 0 (`PROBLEMS["max_projects"]` = "Max projects must be empty (no limit) or a whole number of 0 or more."). `monthly_event_quota` is `null` or an integer > 0 ("Monthly event quota must be empty (no limit) or a whole number greater than 0."). `retention_days` is validated like `uptime_intervals`: a non-empty array of distinct integers from `RETENTION_CHOICES` ("Retention days must be a non-empty list of distinct values from 30, 60, and 90.").

**`Account`** (slice 1):
- `#entitlements` returns an `Entitlements` object.
- `validate :entitlement_values_well_formed` uses `Entitlements.problems`.
- `#update_entitlements!(values)` replaces the whole document. It stores only `KEYS` and drops unknown keys, logging the key names only. This is the single write path the future push uses.

**`EntitlementsHelper`** (slice 1):
- `upgrade_to_unlock(text = "Upgrade to unlock", classes: …)` renders a link to `config.x.upgrade_url` (`target: "_blank"`, `rel: "noopener noreferrer"`) when the URL is set, and nothing (nil) otherwise.
- `upgrade_offered?`, `locked_note` ("Upgrade to unlock" or "Coming soon"), `locked_option(content, classes:, aria:)` (a greyed-out span titled `locked_note`) and `coming_soon_notice(sentence)` (the greyed-out sentence that replaces an add button at a limit). They all ask `UpgradeOffer` (`.url`, `.available?`, `.locked_note`, `.limit_message(limit_sentence, coming_soon:)`), which model validations also use to word their limit errors.
- `entitlements` returns `Current.account.entitlements`, memoised per request.
- `project_limit_reached?` and `new_app_limit_notice` (§12.2.1).
- Views only call these helpers when `!entitlements.unlimited?`.

#### 12.2.1 Apps per account (`max_projects`, approved 2026-11-07)

- **Enforced** by `Project`'s `validate :within_project_limit, on: :create`, declared first: when `max_projects` is not nil (hosted) it locks the account row (`FOR NO KEY UPDATE`, inside `save`'s transaction, so concurrent creates serialise; `test/models/project/concurrent_create_test.rb`) and counts the account's apps uncached. At the limit the error on `:base` is `Project.limit_message(max)`: "This account has reached its limit of N app(s)." ("Apps aren't included in this account." for 0) with an upgrade URL, and "Cannot add more apps yet, but it's coming soon" without one. `Project::MAX_PER_ACCOUNT` (100) still caps every instance.
- **Existing apps are kept.** Nothing is disabled or deleted when an account is over its limit (acme's fixtures have 3 apps against the default of 2); updates and every app page work as before. There is nothing to fit.
- **Onboarding:** a new account has 0 apps, so it can always create its first one unless its stored `max_projects` is 0.
- **UI:** `EntitlementsHelper#project_limit_reached?` (false self-hosted or without an account; the count comes from the sidebar switcher's query when it holds every app, `NavigationHelper#account_project_count`, so it costs no query of its own). At the limit, every "Add a new app" entry point (the overview's new-app tile, the switcher menu item and the switcher's no-app button) is replaced by `new_app_limit_notice`, and the Projects header button is left out so the overview doesn't show the sentence twice: the greyed-out "Cannot add more apps yet, but it's coming soon" (not a link) without an upgrade URL, or "App limit reached." plus `upgrade_to_unlock` with one. `GET /projects/new` at the limit answers 200 with a panel (`#project_limit`, `Project.limit_message`, the upgrade link when set and "Back to Projects") instead of the form; a crafted `POST /projects` gets 422 with the same panel.

#### 12.2.2 Monthly event quota (`monthly_event_quota`, approved 2026-11-07)

- **Values:** `nil` (no quota) or an integer > 0, counting error events per UTC month (the sum of `project_hourly_counts` since the month started, so events dropped by rate limits or rejected don't count; performance data never counts). Hosted default 3,000; self-hosted always unlimited, whatever is stored.
- **Migration** `move_monthly_event_quota_to_entitlements`: copies every non-null `accounts.monthly_event_quota` into `entitlement_values["monthly_event_quota"]` unless the key is already stored. The column stays and `Account` ignores it (`self.ignored_columns`): the previous release still selects and inserts it while this one boots (`db:prepare` runs before the switch) and after `bin/kamal rollback` or a revert, neither of which runs `down`. A later release drops it with a plain `remove_column`, once this one is live. `down` copies the stored values back into the column (a stored null, or anything not a positive integer, as NULL) and removes the key. `test/migrations/move_monthly_event_quota_to_entitlements_test.rb` runs both directions.
- **Enforced at ingest** by `IngestEndpoint#enforce_quota` → `Account.over_quota?(account_id)` (`Account::EventQuota`), after the rate limits and before the body is read: `429 {"error":"quota_exceeded"}`. Self-hosted it returns false without touching the cache or the database. Hosted it is one cache read of a boolean keyed `["account_over_quota", id]`, kept for `OVER_QUOTA_TTL` (1 minute); a miss loads the account and compares `events_this_month` (itself cached 5 minutes) with the resolved `entitlements.monthly_event_quota`, the hosted default included. An `after_update_commit` that changes `entitlement_values` writes the freshly computed answer over the key, and a miss writes only when the key is still empty (`unless_exist: true`), so a miss that read the account just before the commit can't leave its stale answer behind; a pushed quota applies at the next request; a changed hosted default (a restart) applies within the minute. No per-event query is added. `GET /api/v1/verify` and the APM endpoints never check the quota.
- **UI:** the sidebar's `layouts/_usage_meter` reads `entitlements.monthly_event_quota`: hosted shows "N / 3k" with a meter; nil (always self-hosted) shows nothing.

#### 12.2.3 Error retention (`retention_days`, approved 2026-11-07)

- **Choices:** `Project#retention_days` is one of `Project::RETENTION_CHOICES` (`Entitlements::RETENTION_CHOICES`, 30, 60 or 90 days; "must be 30, 60 or 90 days"), so `Project::MAX_RETENTION_DAYS` is 90. The entitlement lists the choices an account's apps may make: hosted default `[30]`, self-hosted all three whatever is stored.
- **Enforced** by `Project`'s `validate :retention_entitled` when the value is set (on create or when it changes, like uptime intervals): "isn't available on this account". An app left on a retention its account no longer allows still saves its other settings until fitting moves it. A new app gets the column default, 30, or `entitlements.default_retention_days` when 30 isn't allowed. The "Add a new app" form has no retention field.
- **UI:** Settings › General's Retention is a select of "30 days", "60 days" and "90 days" (`ProjectsHelper#project_retention_options`). Locked choices (hosted only) are disabled and labelled "90 days · Upgrade to unlock" with an upgrade URL, or "90 days · Coming soon" without one, titled the same; native option tooltips don't show, so a hint under the select (`#project_retention_days_locked_hint`, `project_locked_retention_hint_tag`) says "Some retention periods aren't available on this account." plus the upgrade link, or "Some retention periods are coming soon." titled "Coming soon".
- **Pruning** (`Ingest::Retention`): occurrences, affected users and tag counts per retention group as before, capped at `MAX_RETENTION_DAYS` (90). The per-app cap of 3,000 stored occurrences and the per-issue cap of 100 still apply whatever the retention. The issue and uptime rollup windows don't follow it: `ISSUE_ROLLUP_DAYS` (31) comes from the issue chart's 30-day view and `UPTIME_ROLLUP_DAYS` (31) from `UptimeReport::DAYS`, since nothing reads those counts further back.
- **Migration** `fit_project_retention_to_choices` moves every app on another value to the nearest choice by the same rule (a tie goes up, under 30 becomes 30). Retention was capped at 30, so every app ends on 30, allowed hosted and self-hosted. `down` sets 60 and 90 days back to 30, the most the previous release validates and prunes by, so those apps can still save Settings › General after a rollback.

**Test helpers** (`test/test_helper.rb`): `with_hosted_mode(hosted = true) { … }` sets and restores `Rails.configuration.x.hosted`; `with_upgrade_url(url = "https://billing.example/upgrade") { … }` does the same for `config.x.upgrade_url` (`with_upgrade_url(nil)` for "coming soon").

### 12.3 Future billing push contract (documented only; do not build)

A separate private billing app will **push** values to goodsorcery_web. Nothing here is built now. `Account#update_entitlements!` and the reconciliation below are the parts ready for it.

- **Endpoint:** `PUT /api/internal/v1/accounts/:account_id/entitlements`, routed only when `config.x.hosted`. It is an `ActionController::API` controller with no cookies, sessions or CSRF.
- **Auth:** an HMAC signature header, `X-Goodsorcery-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256(GOODSORCERY_BILLING_SECRET, "#{t}.#{raw_body}")>`.
  - Compare with `ActiveSupport::SecurityUtils.secure_compare`.
  - Reject a `t` more than 5 minutes from now.
  - Rate-limit per IP.
- **Body:** `{"entitlements":{"uptime_intervals":[1,5,10,60],"max_monitors":25,"apm_retention_days":30,"max_projects":10,"monthly_event_quota":100000,"retention_days":[30,60,90]},"sequence":42}`.
  - The document is complete: an omitted key falls back to the hosted defaults, and `"max_monitors": null`, `"max_projects": null` or `"monthly_event_quota": null` means no cap. `max_monitors` counts per app; `max_projects` counts the account's apps, and lowering it below the current count keeps every existing app and only blocks new ones. `monthly_event_quota` counts error events per UTC month; a new value applies at the next ingest request (§12.2.2). `retention_days` lists the retentions an app may choose; removing one moves the apps on it (§12.3.2), and the next daily prune deletes what they no longer keep.
  - `sequence` increases monotonically per account. A push whose `sequence` is ≤ the stored one is acknowledged and ignored, so out-of-order delivery is harmless. The push slice adds `accounts.entitlements_sequence bigint` for this; it is not added now.
- **Responses:**
  - `204` when applied or ignored as stale.
  - `401 {"error":"invalid_signature"}`.
  - `404 {"error":"unknown_account"}`.
  - `422 {"error":"invalid_entitlements","messages":[…]}`, built from `Entitlements.problems`.
- **Values only.** Tier names, prices and customer data are never sent or stored. The billing app maps its plans to values itself.
- **Effect:** `account.update_entitlements!(values)`. Its `after_update_commit` callbacks run `Account#fit_to_entitlements` (monitors, §12.3.1, and retention, §12.3.2) and expire the cached quota answer (§12.2.2).

#### 12.3.1 Fitting monitors to entitlements (slice 2, built now)

`Account::UptimeMonitoring#fit_uptime_monitors_to_entitlements` handles downgrades and upgrades, so lowering stored values never leaves monitors running outside them.

1. Every monitor whose interval isn't allowed gets `entitlements.nearest_uptime_interval(interval)`, with one `update_all` per distinct interval.
2. In each app, monitors beyond `max_monitors`, newest first by `id`, get `paused_at`. Paused monitors that fit again, oldest first, are unpaused, with `paused_at` set to nil and `next_check_at` to now. This is set-based: one subquery ranks every monitor of the account within its app (`ROW_NUMBER() OVER (PARTITION BY project_id ORDER BY id)`, `Account::UptimeMonitoring::APP_RANK_SQL`), and two `update_all`s pause and resume, however many apps and monitors there are.

When self-hosted, the result is all monitors unpaused and intervals left unchanged.

It runs in three places:
- after a commit that changes `entitlement_values` (through `Account#fit_to_entitlements`, which also fits retention, §12.3.2);
- after a monitor is destroyed (`after_destroy_commit`, which frees a slot);
- through `bin/rails goodsorcery:fit_entitlements` (all accounts, `find_each`, `Account#fit_to_entitlements`; `goodsorcery:fit_uptime_monitors` is kept as an alias), which operators run after switching hosted mode on **or off** or changing `config/entitlements.yml`. Switching off without it leaves monitors paused under hosted limits unchecked; the Uptime pages then say "Paused while this instance was hosted. Run `bin/rails goodsorcery:fit_entitlements` to resume it." (`UptimeHelper#uptime_paused_note`).

#### 12.3.2 Fitting app retention to entitlements (approved 2026-11-07)

`Account::ProjectRetention#fit_project_retention_to_entitlements` moves every app of the account whose `retention_days` isn't in `entitlements.retention_days` to the nearest allowed value, a tie going to the longer retention (`Entitlements#nearest_retention_days`). It is one `UPDATE … SET retention_days = CASE WHEN retention_days * 2 < low + high THEN low … ELSE longest END WHERE account_id = ? AND retention_days NOT IN (allowed)` (`Account::ProjectRetention.nearest_value`, an Arel `CASE`), however many apps there are. Self-hosted every choice is allowed, so only values outside 30/60/90 move. It runs with monitor fitting from `Account#fit_to_entitlements`: after a commit that changes `entitlement_values` and from `bin/rails goodsorcery:fit_entitlements`.

### 12.4 Scheduling (slice 2)

**Cron** (`config/schedule.yml`):
```yaml
schedule_uptime_checks:
  cron: "* * * * *"
  class: ScheduleUptimeChecksJob
  description: "Enqueue one uptime check per monitor that is due"
```

**Queue:** add `[uptime, 2]` to `config/sidekiq.yml`, placed after `alerts`. `UptimeCheckJob` runs on `uptime`. `ScheduleUptimeChecksJob` runs on `default`, so scheduling never waits behind slow checks. The uptime alert job runs on `alerts`. Checks are I/O-bound and take up to about 20 seconds in the worst case (two 10-second attempts). Capacity is roughly concurrency × 60 / average check seconds per minute. Operators can scale with a dedicated Sidekiq process for `uptime`; this goes in `docs/DEPLOYMENT.md` (slice 2).

**`UptimeSchedule`** (`app/models/uptime_schedule.rb`):
- `UptimeSchedule.enqueue_due(now: Time.current)` loops `#claim_batch` until it returns fewer than `BATCH` (500) ids. Each batch is enqueued with one `ActiveJob.perform_all_later(ids.map { UptimeCheckJob.new(_1) })`.
- `#claim_batch` is one statement, wrapped in `uncached { }` because of the jobs' query cache gotcha:
  ```sql
  UPDATE uptime_monitors
  SET next_check_at = date_trunc('minute', next_check_at) + make_interval(mins => interval_minutes * (1 + CAST(floor(
    extract(epoch FROM CAST(:now AS timestamp) - date_trunc('minute', next_check_at)) / 60 / interval_minutes) AS integer)))
  WHERE id IN (
    SELECT id FROM uptime_monitors
    WHERE paused_at IS NULL AND next_check_at <= CAST(:now AS timestamp)
    ORDER BY next_check_at
    LIMIT :batch
    FOR NO KEY UPDATE SKIP LOCKED)
  RETURNING id
  ```
  - Claiming by bumping `next_check_at` is the double-enqueue guard. An overlapping cron run sees the bumped rows as not due, and `SKIP LOCKED` keeps concurrent runs from waiting on each other.
  - `NO KEY UPDATE` avoids conflicts with the FK key-share locks taken by check inserts.
  - **Each monitor keeps its own schedule:** `next_check_at` steps forward from the monitor's own minute in whole intervals until it is past `now`. A late claim (backlog, restart, deploy, a fit resume) never moves monitors onto the current minute, so they stay spread across their interval instead of bunching up.
  - Aligning to the minute stops a 10-minute monitor drifting to 11 minutes when the next cron run fires a few milliseconds early.
  - The binds are cast (`CAST(:now AS timestamp)`); Postgres can't infer their types inside `extract` and `make_interval`.
  - It uses `index_uptime_monitors_due` and needs no per-monitor query.

**Stale-job guard:** `UptimeCheckJob` skips a monitor checked since the job was enqueued (`monitor.checked_since?(enqueued_at)`, Active Job's serialized `enqueued_at`; arguments stay ids only). Checks are recorded at the time they **started**, so the comparison holds however long the probe took. A backed-up queue holding several jobs for one monitor therefore probes it once, and `record_check` repeats the test under its row lock so a scheduled job and a "Check now" job running together keep one check.

### 12.5 The check (slice 2)

**`UptimeCheckJob`** (queue `uptime`) runs `perform(uptime_monitor_id)` and takes **an integer id only**.
1. `UptimeMonitor.find_by(id:)` with `includes(:project)`. It returns if the monitor is missing, paused, or `checked_since?(enqueued_at)`.
2. `started_at = Time.current`; `result = monitor.run_check`. This is network I/O outside any transaction.
3. `monitor.record_check(result, at: started_at, unless_checked_since: enqueued_at)` (below).
4. After commit: `monitor.alert_later(incident, kind)` when there was a transition (§12.9), and `monitor.broadcast_checked` (§12.8).

**`UptimeMonitor::Checking`** (concern):
- `#run_check` calls `UptimeProbe.new(url).check`. If the result is down and its `error_kind` isn't `blocked_address`, it probes **once more immediately** and keeps the second result. One check row is stored either way.
- `#record_check(result, at: Time.current, unless_checked_since: nil)` runs one transaction (`at` is when the check started):
  1. `lock("FOR NO KEY UPDATE")`, which reloads the monitor row and serialises the transition. It returns nil, recording nothing, when `checked_since?(unless_checked_since)`.
  2. `UptimeCheck.insert`.
  3. `UptimeHourlyCount.upsert` with `on_duplicate: Arel.sql("checks_count = … + 1, up_count = … + EXCLUDED.up_count, response_time_ms_sum = … + EXCLUDED.response_time_ms_sum")` and `record_timestamps: false`.
  4. The state transition (below).
  5. An update of the monitor's `status`, `last_checked_at`, `last_response_time_ms`, `last_http_status`, `last_error_kind` and `down_since`.

  It returns `[incident, kind]` or nil.
- `#check_soon` is the "Check now" gate (§12.8). It returns true when `Rails.cache.write(["uptime_check_now", id], 1, unless_exist: true, expires_in: check_now_gap)` succeeds and the monitor wasn't checked within `check_now_gap`. The caller then enqueues `UptimeCheckJob.perform_later(id)`. The cache holds an id only. It does not touch `next_check_at`.
- `#check_now_gap` is `RECHECK_GAP` (30 seconds) self-hosted, and hosted the longer of that and the account's shortest entitled interval (10 minutes for the hosted defaults). "Check now" therefore can't check more often than the entitlements allow.
- `#flap_grace` is three intervals, at most 30 minutes (below).

**State machine** (`UptimeMonitor::Checking#transition_for(result)`):

| from | result | to | side effect | alert kind |
|---|---|---|---|---|
| pending | up | up | — | — |
| pending / up | down | down | `down_since = at`; insert `UptimeIncident(started_at: at, error_kind, http_status)` | `monitor_down` |
| down | down | down | — (the incident stays open) | — |
| down | up | up | `down_since = nil`; set the open incident's `resolved_at = at` | `monitor_recovered` |
| up | up | up | — | — |

**Flapping:** going down within `flap_grace` of the last incident's recovery reopens that incident (`resolved_at = nil`) with no `monitor_down` alert, instead of opening a new one. Its recoveries still report `monitor_recovered`, but the per-incident delivery keys let only one recovered email through, so a flapping monitor sends one down and one recovered email rather than a pair per cycle (uptime alerts skip the hourly cap).

The unique partial index makes a second open incident impossible. A monitor whose status says up while an incident is open records down→down with no alert (checked first, with `ON CONFLICT DO NOTHING` on the insert as the backstop). Changing a monitor's URL or interval sets `next_check_at` to now and leaves the state alone.

**`UptimeProbe`** (`app/models/uptime_probe.rb`, PORO) is the HTTP client and SSRF guard. `#check` returns an `UptimeProbe::Result = Data.define(:status, :response_time_ms, :http_status, :error_kind)` with `#up?` and `#down?`. It never raises for network outcomes.

- **Request:** `GET`, with `User-Agent: GoodSorcery-Uptime/1.0`, `Accept: */*` and `Accept-Encoding: identity` (no decompression, no zip bombs). No cookies, no auth. There is no keep-alive: each hop is a new connection, closed afterwards.
- **Budget:** `UptimeProbe::TOTAL_TIMEOUT = 10` seconds per attempt, tracked by `UptimeProbe::Deadline` (`#remaining`, `#expired?`, monotonic clock). The DNS timeout (`Addrinfo.getaddrinfo(host, nil, nil, :STREAM, timeout: remaining)`) and `open_timeout`, `ssl_timeout`, `read_timeout` and `write_timeout` are all set to the remaining budget before each hop. The deadline is checked between hops and between body chunks. As a hard backstop, one attempt's network part (no DB, no locks) runs inside `Timeout.timeout(TOTAL_TIMEOUT + 1)`, because a trickling server could otherwise outlast the per-read timeouts.
- **Up:** the final response is 2xx or 3xx. **Down:** any other status (`error_kind: "http_status"`, with the code stored), or an error.
- **Redirects:** follow at most `MAX_REDIRECTS = 3` 3xx responses with a `Location`. Each hop is parsed by `UptimeUrl` (http/https only, no userinfo), resolved and vetted again, and connected through a new pinned connection. A redirect to a refused address ends the check as down with `blocked_address`. A 3xx whose `Location` is missing, unparseable or not http(s), or one past the limit, is itself the final response and counts as up.
- **Body:** read and discarded in chunks, at most `MAX_BODY_BYTES = 64.kilobytes`, then the connection is closed. Nothing from the body is kept.
- **Read cap:** Net::HTTP reads the status line, headers and 1xx responses with no limit of its own, so `UptimeProbe::Connection` (a `Net::HTTP` subclass) extends its socket in the `on_connect` hook with `ReadCap`, which counts every byte taken from the socket (`rbuf_fill`) and raises `UptimeProbe::ResponseTooLarge` (`connection_error`) past `MAX_READ_BYTES = 128.kilobytes` per connection. An endless header can't fill the worker's memory.
- **Pinning (no DNS rebinding):** `UptimeProbe::AddressGuard#vet(hostname)` resolves once and returns one vetted `IPAddr`. The connection is `UptimeProbe::Connection.new(hostname, port, nil)` with `http.ipaddr = vetted_ip.to_s`.
  - The third argument `nil` disables `http_proxy` from ENV, which would otherwise bypass the pin.
  - Net::HTTP still sends `Host: hostname` and uses it for SNI and certificate hostname verification (`verify_mode = VERIFY_PEER`, `verify_hostname = true`).
  - IP-literal hosts are vetted the same way.
- **Address rules** (`AddressGuard`): the host is refused when **any** resolved address is blocked, so mixed public and private answers are refused. No addresses means `dns_failure`. Blocked ranges:
  - IPv4: `0.0.0.0/8`, `10.0.0.0/8`, `100.64.0.0/10` (CGNAT, including Alibaba's `100.100.100.200` metadata), `127.0.0.0/8`, `169.254.0.0/16` (link-local, including `169.254.169.254` metadata), `172.16.0.0/12`, `192.0.0.0/24`, `192.0.2.0/24`, `192.88.99.0/24`, `192.168.0.0/16`, `198.18.0.0/15`, `198.51.100.0/24`, `203.0.113.0/24`, `224.0.0.0/4` (multicast), `240.0.0.0/4`, `255.255.255.255/32`.
  - IPv6: `::/128`, `::1/128`, `fc00::/7` (ULA, including `fd00:ec2::254` metadata), `fe80::/10`, `fec0::/10`, `ff00::/8`, `100::/64`, `2001:db8::/32`. Addresses that embed IPv4 are unwrapped and the IPv4 is checked against the list: `::ffff:0:0/96` (mapped), `64:ff9b::/96` (NAT64), `2002::/16` (6to4) and `::/96` (compatible).
  - Host names `localhost` and `*.localhost` are refused before resolving.
- **Escape hatch:** `AddressGuard.new(allow_private: Rails.configuration.x.uptime.allow_private_addresses)`. It is off by default and never on in production. Tests inject `allowed_ips: ["127.0.0.1"]`, which allows exactly the local test server while still blocking every other range, and `resolver:` (a lambda `host, timeout -> [IPAddr]`) for pinning tests. Tests never use the ENV variable.
- **Error kinds** (`UptimeCheck::ERROR_KINDS`, with labels in `UptimeCheck.error_label(kind, http_status)`, shared by UI and email):

  | kind | from | label |
  |---|---|---|
  | `timeout` | `Net::OpenTimeout`, `Net::ReadTimeout`, `Net::WriteTimeout`, `Deadline::Exceeded`, `Timeout::Error`, a DNS timeout | "Timed out after 10 s" |
  | `dns_failure` | `Socket::ResolutionError` / `SocketError` from getaddrinfo, no addresses | "DNS lookup failed" |
  | `connection_refused` | `Errno::ECONNREFUSED` | "Connection refused" |
  | `tls_error` | `OpenSSL::SSL::SSLError` (including certificate verification) | "TLS handshake failed" |
  | `http_status` | a final status outside 200..399 | "HTTP 503" |
  | `blocked_address` | `UptimeProbe::BlockedAddress` (first hop or redirect) | "Address not allowed" |
  | `connection_error` | `UptimeProbe::ResponseTooLarge`, `Errno::ECONNRESET`, `EHOSTUNREACH`, `ENETUNREACH`, `EPIPE`, `EOFError`, `IOError`, `Net::HTTPBadResponse`, `Net::ProtocolError`, any other `StandardError` | "Connection failed" |

  An unexpected `StandardError` is logged as `"Uptime check #{monitor_id} failed: #{error.class}"`, with the class name only and never the message, since messages carry host names and URLs.

**`UptimeUrl`** (`app/models/uptime_url.rb`) is used by validation and by redirects.
- `UptimeUrl.parse(string)` returns a normalised `URI`, or nil. It strips whitespace, removes the fragment, and requires an `http` or `https` scheme, a host and no userinfo. Length must be ≤ 2,048.
- `#public?` refuses `localhost` and IP literals in the blocked ranges, which gives an early, friendly validation error. The real guard is still the resolve-time check above.
- `UptimeMonitor#host` is `UptimeUrl.parse(url)&.host`. This is the only part of the URL shown outside the edit form and the detail page.

### 12.6 URL secrecy (every slice)

- `url` is encrypted at rest and decrypted only to probe, to fill the edit form and to show the detail page (ERB-escaped).
- Lists show the name and `host`. Emails show the name and `host`, never the path or query.
- It never appears in job arguments (ids only), Redis, `Rails.cache`, broadcasts (pointer `reload_frame` only, §12.8), logs, exception messages, validation messages, `alert_deliveries` or check rows.
- `config/initializers/filter_parameter_logging.rb` adds `:url` (slice 2), which matches `uptime_monitor[url]` in request logs.
- Net::HTTP debug output is never enabled.
- Tests: the fixture URL carries a secret query (`?token=uptime-fixture-secret`). Slice 2 asserts it is absent from job args and captured logs (a check, a failing check and a create request). Slice 4 asserts it is absent from email subject, parts and headers.

### 12.7 Models and queries (slice 2)

- **`UptimeMonitor`**:
  - `belongs_to :project, inverse_of: :uptime_monitors`; `has_many :checks (UptimeCheck), :hourly_counts, :incidents`; `encrypts :url`.
  - `enum :status` (`pending up down`).
  - `INTERVALS = Entitlements::UPTIME_INTERVALS`, and `INTERVAL_LABELS = { 1 => "Every minute", 5 => "Every 5 minutes", 10 => "Every 10 minutes", 60 => "Every hour" }`.
  - Scopes `active` (unpaused) and `due(now)`. Methods `#paused?`, `#checked_recently?(now, gap:)`, `#checked_since?(time)`, `#host`, `#interval_label`, `#open_incident`.
  - Includes `UptimeMonitor::Checking`, `UptimeMonitor::Broadcasting` (a stub, `def broadcast_checked = nil  # Implemented by slice 3`) and `UptimeMonitor::Alerting` (a stub, `def alert_later(incident, kind) = nil  # Implemented by slice 4`). Those two stub files are the only ones whose ownership transfers.
  - **Validations:**
    - `name` is 1..60 chars.
    - `url` is present and valid by `UptimeUrl` (`public?`), with the message "must be a public http:// or https:// address". The message never echoes the value.
    - `interval_minutes` is in `INTERVALS`.
    - `validate :interval_entitled` uses `project.account.entitlements.allows_uptime_interval?`, with the message "isn't available on this account". It runs on create, and on update only when `interval_minutes` changed, so fitting and other edits never trip it.
    - `validate :within_monitor_limit, on: :create` first runs `Account.where(id: project.account_id).lock("FOR NO KEY UPDATE").pick(:id)` (validations run inside `save`'s transaction, so concurrent creates serialise), then checks `entitlements.monitor_limit_reached?` against the uncached count of the same app's monitors (the limit is per app). The error goes on `:base`: "This app has reached its limit of N monitor(s).", or "Uptime monitors aren't included in this account." for a limit of 0, or "Cannot add more yet, but it's coming soon" without an upgrade URL (`UptimeMonitor.limit_message`).
- **`UptimeCheck`**: `enum :status` (`up down`), `ERROR_KINDS`, `.error_label`, `scope :recent`, `MAX_KEPT_DAYS = 7`.
- **`UptimeIncident`**: `scope :open`, `scope :recent`, `#open?`, `#duration` (to `resolved_at` or now), `#cause_label`, `KEPT_FOR = 31.days`.
- **`UptimeHourlyCount`** answers every one of these queries with a single grouped query, however many monitors there are:
  - `.uptime_percentages(monitor_ids, now:)` returns `{ id => { "24h" => Float|nil, "7d" => …, "30d" => … } }`. It uses `SUM(up_count) FILTER (WHERE hour >= …) / SUM(checks_count) FILTER (…)` in one query, and nil means no checks in that window.
  - `.hourly_bars(monitor_ids, hours: 24, now:)` returns `{ id => [[hour, checks, up], …] * 24 }`, zero-filled through `TimeSeries`.
  - `.daily_bars(monitor, days: 30, zone:)` uses the viewer's local days (`DATE((hour AT TIME ZONE 'UTC') AT TIME ZONE zone)`, as `IssueHourlyCount.series` does).
  - `.average_response_ms(monitor_ids, since:)` returns `{ id => Integer|nil }`.
- **`UptimeCheck.response_series(monitor, since: 24.hours.ago)`** returns 15-minute `date_bin` buckets of the average `response_time_ms` of up checks (≤ 96 points), for the detail sparkline.
- **`Account::UptimeMonitoring`** (concern; slice 2 adds the `include` line to `account.rb`): `has_many :uptime_monitors, through: :projects` (the per-app limit check is `entitlements.monitor_limit_reached?(project.uptime_monitors.count)`), `#fit_uptime_monitors_to_entitlements` (§12.3.1), run by `Account#fit_to_entitlements` from the `after_update_commit` on an `entitlement_values` change.
- **`Project`**: `has_many :uptime_monitors, inverse_of: :project`.

### 12.8 Web (slice 3)

**Routes** (inside `resources :projects … scope module: :projects`):
```ruby
resources :uptime_monitors, path: "uptime" do      # index new create show edit update destroy
  scope module: :uptime_monitors do
    resource :check, only: :create                  # "Check now"
    resource :row, only: :show                      # live frame on the list
    resource :report, only: :show                   # live frame on the detail page
  end
end
```
URLs look like `/projects/storefront/uptime` and `/projects/storefront/uptime/12`. Helpers are `project_uptime_monitors_path`, `project_uptime_monitor_path`, `new_/edit_project_uptime_monitor_path`, `project_uptime_monitor_check_path`, `project_uptime_monitor_row_path` and `project_uptime_monitor_report_path`.

**Controllers:**

| Controller | Actions | Notes |
|---|---|---|
| `Projects::UptimeMonitorsController` | index, new, create, show, edit, update, destroy | `include ProjectScoped, VerifiedEmailRequired`, with `require_verified_email only: %i[new create]` (a monitor makes outbound requests, like creating apps and keys). `@uptime_monitor = @project.uptime_monitors.find(params[:id])`. Strong params are `params.expect(uptime_monitor: %i[name url interval_minutes])`. create/update redirect to show with a notice, and 422 re-renders the form. destroy uses `button_to … method: :delete, data: { turbo_confirm: "Delete <name>? Its check history goes too." }` and redirects to index |
| `Projects::UptimeMonitors::ChecksController` | create | `rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, name: "uptime_check_now", store: Ingest::RateLimitStore`. Then `@uptime_monitor.check_soon`: if true, it enqueues `UptimeCheckJob` and redirects back with "Checking <name> now…". Otherwise it redirects back with "Checked less than <check_now_gap> ago." ("30 seconds" self-hosted, "10 minutes" for the hosted defaults). A paused monitor is refused |
| `Projects::UptimeMonitors::RowsController` | show | frame `dom_id(monitor, :row)` |
| `Projects::UptimeMonitors::ReportsController` | show | frame `dom_id(monitor, :report)` |

The `UptimeMonitorScoped` concern includes `ProjectScoped` and sets `@uptime_monitor = @project.uptime_monitors.find(params[:uptime_monitor_id])`. A monitor of another app or account is a 404. Every page keeps `Cache-Control: no-store` (inherited). The edit and detail pages, which show the URL, add `<meta name="turbo-cache-control" content="no-cache">`.

**Live updates:**
- `UptimeMonitor::Broadcasting#broadcast_checked` replaces slice 2's stub. It sends `reload_frame` on stream `[project, :uptime]` for `dom_id(monitor, :row)` (src the row path) and `dom_id(monitor, :report)` (src the report path), through `LiveFrames` paths.
- These are pointers only, and `AuthorizedStreamsChannel` already accepts `Project` streams.
- The index and show pages place `live_stream_from @project, :uptime`.
- There is at most one broadcast per check, so no debounce is needed.

**Presentation objects:**
- `UptimeOverview.new(monitors, now:)#rows` costs a fixed 3 queries for the list: monitors, `uptime_percentages` and `hourly_bars`. When hosted, the app's monitor count (one query, `@monitor_count`) feeds the limit chip and `@monitor_limit_reached`.
- `UptimeReport.new(monitor, zone:)` serves the detail page with `#percentages`, `#daily_bars`, `#average_response_ms`, `#response_series`, `#recent_checks` (20), `#incidents` (`incidents.recent.limit(10)` within `KEPT_FOR`) and `#open_incident`.

**Screens** follow the flat pastel theme with existing tokens and component classes (`.panel`, `.chip-*`, `.btn*`, `.segmented`, `.toggle`), server-rendered SVG, no inline styles or scripts, and no new JS beyond the existing Stimulus controllers.
- **Sidebar:**
  - Uptime becomes a real `nav_link_to "Uptime", project_uptime_monitors_path(project), key: "uptime", icon: :uptime`, placed in "Grimoire" between Issues and Alerts.
  - With no project it is `nav_placeholder "Uptime"` with no "soon" note.
  - The "Coming from the suite" label and placeholder are removed.
  - When any unpaused monitor of the sidebar project is down, a coral dot badge shows, titled "N down". The count is a correlated subquery (`NavigationHelper::DOWN_MONITORS_SQL`) in the app switcher's existing projects query, so it costs no extra query; `#sidebar_down_monitors_count` falls back to one count when the project isn't in the switcher list.
- **Uptime index:**
  - Header: eyebrow "<app> · uptime", then "Uptime — N monitors", then an "Add a monitor" `btn-primary`.
  - When hosted and the limit is reached, the button (here and in the empty state) is replaced by a muted chip with the app's real usage, "2 of 1 monitor used", plus `upgrade_to_unlock` (`_add_button`). With a limit of 0 there is no chip, only the link. Without an upgrade URL it is replaced by the greyed-out "Cannot add more yet, but it's coming soon" (`coming_soon_notice`) and no chip.
  - The table is a `div` grid like the issue rows, with the name link stretched over the row. Columns:
    - a status chip: "Up" mint, "Down" coral with dot plus "for 12 min" (`down_since`), "Pending" muted, "Paused" muted;
    - name with `host` in small mono below;
    - `interval_label`;
    - last check (`time_ago_compact`);
    - last response time ("212 ms");
    - uptime 24h/7d/30d ("99.93%", "—" for no data);
    - a 24-segment hourly status bar.
  - A paused row (and the detail hero) adds `uptime_paused_note`: "Over this app's monitor limit. Upgrade to unlock" when hosted (without an upgrade URL just the first sentence), and how to resume with the fit task when self-hosted (§12.3.1).
- **Status bar:** `UptimeHelper#uptime_bar_svg(buckets, height: 22)` is pure SVG built with `tag`, like `ChartHelper`. Each segment has a `<title>` such as "Oct 3, 14:00 · 98.3% up · 60 checks". Colours come from `ChartHelper` constants:
  - no checks: `PAPER` at 0.45 opacity;
  - all up: `MINT`;
  - some down with ≥ 50% up: `CORAL` at 0.55;
  - < 50% up: `CORAL`.
- **Empty state** (`shared/_empty_state`):
  - Title "Watch your app from the outside".
  - Body "Uptime requests a URL of yours every few minutes, from outside your servers, and emails you when it stops answering and again when it's back."
  - Action "Add a monitor", or, when hosted and the limit is reached (a limit of 0), the same chip and `upgrade_to_unlock` as the header.
- **Detail** (`show`; the hero, ribbon, bars and recent checks sit inside the `dom_id(monitor, :report)` frame):
  - Hero: status chip, name in `font-display`, the full URL in mono (escaped), `interval_label`, and the buttons Check now (`btn-sm`), Edit and Delete.
  - Ribbon: Uptime 24h / 7d / 30d, Avg response 24h, Last check (`clock_label` · ago), and then by state "Paused since", "Status: Not checked yet" (pending), "Down since" or "Up since" (the last incident's `resolved_at`, or the first check).
  - A 30-day daily status bar (`daily_bars`, the viewer's days).
  - A 24h response-time `sparkline_svg(fluid: true)` in IRIS.
  - Incidents: started, resolved or "ongoing" (a coral dot), duration and `cause_label`. Empty, it says "No incidents. It has answered every check." only when there are checks, and "No incidents yet." otherwise.
  - Recent checks: time, status, ms, HTTP code and error label.
- **Form** (`_form`, used by new and edit):
  - Name, optional; the hint says it is filled from the host.
  - URL: `url_field`, `autocomplete: "off"`, placeholder `https://example.com/up`. The hint says "Kept encrypted. Lists and emails show only the host."
  - Check interval (the label matches the error messages' "Check interval"): a `select` of `INTERVALS` with `INTERVAL_LABELS`, default `entitlements.default_uptime_interval`. Locked intervals are `disabled` options labelled and titled with `locked_note`: "Every minute · Upgrade to unlock", or "Every minute · Coming soon" without an upgrade URL. Native select popups don't show option titles in most browsers, so the label suffix is what carries the note there. Below the select, a hint (`uptime_locked_intervals_hint_tag` around `uptime_locked_intervals_hint`: "Some intervals aren't available on this account." with `upgrade_to_unlock`, or "Some intervals are coming soon." titled "Coming soon" for the hover tooltip; `#uptime_monitor_interval_hint`, the select's `aria-describedby`) renders when any interval is locked. This only happens when hosted.
  - Errors are whole sentences in coral, with `aria-invalid`, like Settings › Alerts.
  - `new`, when the limit is reached, renders a panel "This app has reached its limit of N monitor(s)." ("Each app in <account> can have N monitor(s).") with `upgrade_to_unlock` instead of the form, or "Cannot add more yet, but it's coming soon" without an upgrade URL (`UptimeMonitor.limit_message`, also the validation error). `create` is still rejected by validation.

### 12.9 Alerts (slice 4)

**Rules.**
- `AlertRule::DEFAULTS` gains `"monitor_down" => { enabled: true }` and `"monitor_recovered" => { enabled: true }`.
- New constants: `AlertRule::UPTIME_KINDS = %w[monitor_down monitor_recovered]` and `AlertRule::ERROR_KINDS = KINDS - UPTIME_KINDS`.
- `INSTANT_KINDS` becomes `ERROR_KINDS - %w[daily_digest]`. Its meaning is unchanged: error alerts covered by the "Email alerts" switch and counted by the cap.
- `#uptime?` is added.
- `Project::Alerting#alert_rules_in_order(kinds = AlertRule::ERROR_KINDS)`.
- `AlertsHelper::RULE_COPY` gains:
  - `"monitor_down" => ["Monitor down", "A monitor fails its check, after one immediate retry."]`;
  - `"monitor_recovered" => ["Monitor recovered", "A monitor that was down passes its check again."]`.
- The environment scope (`alert_scope`) doesn't apply to uptime rules.

**Delivery.**
- `UptimeMonitor::Alerting#alert_later(incident, kind)` (replacing the stub) runs `UptimeAlertJob.perform_later(incident.id, kind)`.
- `UptimeAlertJob` runs on queue `alerts` and takes `perform(uptime_incident_id, kind)`. It discards a missing incident (the monitor was deleted).
- `UptimeAlert` (`app/models/uptime_alert.rb`) provides `UptimeAlert.new(incident, kind).deliver`, which returns the users mailed. `#due?` requires:
  - the app's rule for the kind is on;
  - for `monitor_down`, the incident is still open;
  - for `monitor_recovered`, it is resolved.
- Recipients are `project.uptime_alert_recipients`: verified members who haven't muted uptime alerts for that app (`Membership.receiving_uptime_alerts_for(project)`).
  - For `monitor_recovered`, only those who were sent this incident's down email are included: `AlertDelivery.where(dedupe_key: incident_key("monitor_down", incident), status: "sent").select(:user_id)`. Nobody gets a "recovered" email without the matching "down" one, except when the app's `monitor_down` rule is off: then no down email could go out, and recovered goes to every recipient.
- Per recipient: `AlertDelivery.record(user:, project:, kind:, dedupe_key: AlertDelivery.incident_key(kind, incident))`. This uses **`record`, never `claim`**, so the row is always `"sent"`, never `"folded"`, and never part of `AlertSummary`. When it inserted, `AlertsMailer.public_send(kind, user, incident).deliver_later` follows.
- **Dedupe keys:** `AlertDelivery.incident_key(kind, incident)` gives `"monitor_down:<incident_id>"` and `"monitor_recovered:<incident_id>"`, so there is one email of each kind per incident per user. `issue_id` is nil on these rows.
- **Cap exemption:** `AlertDelivery.sent_in_last_hour` keeps counting `AlertRule::INSTANT_KINDS` only, which no longer includes uptime kinds. Tests check two things: a user at the cap still gets `monitor_down`, and uptime rows don't move the count.

**Switches and mute links.**
- `NotificationPreference::STREAMS = %w[alerts uptime digest]`, with `STOPPED["uptime"] = { uptime_alerts_muted: true }` and `#receives?("uptime")`.
- `Membership#receives_uptime_alerts?(project)`.
- `AlertMute` accepts the stream `uptime`, and `alert_mute_subject` says "uptime alerts".
- The Notifications page gains a third switch column, "Uptime alerts" (`NOTIFICATION_ROW_GRID` becomes `minmax(0,1fr)_96px_96px_96px`), and still has a fixed query count.
- Settings › Alerts gains an "Uptime" panel below Rules, with the two uptime rules using the same `_rule` partial. Its intro says that the environment scope doesn't apply and that alerts are sent once per incident.

**`AlertsMailer`** (with `MailerHelper` blocks, `mail_in_zone` and `allow_unsubscribe(project, "uptime")`):
- `monitor_down(user, incident)`:
  - Subject: `"Down: <monitor name> in <app>"`.
  - Body: heading "<name> is down", the text "Good Sorcery couldn't reach <host>, even after an immediate retry.", then `email_details` (App, Monitor, Host, Cause `cause_label`, Since in the recipient's zone, Checks `interval_label`), an "Open monitor" button to `project_uptime_monitor_url` and `email_link_fallback`.
  - Send-time checks: the incident is still open, and the membership `receives_uptime_alerts?`.
- `monitor_recovered(user, incident)`:
  - Subject: `"Recovered: <monitor name> in <app> after 14 min"`.
  - Body: heading "<name> is back up", then details (Down for, From–To, Cause), a button and a fallback.
  - Send-time checks: the incident is resolved, and the membership `receives_uptime_alerts?`.
- **Content rule:** the monitor name, app name, host, labels, numbers, times and links only. Never the URL's path or query. HTML is escaped, and text parts use `raw` as the email template rule says.
- Previews go in `test/mailers/previews/alerts_mailer_preview.rb`.

### 12.10 Authorization

- Same as Settings › General and Settings › Alerts (§6): any member of the account may list, create, edit, delete and "Check now" monitors. There is no role gate. Creating also requires a verified email.
- All lookups go `Current.account.projects.find_by!(slug:)` → `@project.uptime_monitors.find(id)`.
- **Tests on every new action** (index, new, create, show, edit, update, destroy, check, row, report):
  - `users(:outsider)` gets 404 for acme's app and monitor URLs;
  - a monitor of `billing` under the `storefront` slug is a 404;
  - signed-out requests redirect to sign-in;
  - hosted mode rejects a disallowed `interval_minutes` and an over-limit create with 422, from crafted POST/PATCH bodies.

### 12.11 Retention

`Ingest::Retention#prune` gains `prune_uptime` (slice 2):
- **Checks:** per retention group (`each_retention_cutoff`), delete `UptimeCheck`s older than `[project.retention_days, UptimeCheck::MAX_KEPT_DAYS].min` days. The query is `where(uptime_monitor_id: UptimeMonitor.where(project_id: ids).select(:id), checked_at: ...cutoff).in_batches(of: BATCH).delete_all` on `[uptime_monitor_id, checked_at]`. Raw rows are capped at 7 days: they feed only the 24h sparkline and the recent list, and the percentages and bars use rollups. A 1-minute monitor would otherwise keep 43k raw rows.
- **Rollups:** `prune_hour_slices(UptimeHourlyCount, rollup_cutoff(UPTIME_ROLLUP_DAYS))`, where `UPTIME_ROLLUP_DAYS = UptimeReport::DAYS + 1` (31). That covers the 30-day uptime and local-day bars.
- **Incidents:** resolved before `UptimeIncident::KEPT_FOR` (31 days) are deleted. Open incidents are kept.
- Delivery rows for uptime alerts are pruned with `alert_deliveries` (30 days), **except** the `monitor_down` rows of incidents still open, which pick who gets the recovered email however long the outage lasts. Incident ids are never reused, so keys stay unique.

### 12.12 Build slices and file ownership

Never edit a file you don't own; report the need instead. Use your own test database (`TEST_DB_SUFFIX=_<slice>`). Run the full §9/§10 checklists, `bin/rubocop` and `bin/brakeman` before committing. Commit in logical steps on `main` with the trailer.

**Slice 1: entitlements groundwork** (`_entitlements`)
- `config/application.rb` (the `config.x` lines in §12.2), `config/entitlements.yml`, `config/deploy.yml` (pass `GOODSORCERY_HOSTED` and `GOODSORCERY_UPGRADE_URL` through when set, as `GOODSORCERY_ENABLE_SIGNUPS` is), `README.md` (env vars: `GOODSORCERY_HOSTED`, `GOODSORCERY_UPGRADE_URL`, `GOODSORCERY_UPTIME_ALLOW_PRIVATE_ADDRESSES`)
- `db/migrate/*_add_entitlement_values_to_accounts.rb`, `db/schema.rb`
- `app/models/entitlements.rb`, `app/models/account.rb` (`#entitlements`, validation, `#update_entitlements!`)
- `app/helpers/application_helper.rb` (`hosted?` from config), `app/helpers/entitlements_helper.rb`
- `test/test_helper.rb` (`with_hosted_mode`), `test/fixtures/accounts.yml`, `test/models/entitlements_test.rb`, `test/models/account_test.rb`, `test/helpers/entitlements_helper_test.rb`, `test/helpers/application_helper_test.rb` and `test/controllers/projects/setups_controller_test.rb` (switch from ENV to `with_hosted_mode`)
- Required tests:
  - self-hosted ignores stored values and is unlimited;
  - hosted falls back per key to the defaults;
  - stored values win, including `max_monitors: null`;
  - invalid values are rejected by `Account` and ignored by the reader;
  - `default_uptime_interval` and `nearest_uptime_interval` edge cases;
  - the upgrade link with and without a URL;
  - a grep-style test that no app/config file contains "free" or "premium" as a tier word (optional but welcome).

**Slice 2: uptime models, checker, scheduling and retention** (`_uptime`)
- `db/migrate/*_create_uptime_monitors.rb` (all four uptime tables, constraints and indexes), `db/schema.rb`, `db/seeds.rb` (demo monitors on `.example` hosts with history rows written directly: no network)
- `app/models/uptime_monitor.rb`, `uptime_monitor/checking.rb`, `uptime_monitor/broadcasting.rb` (stub → slice 3), `uptime_monitor/alerting.rb` (stub → slice 4), `uptime_check.rb`, `uptime_hourly_count.rb`, `uptime_incident.rb`, `uptime_probe.rb`, `uptime_probe/address_guard.rb`, `uptime_probe/deadline.rb`, `uptime_url.rb`, `uptime_schedule.rb`, `account/uptime_monitoring.rb`; the one-line `include` in `account.rb` and the `has_many :uptime_monitors` in `project.rb`
- `app/jobs/schedule_uptime_checks_job.rb`, `app/jobs/uptime_check_job.rb`
- `app/models/ingest/retention.rb` (`prune_uptime`), `lib/tasks/goodsorcery.rake` (`goodsorcery:fit_uptime_monitors`, now an alias of `goodsorcery:fit_entitlements`)
- `config/schedule.yml`, `config/sidekiq.yml`, `config/initializers/filter_parameter_logging.rb` (`:url`), `docs/DEPLOYMENT.md` (the uptime queue and scaling note)
- `test/fixtures/{uptime_monitors,uptime_checks,uptime_hourly_counts,uptime_incidents}.yml`. Fixtures:
  - `storefront_home` (up, 10 min, URL `https://storefront.example/up?token=uptime-fixture-secret`);
  - `storefront_api` (down, with the open incident `storefront_api_outage`);
  - `billing_checkout` (pending);
  - `umbrella_site` (umbrella_app);
  - plus one resolved incident and 24h of rollups.
- `test/models/uptime_*_test.rb`, `test/models/account/uptime_monitoring_test.rb`, `test/jobs/{schedule_uptime_checks,uptime_check}_job_test.rb`, and the `Ingest::Retention` test additions
- Required tests:
  - every blocked range, including mapped, NAT64, 6to4 and metadata, plus `localhost`, plus "any address blocked refuses";
  - the pinned connection sends the original `Host` and SNI (injected resolver plus a local `TCPServer`);
  - a redirect to a private address gives `blocked_address`, and redirects past the limit stop;
  - the 10-second budget, with an injected short timeout against a silent server;
  - the body cap;
  - error-kind mapping;
  - retry once, and no retry for `blocked_address`;
  - every state-machine row and the one-open-incident index;
  - the scheduler claim: a second claim gets nothing, batches go through `perform_all_later`, and the query count is fixed regardless of the number of monitors;
  - the stale-job guard (a backed-up queue probes once) and late claims keeping each monitor's schedule;
  - the read cap against endless headers;
  - validations, including hosted entitlements and the concurrent-create limit;
  - fitting on downgrade, upgrade and destroy;
  - the raw `url` column is ciphertext;
  - the secret query is absent from job args and logs;
  - retention.

**Slice 3: uptime UI** (`_uptime_ui`)
- `config/routes.rb` (the §12.8 block)
- `app/controllers/projects/uptime_monitors_controller.rb`, `app/controllers/projects/uptime_monitors/{checks,rows,reports}_controller.rb`, `app/controllers/concerns/uptime_monitor_scoped.rb`
- `app/models/uptime_overview.rb`, `app/models/uptime_report.rb`, `app/models/uptime_monitor/broadcasting.rb` (replacing the stub), `app/models/live_frames.rb` (uptime paths)
- `app/views/projects/uptime_monitors/**` (index, show, new, edit, `_form`, `_row`, `_report`, `_hero`, `_ribbon`, `_incidents`, `_recent_checks`, `_add_button`, `_limit_reached`, `rows/show`, `reports/show`), `app/views/layouts/_sidebar.html.erb`
- `app/helpers/uptime_helper.rb` (`uptime_bar_svg`, the `uptime_status_chip` helper, `uptime_paused_note`, percentage and ms formatting), `app/helpers/navigation_helper.rb` (the sidebar down badge: `DOWN_MONITORS_SQL` in the switcher query)
- `test/controllers/projects/uptime_monitors_controller_test.rb`, `test/controllers/projects/uptime_monitors/**`, `test/models/{uptime_overview,uptime_report}_test.rb`, `test/models/uptime_monitor/broadcasting_test.rb`, `test/helpers/uptime_helper_test.rb`, `test/integration/shell_test.rb` (the sidebar Uptime link)
- Required tests:
  - §12.10 authorization on every action;
  - the hosted locked options and limit message, and that self-hosted shows neither;
  - the upgrade link;
  - `no-store`;
  - the Check now rate limit and its gate (30 seconds, or the shortest entitled interval when hosted);
  - a fixed index query count with 1 vs. 5 monitors;
  - broadcasts carry no URL;
  - the empty state.

**Slice 4: down and recovered alerts** (`_uptime_alerts`)
- `db/migrate/*_add_uptime_alerts.rb` (`notification_preferences.uptime_alerts_muted` plus the alert rule backfill), `db/schema.rb`
- `app/models/alert_rule.rb`, `alert_delivery.rb` (`incident_key`), `notification_preference.rb`, `membership.rb`, `alert_mute.rb`, `project/alerting.rb` (`uptime_alert_recipients`, `alert_rules_in_order(kinds)`), `uptime_alert.rb`, `uptime_monitor/alerting.rb` (replacing the stub)
- `app/jobs/uptime_alert_job.rb`
- `app/mailers/alerts_mailer.rb`, `app/views/alerts_mailer/monitor_down.{html,text}.erb`, `monitor_recovered.{html,text}.erb`, `app/helpers/alert_emails_helper.rb`, `app/helpers/alerts_helper.rb`
- `app/views/projects/alerts/show.html.erb` (the Uptime panel), `app/views/notifications/**`, `app/views/alert_mutes/**`
- `test/fixtures/alert_rules.yml` (follows `DEFAULTS` automatically; check it), `test/fixtures/notification_preferences.yml`, `test/models/{alert_rule,alert_delivery,notification_preference,membership,alert_mute,uptime_alert}_test.rb`, `test/models/project/alerting_test.rb`, `test/jobs/uptime_alert_job_test.rb`, `test/mailers/alerts_mailer_test.rb`, `test/mailers/previews/alerts_mailer_preview.rb`, `test/controllers/{notifications,alert_mutes}_controller_test.rb`, `test/controllers/projects/{alerts,alert_rules,notification_preferences}_controller_test.rb`
- Required tests:
  - one email per incident per kind per user (a repeated job sends nothing);
  - a recovered email only to users who got the matching down email;
  - the rule off sends nothing;
  - uptime muted sends nothing, while error alerts still flow, and the reverse;
  - unverified users are never mailed;
  - the cap exemption (above), and never folded or summarised;
  - the List-Unsubscribe uptime stream and its mute page;
  - the fixture URL's path and query are absent from the email;
  - the backfill migration is idempotent.

**Integration (lead, after the slices):** update `CLAUDE.md` ("Current state", "Not built yet", the gotchas for `UptimeMonitor` naming, URL secrecy and the claim SQL casts), then run the full test, system, lint, Brakeman and audit pass.

---

## 13. Performance (APM) (approved 2026-11-04)

This section is the binding blueprint for the performance-monitoring build. The approved UI is a canvas of three screens (overview, endpoint detail, slow request trace); the build matches its layout, copy and states with the existing Tailwind tokens, component classes and server-rendered SVG helpers (§7). Everything in §0 (ground rules), §6 (authorization) and the §9/§10 checklists applies. **Traces are captured data** (§0.4): they hold normalised SQL, request paths, host names and code context, so they are encrypted at rest and never leave Postgres except to render the trace page. The client side (the `goodsorcery` gem) is specified in `goodsorcery-ruby/docs/DESIGN.md` §8; the wire format is in `docs/INGEST_API.md` › Performance monitoring.

### 13.0 Decisions (binding)

- **Scope.** A simple APM for Rails apps: metrics from every web request and background job, and full timelines (traces) for a few slow requests only. Not built: logs, distributed tracing, a custom instrumentation API, latency alerts, live updates on the APM pages (they are static: no Action Cable, no broadcasts).
- **Transactions.** Web: `Controller#action`, plus the HTTP verb and route pattern (`POST /checkout`). Jobs: the job class, plus adapter, queue and queue wait (job start − `enqueued_at`; for a job scheduled with `wait:`/`wait_until:` the gem measures from `scheduled_at`, so a deliberate delay is not counted as waiting). Each app keeps at most `Apm::MAX_TRANSACTIONS` (500) distinct names **per environment and kind**; further names are folded into the transaction `(other)`.
- **Metrics** are aggregated in the gem per transaction per minute and flushed once a minute per process. The server merges them **by addition** (upsert), so any number of processes, retries of other batches and late minutes combine correctly. Percentiles come from the merged histogram; Average comes from `duration_ms_sum / requests_count`.
- **Response-time statistics everywhere are Average, p75, p90, p95 and p99. p50 is not shown anywhere**: the overview KPI tiles, the endpoint stat ribbon and the endpoint response-time chart use all five; the overview endpoint table shows **p75 / p90 / p95 / p99** (changed from the canvas's p50 / p95 / p99 on 2026-11-07).
- **Traces.** The gem records a timeline for every transaction cheaply and keeps only the slowest per transaction per minute per process (no duration floor). The server keeps at most one trace per transaction per minute while its hour is open (a slower one replaces it) and trims each closed hour to the 3 slowest per transaction. Trace ids are UUIDv7.
- **Quota and limits.** APM data never counts toward the monthly event quota and is accepted when an account is over it. It has its own rate limits (§13.3).
- **Retention.** A new entitlement `apm_retention_days` (hosted default **1**). Self-hosted: `GOODSORCERY_APM_RETENTION_DAYS` (default **30**, 1..30). Per-minute rows are kept 2 days whatever the retention. Downgrades apply at query time and at the next prune.
- **"Slower"** replaces any "vs previous day" comparison: a transaction is Slower when its last-hour p95 is ≥ 1.5× its p95 over the past 24 hours, with minimum request counts (§13.6).
- **Opt-in.** Performance monitoring is off by default in the gem (`config.performance_monitoring = true` turns it on). The server needs no switch: an app shows data as soon as its gem sends some.
- **Naming.** Models use the `Apm` prefix (`ApmTransaction`, `Apm::Distribution`); controllers and views say "performance" (`Projects::Performance::…`). Never name a model `Performance`, `Transaction` or `Trace` at the top level: `Transaction` reads as a database transaction next to `ActiveRecord::Base.transaction`, and the prefix keeps every APM table and class easy to find.

### 13.1 Histogram (shared with the gem; never change without a new scheme)

Scheme name: **`gs-v1`**. Both repos hold the same literal list and a test asserting it element by element (`Apm::Histogram::BOUNDS_MS` here, `GoodSorcery::Performance::Histogram::BOUNDS_MS` in the gem).

```ruby
# Upper bounds in milliseconds of buckets 0..29; bucket 30 is open-ended.
BOUNDS_MS = [
  1, 1.5, 2, 3, 4.5, 6.5, 9.5, 14, 20, 28,
  40, 60, 85, 125, 180, 260, 380, 550, 800, 1_150,
  1_700, 2_450, 3_550, 5_100, 7_500, 11_000, 16_000, 23_000, 33_000, 48_000
].freeze
BUCKETS = 31
SCHEME = "gs-v1"
```

- Bucket `i` holds durations `d` with `BOUNDS_MS[i-1] <= d < BOUNDS_MS[i]` (lower bound 0 for bucket 0, no upper bound for bucket 30). `Histogram.index(ms)` = the number of bounds `<= ms` (`BOUNDS_MS.bsearch_index { _1 > ms } || 30`), so 0.4 ms → 0, exactly 1 ms → 1, 250 ms → 15, 60 s → 30.
- Edges step by ×1.33–×1.5 (about ×1.45, a log scale), so every value in a bucket is within about ±20% of the bucket's geometric centre. That is the "about 30 buckets, each ~20% wide" of the approved spec: ~20% is the precision of a reported percentile; a literal 20%-wide edge step would need ~60 buckets to cover 1 ms–48 s.
- Queue wait uses the same buckets (counts only).

### 13.2 Schema

```
Project ──< ApmTransaction (per environment + kind + name; plus one "total" row per environment + kind)
               ├─< ApmMinuteStat  (per transaction per minute; kept 2 days)
               ├─< ApmHourlyStat  (per transaction per hour; kept for the retention)
               └─< ApmTrace       (encrypted timeline; ≤ 1 per minute, ≤ 3 per closed hour)
Project ──< ApmInboundBatch (encrypted raw body until processed; dedupe by batch id)
```

All ids are `bigint`; FKs are real constraints with `on_delete: :cascade`; models declare `has_many … inverse_of:` without `dependent:`, as `Project` does. One migration, `create_apm_tables`, creates all five tables.

**apm_transactions**
| column | type | null | default | notes |
|---|---|---|---|---|
| project_id | references → projects, cascade | false | | |
| environment | string | false | | from the API key that sent the data |
| kind | string | false | | `web` or `job` (check constraint) |
| name | string(255) | false | | **plaintext**, like `issues.transaction_name`: `CheckoutsController#create`, `Orders::PlaceJob`, `(other)`, or the total row's fixed name |
| total | boolean | false | false | the app-wide row for its environment and kind: `"All web requests"` / `"All background jobs"` (`ApmTransaction::TOTAL_NAMES`). Never listed, never counted toward the cap |
| http_method | string(16) | true | | web: `POST` |
| route | string(255) | true | | web: the route pattern `/products/:slug` (never a real path) |
| adapter | string(32) | true | | jobs: `sidekiq`, `async`, `good_job`… |
| queue | string(128) | true | | jobs |
| source_file | string(500) | true | | app-relative path of the controller or job class, normalised by `Ingest::PathNormalizer` (a code location, plaintext like `culprit`) |
| first_seen_at | datetime | false | | |
| last_seen_at | datetime | false | | bumped at most hourly (§13.4) |
| timestamps | | | | |

Indexes: unique `[project_id, environment, kind, name]` (the registry key), `[project_id, environment, kind, last_seen_at]` (lists, env picker), `[last_seen_at]` (prune). `http_method`, `route`, `adapter`, `queue` and `source_file` keep the latest value sent (updated with `last_seen_at`). Model API: scopes `listed` (`total: false`), `web`, `jobs`, `for_environment(env)`, `matching(q)`; `#web?`, `#job?`, `#route_label` ("POST /checkout"); `MAX_TRANSACTIONS = 500`, `OTHER_NAME = "(other)"`, `TOTAL_NAMES`.

**apm_minute_stats** (`create_table …, primary_key: [:apm_transaction_id, :minute]`) and **apm_hourly_stats** (`primary_key: [:apm_transaction_id, :hour]`) have identical columns apart from the time column:
| column | type | null | default | notes |
|---|---|---|---|---|
| apm_transaction_id | bigint FK → apm_transactions, cascade | false | | |
| minute / hour | datetime | false | | UTC minute / hour start |
| requests_count | bigint | false | 0 | |
| failed_count | bigint | false | 0 | web: status ≥ 500 or raised; job: raised |
| duration_ms_sum | double precision | false | 0 | Average = sum / count |
| bucket_counts | bigint[] | false | 31 zeros | requests per §13.1 bucket |
| bucket_db_ms | double precision[] | false | 31 zeros | summed database time of the requests in each bucket |
| bucket_http_ms | double precision[] | false | 31 zeros | external HTTP |
| bucket_view_ms | double precision[] | false | 31 zeros | views |
| bucket_ruby_ms | double precision[] | false | 31 zeros | Ruby (per request: total − the others, floored at 0) |
| queue_wait_counts | bigint[] | false | 31 zeros | jobs only (zeros for web) |
| queue_wait_ms_sum | double precision | false | 0 | jobs only |

Check constraints: `cardinality(<each array>) = 31`. Extra index: `[minute]` / `[hour]` for pruning by time slice, like the other rollups. Arrays are always dense (31 entries); the payload's sparse buckets are densified before the upsert.

**apm_traces**
| column | type | null | default | notes |
|---|---|---|---|---|
| project_id | references → projects, cascade | false | | lookup by uuid, retention |
| apm_transaction_id | references → apm_transactions, cascade | false | | |
| uuid | uuid | false | | UUIDv7 from the gem (or generated); the URL id |
| minute | datetime | false | | the minute the request finished (the metrics minute) |
| hour | datetime | false | | `minute` truncated to the hour |
| started_at | datetime(6) | false | | |
| duration_ms, db_ms, http_ms, view_ms, ruby_ms | double precision | false | 0 | layer totals (list columns, layer bar) |
| sql_count, http_count, n_plus_one_count | integer | false | 0 | |
| status | integer | true | | HTTP status (web); nil for jobs |
| failed | boolean | false | false | |
| error_event_uuid | uuid | true | | the error event reported by this request; links to its issue through `occurrences.uuid` |
| payload | text | false | | **encrypted** JSON (§13.5): request/job details, host, process, runtime, GC, allocations, spans with normalised SQL, HTTP host/path, templates, call sites and code context |
| created_at | datetime | false | | |

Indexes: unique `[project_id, uuid]`, unique `[apm_transaction_id, minute]` (one trace per transaction per minute, the replacement upsert's conflict target; still true after the hourly trim), `[apm_transaction_id, started_at]` (Newest sort, older/newer navigation), `[hour]` (trim and prune).

**apm_inbound_batches** (transient, like `inbound_events`)
| column | type | null | notes |
|---|---|---|---|
| project_id | references → projects, cascade | false | |
| environment | string | false | from the key |
| kind | string | false | `metrics` or `traces` (check constraint) |
| uuid | uuid | false | the payload's `batch_id`, or generated when absent |
| body | text | true | **encrypted** raw JSON; set to nil once processed |
| received_at | datetime | false | |
| processed_at | datetime | true | |

Indexes: unique `[project_id, kind, uuid]` (the idempotency key: a resent batch is accepted and ignored), `[received_at]` (pruning).

**accounts.entitlement_values** gains the key `apm_retention_days` (no schema change).

**Encryption (§1.4):** `ApmTrace#payload` and `ApmInboundBatch#body` join the encrypted attributes (non-deterministic, compressed). The backend slice adds the raw-ciphertext model tests.

### 13.3 Ingest endpoints

```ruby
namespace :api do
  namespace :v1 do
    namespace :apm do
      resource :metrics, only: :create   # POST /api/v1/apm/metrics → Api::V1::Apm::MetricsController#create
      resource :traces, only: :create    # POST /api/v1/apm/traces  → Api::V1::Apm::TracesController#create
    end
  end
end
```

Both are `ActionController::API` controllers that include **`ApmIngestEndpoint`**, a concern sharing `ApiKeyAuthentication`, `IngestErrorResponses`, `Ingest::RequestBody` (gzip, size cap) and the media-type check with `IngestEndpoint`, but **not** the quota check and not the event-weighted counters. Check order: per-IP limit, key (401), per-key and per-account request limits (429), media type (415), size (413), JSON (400), shape (422).

- **Rate limits** (`Apm::Limits`, fixed one-minute windows, store `Ingest::RateLimitStore`, scope `api/v1/apm`, separate from the error counters): 6,000 requests/min per IP (Rails `rate_limit`), 600 requests/min per key and 3,000 requests/min per account (`Ingest::RateCounter` gains a `scope:` keyword, default `Ingest::RateCounter::SCOPE`; each request takes 1). A gem process sends at most 2 requests a minute, so one key covers ~300 processes. All return `429 {"error":"rate_limited"}` with `Retry-After: 60`.
- **Bodies:** metrics ≤ 512 KiB, traces ≤ 2 MiB, compressed and decompressed (`Ingest::RequestBody#read(max:)`). `IngestBodyShield::PATH` grows to `%r{\A/api/v1/(?:events(?:/batch)?|apm/(?:metrics|traces))(?:\.[^/]*)?\z}` so neither body reaches `params` or the log.
- **Validation at request time:** `Apm::MetricsEnvelope` / `Apm::TracesEnvelope` (`.new(json)`, `#valid?`, `#errors`, `#batch_uuid`) check the shape in `docs/INGEST_API.md` › Performance monitoring. A batch is validated as a whole: any structural error gives `422 {"error":"invalid_payload","messages":[…]}` and nothing is stored (the gem builds these payloads, so a bad one is a bug, never retried). Oversized strings are truncated, not rejected. Messages never echo payload content.
- **Storage:** `ApmInboundBatch.store(api_key, kind:, uuid:, body:)` is one `INSERT … ON CONFLICT (project_id, kind, uuid) DO NOTHING RETURNING id` (the body encrypted through the attribute type, as `InboundEvent.store_for` does). A new row enqueues `ProcessApmBatchJob.perform_later(id)` (queue `apm`, **integer id only**); a duplicate enqueues nothing. `ApiKey.record_usage` runs once per request.
- **Response:** `202 {"id":"<batch uuid>"}` for new and duplicate batches alike.

### 13.4 Processing and merge semantics

`ProcessApmBatchJob#perform(apm_inbound_batch_id)` → `Apm::BatchProcessor.new(batch).process`. One transaction, wrapped in `uncached { }` (jobs run with the query cache on):

1. `lock("FOR NO KEY UPDATE")` the batch row; return when it is missing or `processed_at` is set (idempotent across Sidekiq retries).
2. Parse the decrypted body (`Apm::MetricsPayload` / `Apm::TracesPayload`, value objects over the validated JSON). Minutes outside the accepted window are skipped silently: metrics `[now − 24 h, now + 2 min]`, traces `[now − 2 h, now + 2 min]`.
3. **`Apm::TransactionRegistry#ids_for(entries)`** maps `(kind, name)` to `apm_transactions.id` for the batch's project and environment: one SELECT for the names; missing ones are inserted with `insert_all … ON CONFLICT DO NOTHING RETURNING id` (re-selecting conflicts) while the app has fewer than `Apm::MAX_TRANSACTIONS` non-total names of that kind in that environment, otherwise they map to `(other)` (created on demand, outside the cap; an `(other)` the client sent itself, as the gem does past its own cap, is always created). Names are inserted in `[kind, name]` order and the refresh UPDATE locks its rows in id order first, so batches flushed at the same moment don't deadlock; an id still unresolved raises `Apm::TransactionRegistry::Unresolved` rather than reach the upsert as nil. The cap is soft under concurrency (two batches may each add the last names); that is accepted. The total rows are created on demand the same way. One `UPDATE … SET last_seen_at = :now, route = …, … WHERE id IN (…) AND last_seen_at < :now - interval '1 hour'` keeps `last_seen_at` and the latest labels fresh without touching hot rows every minute.
4. **Metrics** (`Apm::StatsUpsert`): entries are merged **in Ruby** first per `[transaction_id, minute]` (several names can map to `(other)`, and `upsert_all` cannot update one row twice), plus one entry per minute for the kind's total row (the sum of that minute's entries). Then two multi-row upserts, **rows sorted by `[apm_transaction_id, time]`** and always minute table first, hourly second (a fixed lock order, so concurrent batches never deadlock): `ApmMinuteStat.upsert_all(rows, unique_by: :primary_key, on_duplicate: Apm::StatsUpsert::ADD_SQL, record_timestamps: false)` and the same into `apm_hourly_stats` with `hour = minute` truncated. `ADD_SQL` adds every column:
   ```sql
   requests_count = <table>.requests_count + EXCLUDED.requests_count,
   failed_count = <table>.failed_count + EXCLUDED.failed_count,
   duration_ms_sum = <table>.duration_ms_sum + EXCLUDED.duration_ms_sum,
   queue_wait_ms_sum = <table>.queue_wait_ms_sum + EXCLUDED.queue_wait_ms_sum,
   bucket_counts = ARRAY(SELECT a + b FROM unnest(<table>.bucket_counts, EXCLUDED.bucket_counts)
                         WITH ORDINALITY AS t(a, b, i) ORDER BY i),
   -- the same element-wise sum for bucket_db_ms, bucket_http_ms, bucket_view_ms, bucket_ruby_ms, queue_wait_counts
   ```
   **Minute → hour rollup happens at write time:** every metrics batch is added to its minute row and to its hour row in the same transaction. There is no rollup job, no watermark and no "late minute" problem: a minute that arrives late (a retried flush) lands in both tables like any other. Minute rows exist only for the short ranges and the last hour; they are pruned after 2 days.
5. **Traces** (`Apm::TraceUpsert`): each trace is normalised by `Apm::TraceNormalizer` (§13.5), then the batch keeps the slowest per `[transaction_id, minute]` in Ruby, then one `ApmTrace.upsert_all(rows, unique_by: [:apm_transaction_id, :minute], on_duplicate: Arel.sql("<every column> = EXCLUDED.<column> … WHERE EXCLUDED.duration_ms > apm_traces.duration_ms"))`, rows sorted by `[apm_transaction_id, minute]`. A slower trace for the same minute replaces the stored one (new uuid, payload and numbers); a faster or equal one changes nothing. `upsert_all` casts `payload` through the encrypted type (§1.4). If the trailing `WHERE` cannot be expressed through `on_duplicate`, write each SET as `CASE WHEN EXCLUDED.duration_ms > apm_traces.duration_ms THEN EXCLUDED.<col> ELSE apm_traces.<col> END`; the semantics are binding, not the spelling.
6. Set `processed_at = now` and `body = nil`.

Statement budget per batch (asserted in tests): metrics ≤ 8 (lock, registry select, ≤ 1 insert + ≤ 1 re-select, last-seen update, minute upsert, hour upsert, batch update); traces ≤ 7. Log lines carry the batch id, kind and counts only (`"APM batch 123 processed: 42 transactions"`); a processing error is logged and re-raised by class name only, never with a message (Postgres messages can echo row values).

**Hourly trim** (`TrimApmTracesJob`, queue `default`, sidekiq-cron `"3 * * * *"`): `Apm::TraceTrim.new(now:).trim` deletes, for the closed hours `[current hour − 3 h, current hour)`, every trace past the 3 slowest per `[apm_transaction_id, hour]`:
```sql
DELETE FROM apm_traces WHERE id IN (
  SELECT id FROM (SELECT id, ROW_NUMBER() OVER (PARTITION BY apm_transaction_id, hour
                                                ORDER BY duration_ms DESC, id) AS rank
                  FROM apm_traces WHERE hour >= :from AND hour < :to) ranked
  WHERE rank > :kept)
```
`:kept` = `ApmTrace::KEPT_PER_CLOSED_HOUR` (3), deleting at most 1,000 ids per statement until none are left. Three hours of look-back cover traces that arrive late (they are accepted up to 2 hours late). When runs were missed (Sidekiq down), the window starts instead at the oldest earlier hour, within `Entitlements::MAX_APM_RETENTION_DAYS`, that still has more than 3 traces of one transaction (one `GROUP BY apm_transaction_id, hour HAVING COUNT(*) > 3` over the `hour` index). The open hour is never trimmed.

**Sidekiq:** add `[apm, 2]` to `config/sidekiq.yml` after `ingest`. `ProcessApmBatchJob` is short and DB-bound; one queue for both kinds.

### 13.5 Trace normalisation and payload (server side)

`Apm::TraceNormalizer#normalize(trace_json)` → `{ columns:, payload: }`. It **allow-lists** keys (anything else in the JSON is dropped), caps every string (`Apm::Limits`), and applies a second layer of scrubbing:

- SQL: `Apm::SqlScrub#scrub` repeats the gem's rules (string and dollar-quoted literals and numbers, including `0x` hex, → `?`; the server doesn't know the client's database, so the SQL is read with a backslash as ordinary (except in `E'…'` strings) and as an escape, and when the readings disagree everything from the first string holding a backslash on becomes one `?`; `IN (…)` lists collapsed, comments removed, whitespace collapsed; `$1` placeholders kept), then `Ingest::Scrubber`'s string scrubbing (tokens, card numbers, JWTs, `password=…`).
- Paths (request path, HTTP span path): the query string and fragment are dropped, then string-scrubbed. HTTP span hosts drop any `user:pass@` part.
- Call-site files go through `Ingest::PathNormalizer`; code-context lines through the string scrubber.
- Spans are capped at `Apm::Limits::SPANS` (300); excess spans are dropped and added to `spans_dropped`.
- Derived columns: `sql_count` and `http_count` (from the trace's counts), `n_plus_one_count` = number of SQL spans with `count >= Apm::N_PLUS_ONE_MIN` (10), the layer columns, `status`, `failed`, `error_event_uuid` (only a valid UUID), `minute`, `hour`.

Stored payload (encrypted JSON; `ApmTrace#details` parses it into `Apm::TraceDetails`, a read-only value object):
```json
{ "request": { "method": "POST", "path": "/checkout", "request_id": "7f3a9c1e-…" },
  "job": null,
  "host": "web-2", "process": "Puma worker 3",
  "runtime": { "ruby": "3.4.1", "rails": "8.0.2" },
  "gc": { "time_ms": 14.0, "count": 3 }, "allocations": 1400000,
  "spans_dropped": 0,
  "spans": [ { "type": "sql", "offset_ms": 40.1, "duration_ms": 1180.0, "span_ms": 1215.2, "count": 38, "rows": 38,
               "name": "Product Load", "sql": "SELECT \"products\".* FROM \"products\" WHERE \"products\".\"id\" = $1 LIMIT $2",
               "call_site": { "file": "app/services/cart_total.rb", "line": 27, "method": "total_cents",
                              "context": { "start_line": 25, "lines": ["…"] } } } ] }
```
Span types: `sql`, `http`, `view`, `enqueue` (the root "Action"/"Job" row is drawn from the trace itself).

### 13.6 Statistics math (`Apm::Distribution`, backend)

`Apm::Distribution` is a value object over one merged histogram: `count`, `failed`, `duration_ms`, `counts[31]`, `db_ms[31]`, `http_ms[31]`, `view_ms[31]`, `ruby_ms[31]`, `queue_wait_counts[31]`, `queue_wait_ms`. `#+` adds element-wise; `Apm::Distribution.empty`.

- **Average** `#average_ms` = `duration_ms / count` (nil when `count` is 0).
- **Percentile** `#percentile(p)` for p ∈ {50, 75, 90, 95, 99}: `rank = ceil(p / 100.0 × count)`; `b` = the first bucket whose cumulative count reaches `rank`; `f = (rank − cumulative_before_b − 0.5) / counts[b]` (0 < f < 1).
  - `b = 0`: `f × BOUNDS_MS[0]` (linear between 0 and 1 ms).
  - `1 ≤ b ≤ 29`: `L × (U / L) ** f` with `L = BOUNDS_MS[b − 1]`, `U = BOUNDS_MS[b]` (geometric interpolation; monotone in p).
  - `b = 30` (≥ 48 s): the bucket's own mean, `(db + http + view + ruby)[30] / counts[30]`, at least 48,000.
- **Layer split** `#layer_split(:average | p)` → `{ db:, http:, view:, ruby: }` in ms, summing exactly to the bar's value:
  - Average: `average_ms` split in the proportions of `Σ db_ms : Σ http_ms : Σ view_ms : Σ ruby_ms` over all buckets.
  - Percentile p: `percentile(p)` split in the proportions of the four layer sums **of the bucket p falls in**. A bucket whose layer sums are all 0 puts everything in `ruby`.
- `#failed_rate` = `failed / count`; `#queue_wait_percentile(p)` uses the same interpolation on `queue_wait_counts` (no overflow mean: bucket 30 reports 48,000 ms); `#rate_per_minute(minutes)`.

**Queries** (`Apm::StatsQuery`, backend; every method is one or two grouped statements whatever the number of transactions):
```ruby
range = Apm::Range.new("1d", now: Time.current, retention_days: entitlements.apm_retention_days)
stats = Apm::StatsQuery.new(range)
stats.by_transaction(ids)            # => { id => Apm::Distribution } over the range
stats.last_hour(ids)                 # => { id => Apm::Distribution } minute rows, minute >= floor(now) − 59 min
stats.past_day(ids)                  # => { id => Apm::Distribution } hourly rows, hour >= floor_hour(now) − 23 h
stats.series(id)                     # => [[bin_start, Apm::Distribution], …] zero-filled bins of range.bin
stats.hourly_p95(ids, hours: 24)     # => { id => [Float | nil] * 24 } (overview sparklines)
```
Bucket arrays are summed with `unnest(bucket_counts, bucket_db_ms, …) WITH ORDINALITY AS b(c, db, http, view, ruby, qw, i)` grouped by `apm_transaction_id, i` (plus `date_bin` for series); scalars in a second grouped SELECT. Hosted ranges are clamped to the retention (`Apm::Range#start`).

**`Apm::Range`** (backend): `KEYS = %w[15m 1h 1d 7d 30d]`, default `1d`.
| key | rows | start | chart bin | bins |
|---|---|---|---|---|
| 15m | minute | floor_minute(now) − 14 min | 1 min | 15 |
| 1h | minute | floor_minute(now) − 59 min | 1 min | 60 |
| 1d | hourly (figures), minute (chart) | floor_hour(now) − 23 h | 15 min | 96 |
| 7d | hourly | floor_hour(now) − 167 h | 2 h | 84 |
| 30d | hourly | floor_hour(now) − 719 h | 8 h | 90 |

`#days` (1 for 15m/1h/1d), `#locked?(entitlements)` (= `days > entitlements.apm_retention_days`), `#label` ("last 15 minutes", "last hour", "last 24 hours", "last 7 days", "last 30 days"), `#minutes` (elapsed minutes, for rates), `#cache_key` (key + current minute). Bins are epoch-aligned (`TimeSeries.align`), zero-filled through `TimeSeries`.

**"Slower"** (`Apm::Slower.new(stats).ratios(ids)` → `{ id => Float }` for the slower ones only): last hour `count >= 30` **and** past 24 hours `count >= 100` **and** `last_hour.percentile(95) >= 1.5 × past_day.percentile(95)` (`Apm::SLOWER_RATIO`, `SLOWER_MIN_LAST_HOUR`, `SLOWER_MIN_PAST_DAY`). The past-day window includes the last hour.

### 13.7 Retention and entitlements

**Configuration** (`config/application.rb`, read once at boot):
```ruby
config.x.apm_retention_days = (ENV["GOODSORCERY_APM_RETENTION_DAYS"].presence || 30).to_i.clamp(1, 30)
```
`config/entitlements.yml` `hosted_defaults` gains `apm_retention_days: 1`.

**`Entitlements`** gains:
```ruby
Entitlements::KEYS                       # => %w[uptime_intervals max_monitors apm_retention_days]
Entitlements::MAX_APM_RETENTION_DAYS     # => 30
entitlements.apm_retention_days          # self-hosted: config.x.apm_retention_days; hosted: stored or default (1)
entitlements.allows_apm_range?(days)     # days <= apm_retention_days (1-day ranges always allowed)
```
Valid stored value: an integer 1..30. The unlimited value is no longer a constant for this key (it reads the self-hosted setting); keep `UNLIMITED` for the uptime keys and resolve `apm_retention_days` through a method. `PROBLEMS["apm_retention_days"]` = "APM retention days must be a whole number from 1 to 30."

**Query time.** `Apm::Range` clamps its start to `now − apm_retention_days`; a locked range in the URL (crafted, or after a downgrade) falls back to `1d`. Traces older than the cutoff are not listed and their page shows "no longer kept" (§13.9).

**Prune** (`Ingest::Retention#prune_apm`, run by `goodsorcery:prune`):
- `apm_minute_stats` older than `ApmMinuteStat::KEPT_FOR` (2 days), one minute slice per DELETE through `[minute]` (`prune_hour_slices`'s pattern with a minute column).
- `apm_hourly_stats` and `apm_traces` past each **account's** `apm_retention_days`: group accounts by the resolved value (`Account.find_each`, values computed in Ruby), then per distinct value delete `where(apm_transaction_id: ApmTransaction.where(project_id: Project.where(account_id: ids)).select(:id), hour: ...cutoff).in_batches(of: BATCH)`. A global backstop deletes anything older than `MAX_APM_RETENTION_DAYS + 1` days by hour slice.
- `apm_transactions` (not total rows) whose `last_seen_at` is older than their account's cutoff (cascades the rest).
- `apm_inbound_batches` with `received_at` older than 1 day, processed or not (unprocessed ones deleted unread, logged by id only).

### 13.8 Web: routes, controllers, presentation objects

**Routes** (inside `resources :projects … scope module: :projects`):
```ruby
resource :performance, only: :show, controller: "performance/overviews" do
  scope module: :performance do
    resources :transactions, only: :show     # /projects/storefront/performance/transactions/42
    resources :traces, only: :show           # /projects/storefront/performance/traces/<uuid>
  end
end
```
Helpers: `project_performance_path`, `project_performance_transaction_path(project, transaction)`, `project_performance_trace_path(project, trace.uuid)`.

**Shared query params** (parsed by `Apm::Selection`, UI): `env` (an environment with APM data; default the project's `default_environment` when it has data, else the environment with the most requests in the past day, else the first with any), `range` (§13.6 keys; locked or unknown → `1d`), overview `tab` (`web` | `jobs`; default `web`, or `jobs` when the environment has no web data), `sort` (`time` default | `p95` | `rate` | `failed`), `q` (filter, ≤ 100 chars, `ILIKE` on name and route with `sanitize_sql_like`), `all` (`1` lifts the 25-row limit); endpoint `traces` (`slowest` default | `newest`) and `page` (1..10,000, `ApmTrace::MAX_PAGE`; clamped so a crafted number cannot overflow the offset). Every link on these pages carries `env` and `range`.

| Controller | Actions | Notes |
|---|---|---|
| `Projects::Performance::OverviewsController` | show | `include ProjectScoped`; `@overview = Apm::Overview.new(@project, selection)`; empty state when the project has no APM data |
| `Projects::Performance::TransactionsController` | show | `@transaction = @project.apm_transactions.listed.find(params[:id])` (total rows and other projects' ids are 404); `@report = Apm::EndpointReport.new(@transaction, selection)` |
| `Projects::Performance::TracesController` | show | `Apm::TraceLookup.new(@project, params[:id], entitlements:, now:)`: found → `@page = Apm::TracePage.new(trace)`; expired → renders `expired` with status **410**; unknown → `ActiveRecord::RecordNotFound` (404) |

Each page sets `provide :nav, "performance"` and the breadcrumbs `Acme Labs / storefront / Performance [/ CheckoutsController#create [/ trace 7f3a9c1e]]` (the trace crumb is the **last** 8 hex digits of the uuid; UUIDv7's first digits are a timestamp and repeat within a minute).

**`Apm::TraceLookup`** (backend): `#trace` (scoped `@project.apm_traces.find_by(uuid:)`), `#expired?`, `#reason`. A missing uuid is **expired** when it is a valid UUIDv7 whose embedded time (`Apm::TraceId.time(uuid)`, the first 48 bits as Unix ms) is between `project.created_at` and now; otherwise it is unknown (404). Reasons: `:plan` (hosted, older than the account's cutoff but within `MAX_APM_RETENTION_DAYS`: shows "Upgrade to keep more days"), `:retention` (older than the cutoff otherwise), `:trimmed` (within the retention: replaced by a slower request in its minute or trimmed from its hour). Another account's trace is a 404 at the project lookup, before any of this runs.

**Presentation objects** (UI; they call the backend query API and never write):
- `Apm::Overview` — `#environments`, `#tiles` (Requests/min, Average, p75, p90, p95, p99, Failed, each with range value, last-hour value and, for p95, the Slower change), `#chart` (bins of the total row: average layer split + p95), `#tab_counts` (web/jobs transactions with data in the range), `#rows` (sorted, filtered, limited 25 unless `all`), `#total_rows_count`. Fixed query count, independent of the number of transactions (≤ 12 statements; asserted with 1 vs 5 transactions). The per-transaction numbers (`{ id => numbers }`, no names) cover both tabs and are cached under `["apm_overview", project.id, env, *range.cache_key]` (range key, retention days, now floored to `range.cache_step`) for `range.cache_step`: 1 minute, 10 minutes for 7d and 30d.
- `Apm::EndpointReport` — `#ribbon`, `#series` (five lines), `#bars` (five layer-split bars), `#summary_sentence`, `#slower_ratio`, `#climbing_since`, `#issues` (unresolved issues of the app whose `transaction_name` equals the transaction name and whose `environments` include `env`, newest `last_seen_at` first, limit 5, plus the count), `#traces` (`Apm::TraceList`: range, sort, 20 per page, `#total`), with the error links resolved in one query (`@project.occurrences.where(uuid: error_uuids).includes(:issue)`).
- `Apm::TracePage` — `#header`, `#chips`, `#layers`, `#timeline_rows` (spans in offset order; grouped spans carry `count`), `#axis_ticks`, `#n_plus_one` (the N+1 group with the largest total, or nil), `#request_rows`, `#error_issue`, `#older`, `#newer` (the adjacent traces of the transaction by `started_at`, one query each).

### 13.9 Screens (match the canvas)

Flat pastel theme, existing tokens and component classes (`.panel`, `.chip-*`, `.btn*`, `.segmented`, `.tab`), server-rendered SVG, no inline styles or scripts, no new JavaScript beyond the existing Stimulus controllers (`dropdown`, `tabs`). Numbers: `apm_duration(ms)` gives "0.4 ms", "412 ms", "1.24 s", "3.2 s", "12.4 s" (3 significant digits, insignificant zeros stripped; tiles split value and unit), rates `delimited`, percentages one decimal ("1.9%", "0.24%" below 1%).

**Colours** (`PerformanceChartHelper` constants): Database `LILAC` `#b39cf2`, External HTTP `IRIS` `#8f94ee`, Views `MINT_400` `#6fcca6`, Ruby `RUBY` `#d2cec4`. Lines: Average `INK` `#34374d` dashed (5 4), p75 `IRIS`, p90 `IRIS_300` `#5a5fd6`, p95 `CORAL` (2.4px), p99 `IRIS_SOFT` `#b7baf3`. Legend order: Database, External HTTP, Views, Ruby; stack order bottom-up: Ruby, Database, External HTTP, Views.

**Sidebar:** "Performance" (`nav_link_to "Performance", project_performance_path(project), key: "performance", icon: :performance`) in Grimoire **after Issues**, before Uptime; `nav_placeholder "Performance", icon: :performance` without a project. `IconHelper` gains `:performance` (a gauge).

**1 · Performance overview**
- Header: eyebrow "storefront · production", title "Performance — last 24 hours" (`range.label`), the environment dropdown ("production ▾", environments with APM data) and the range `.segmented` 15m · 1h · 1d · 7d · 30d. Locked ranges render as disabled segments; when hosted, they are titled "Upgrade to unlock" and `upgrade_to_unlock` follows them, or, without an upgrade URL, they are greyed out with no lock icon, titled "Coming soon", and no upgrade text follows. Self-hosted never shows upgrade copy; a self-hosted range beyond the setting is disabled with the title "This instance keeps N days".
- KPI tiles, one row of seven: **Requests per minute**, **Average**, **p75**, **p90**, **p95**, **p99**, **Failed requests** (jobs tab: "Runs per minute", "Failed runs"). Each shows the range value and a **"Last hour X"** subline: "Last hour 1,310 per minute", "Last hour 164 ms", …, "Last hour 0.31% · see issues" (link to the issue list for `env`). The p95 subline turns coral with "· ▲ 49%" (`(last_hour_p95 / past_day_p95 − 1)`, rounded) when the total row is Slower. "—" when there is no data.
- "Where request time goes" ("Where job time goes" on the jobs tab) panel: "Average time per request by layer, every 15 minutes. The line is p95." (the bin wording follows the range). Stacked layer bars per bin (`apm_layer_bars_svg`) with the p95 line on top, y-axis ticks, x labels "−24h … now" (relative to the range), legend Database · External HTTP · Views · Ruby · p95. The tiles and the chart follow the tab: web shows the web total row, jobs the job total row.
- Tabs "Web requests 23" / "Background jobs 14" (transactions with data in the range), the filter input ("Filter endpoints" / "Filter jobs", GET form) and "Sort: Time consumed ▾" (dropdown: Time consumed, Slowest p95, Most requests, Most failed).
- Table columns: **Endpoint** / **Job** (name, link to the endpoint page; below it the route "POST /checkout", or for jobs "sidekiq · critical · waits 0.8 s (p95)"), **Req/min** / **Runs/min**, **p75**, **p90**, **p95**, **p99**, **Failed**, **Time share** (bar of the row's `duration_ms` over the tab total, and the %), **p95 · 24h** (sparkline of `hourly_p95`, coral when Slower, iris otherwise). Chips after the name: "Slower" (coral with dot) and "N+1 queries" (lilac; any trace of the transaction in the range with `n_plus_one_count > 0`). Default sort: time consumed (`duration_ms` sum) descending. Footer "Showing 7 of 23 endpoints · show all".
- **Empty state** (no APM data for the app): title "See where request time goes", body "Turn on performance monitoring in the goodsorcery gem to see response times, slow endpoints and traces of the slowest requests.", the snippet `config.performance_monitoring = true` and a link to Settings & setup. An environment with no data in the range shows "No requests in the last 24 hours."

**2 · Endpoint detail**
- Same range picker. Eyebrow "Web request · production" / "Background job · production"; title the name (`font-display`); below it "POST /checkout • app/controllers/checkouts_controller.rb" (jobs: "sidekiq · critical • app/jobs/orders/place_job.rb"; the file only when known). When Slower, a coral chip line: "p95 in the last hour is 1.8× the day's, climbing since about 14:00" (the clause after the comma only when `climbing_since` finds a start: the earliest of the last 6 hours from which every hourly p95 is ≥ 1.25× the day's; the time in the viewer's zone).
- Ribbon: **Requests · 24h** (the label follows the range; "60,480", subline "42 per minute · last hour 51"), **Average**, **p75**, **p90**, **p95**, **p99** (each with "Last hour X"; p95 coral "· ▲ 1.8×" when Slower), **Failed** ("1.9%", subline "Last hour 2.4% · 2 issues", where "2 issues" links to the issue list filtered by the transaction name: `project_issues_path(project, q: name, env:)`; "· no issues" when none).
- "Response time" chart: five lines over the range bins (`apm_lines_svg`): Average dashed ink, p75, p90, p95 coral, p99 light; legend in that order.
- "Where time goes": "Requests around each percentile, split by layer. Last day." (range wording). Five horizontal stacked bars: Average, p75, p90, p95, p99, each labelled with its value; then the summary sentence: "Around p95 and p99, <layer> takes the most time (49% and 56%)." followed by "Typical requests mostly wait on <layer>." when the Average bar's largest layer differs, or "Typical requests spend most of their time there too." when it is the same. Layer names: "the database", "external HTTP", "views", "Ruby"; "wait on" for database/HTTP, "spend most of their time in" for views/Ruby.
- "Errors on this endpoint" ("Unresolved issues raised by this endpoint."): rows with class, the redacted title, "GS-1042 · 1,284 events · 2 min ago" and a "New" chip, linking to the issue. Empty: "No unresolved issues from this endpoint."
- "Slow traces · last day" ("We keep the slowest request each minute this hour, and the 3 slowest of each earlier hour."), segmented Slowest | Newest, 20 per page. Columns: Time (`clock_label` with seconds), Duration, Database, Queries, External HTTP ("1.23 s · 2"), Status (HTTP code; jobs "OK" or "Failed"; plus a coral chip with the issue short id linking to the issue when `error_event_uuid` resolves), "Trace →". Footer "8 of 131 traces in the last day" and "Next 20 →" / "← Previous 20". The panel is a `turbo_frame_tag dom_id(transaction, :traces)` so sorting and paging replace only it (`turbo_action: "advance"`).

**3 · Slow request trace**
- "← Older trace" / "Newer trace →" (disabled at the ends). Eyebrow "Slow trace · the slowest request in its minute" (open hour) or "Slow trace · one of the 3 slowest in its hour" (closed hour). Title: method + path ("POST /checkout"; jobs: the job class). Subline: "CheckoutsController#create · Nov 4, 14:32:08 · web-2 · request 7f3a9c1e" (request id: first 8 characters; jobs: queue instead).
- Chips: duration, status ("200 OK"; coral for ≥ 500 or failed), "43 SQL queries", "2 HTTP calls", "1 N+1 pattern" (only when > 0).
- Layer summary: one stacked bar plus four figures (Database 1.22 s 41%, External HTTP, Views, Ruby).
- "Timeline" ("Repeated queries are grouped into one row."): axis ticks (0, 0.5 s … total), a root row ("Action CheckoutsController#create" / "Job Orders::PlaceJob") spanning the trace, then one row per span: type label (SQL / HTTP / View / Job), a short label (`apm_sql_label`: `SELECT "users" WHERE "id" = $1`; HTTP "POST api.taxjar.com/v2/taxes"; view "checkouts/create.html.erb"; enqueue "enqueue Orders::PlaceJob"), an SVG bar from `offset_ms` over `span_ms` (grouped) or `duration_ms`, in the layer colour, and the time. Grouped rows show "×4", or the lilac chip "N+1 ×38" at `count >= 10`. "N spans not shown" when `spans_dropped > 0`.
- N+1 detail (when any): "One query, run 38 times" with the N+1 chip; the full normalised SQL formatted one clause per line (`formatted_sql`: keywords `tok-k`, placeholders `tok-n`); "Values become $1, $2 inside your app, before anything is sent."; Calls / Total / Average / Rows each; "Called from app/services/cart_total.rb:27 in total_cents" with the code context (mono, the call line highlighted, plain text); the hint "Load the products in one query instead:" with `….includes(:product)` (table from the first `FROM "x"`, singularised; without a table: "Preload the association with includes so it loads in one query.").
- Request panel: Status, Host ("web-2 · Puma worker 3"), Started ("14:32:08.114"), Runtime ("Ruby 3.4.1 · Rails 8.0.2"), GC ("14 ms · 3 runs"), Allocations ("1.4M objects"); jobs add Queue and Queue wait. Footnote "Traces carry no params, headers, cookies or bodies."
- "Errors in this request": the linked issue row (class, title, short id) when `error_event_uuid` resolves; "Error reported, but its event is no longer stored." when it doesn't; otherwise "None. Requests that raise link straight to their issue."
- **Expired page** (`traces/expired`, 410): title "This trace is no longer kept"; body by reason: `:retention`/`:plan` "Good Sorcery keeps performance data for N day(s) on this account." (self-hosted: "This instance keeps performance data for N days.") and, for `:plan` only when hosted with an upgrade URL, `upgrade_to_unlock("Upgrade to keep more days")`; `:trimmed` "We keep the slowest request each minute this hour, and the 3 slowest of each earlier hour. A slower request replaced this one." A "Back to Performance" link.

**SVG helpers** (`PerformanceChartHelper`, pure `tag`-built SVG like `ChartHelper`, numbers to 1 dp, a `<title>` per bar/point): `apm_layer_bars_svg(bins, line:)` (stacked bars + p95 line), `apm_lines_svg(series)` (five lines), `apm_split_bar_svg(split, scale_ms:)` (one horizontal stacked bar), `apm_timeline_bar_svg(offset_ms, width_ms, total_ms, color:)`, and the overview sparkline through the existing `sparkline_svg`. `PerformanceHelper`: `apm_duration`, `apm_rate`, `apm_percent`, `apm_tile`, `apm_slower_chip`, `apm_n_plus_one_chip`, `apm_sql_label`, `formatted_sql`, `apm_route_line`, `apm_status_label`.

**Setup page:** the Rails and Ruby initializer snippets (`app/views/projects/setups/*`, `SetupHelper`) gain a commented block, in step with the gem's generator: `# Performance monitoring: response times, slow endpoints, traces of slow requests.` / `# config.performance_monitoring = true`.

### 13.10 Authorization

- Any member of the account may view every APM page (no role gate), as for issues.
- Every lookup starts at `Current.account.projects.find_by!(slug:)`, then `@project.apm_transactions.listed.find(id)` or `@project.apm_traces.find_by(uuid:)`. Never `ApmTrace.find_by(uuid:)` unscoped.
- **Tests on every action** (overview, transaction, trace, expired): `users(:outsider)` gets 404 for acme's URLs; a transaction or trace of `billing` under the `storefront` slug is 404; a total row's id is 404; signed-out requests redirect to sign-in; an unknown or non-v7 uuid is 404; the expired page renders only for the account's own app.

### 13.11 Caching

| What | Key | TTL | Owner |
|---|---|---|---|
| APM request counters | `rate-limit:api/v1/apm:<name>:<id>` | 1 min | backend |
| Overview per-transaction numbers (ids → numbers, no names, no SQL) | `["apm_overview", project.id, env, *range.cache_key]` (both tabs) | `range.cache_step`: 60 s, 10 min for 7d/30d | UI |

Nothing else is cached. Transaction names, routes and anything from a trace payload are never written to the cache. Pages keep `Cache-Control: no-store` (inherited).

### 13.12 Privacy rules (every slice)

- **Encrypted at rest:** `apm_traces.payload` (normalised SQL, call sites, code context, request method/path/request id, job details, host, process, runtime, HTTP hosts/paths, templates) and `apm_inbound_batches.body`.
- **Plaintext, by design:** transaction `name`, `kind`, `http_method`, `route` (a pattern), `adapter`, `queue`, `source_file`, all numbers and timestamps, `status`, `failed`, `uuid`, `error_event_uuid`. These are code identifiers, as `issues.transaction_name` and `culprit` are (§1.5).
- **Never** in job arguments (`ProcessApmBatchJob` takes the integer batch id; `TrimApmTracesJob` none), Redis, the cache, logs, exception or validation messages, or broadcasts (there are none). Processing and trim errors are logged by class name and ids only. Error responses never echo payload content.
- **Traces carry no params, headers, cookies, bodies, query strings or userinfo.** The gem never collects them; the server allow-lists trace keys and strips query strings and userinfo again (§13.5).
- Views render SQL, paths and code through ERB escaping (`formatted_sql` builds with `tag`/`safe_join`); never `raw`/`html_safe`/`sanitize` on trace data.
- Test fixture: the `checkout_slow` trace's code context and SQL carry `apm-fixture-secret`; tests assert it is absent from job args, captured logs, the cache store and every non-trace page, and that the raw `payload` column is ciphertext.

### 13.13 Build slices and file ownership

Two slices in this repo plus the gem build in its own repo (`goodsorcery-ruby/docs/DESIGN.md` §8), all able to run in parallel. The UI slice starts once the backend's first commit (migration, models, fixtures, the §13.6 query API with stubbed numbers if need be) has landed, and runs its tests against it. Never edit a file you don't own; report the need instead. Use your own test database (`TEST_DB_SUFFIX=_<slice>`). Keep methods ≤ 20 lines (aim for 1–8), no `call` objects, shallow conditionals. Run the §9/§10 checklists, `bin/rubocop` and `bin/brakeman` before each commit; commit in logical steps on `main` with the trailer.

**Web backend** (`_apm_backend`)
- `db/migrate/*_create_apm_tables.rb`, `db/schema.rb`, `db/seeds.rb` (a day of demo metrics and a few traces for storefront production, written directly)
- `config/routes.rb` (the API routes of §13.3 **and** the dashboard routes of §13.8), `lib/middleware/ingest_body_shield.rb`, `config/application.rb` (`config.x.apm_retention_days`), `config/entitlements.yml`, `config/sidekiq.yml` (`apm`), `config/schedule.yml` (`trim_apm_traces`), `config/deploy.yml` (pass `GOODSORCERY_APM_RETENTION_DAYS` through when set), `README.md` (the env var), `docs/DEPLOYMENT.md` (the `apm` queue)
- `app/controllers/api/v1/apm/{metrics,traces}_controller.rb`, `app/controllers/concerns/apm_ingest_endpoint.rb` (and `ingest_endpoint.rb` if shared parts move into a common concern)
- Models: `app/models/apm_transaction.rb`, `apm_minute_stat.rb`, `apm_hourly_stat.rb`, `apm_trace.rb`, `apm_inbound_batch.rb`; `app/models/apm/{histogram,limits,distribution,range,stats_query,slower,metrics_envelope,traces_envelope,metrics_payload,traces_payload,batch_processor,transaction_registry,stats_upsert,trace_upsert,trace_normalizer,sql_scrub,trace_trim,trace_lookup,trace_id,trace_details}.rb`; the `has_many` lines in `project.rb`; `app/models/entitlements.rb`; `app/models/ingest/rate_counter.rb` (`scope:`); `app/models/ingest/retention.rb` (`prune_apm`)
- `app/jobs/process_apm_batch_job.rb`, `app/jobs/trim_apm_traces_job.rb`
- `docs/INGEST_API.md` (keep the APM section true to the build)
- Tests: `test/fixtures/{apm_transactions,apm_minute_stats,apm_hourly_stats,apm_traces,apm_inbound_batches}.yml` (fixtures below), `test/controllers/api/v1/apm/**`, `test/models/apm/**` (except the UI's), `test/models/apm_*_test.rb`, `test/models/entitlements_test.rb`, `test/models/ingest/retention_test.rb` additions, `test/jobs/{process_apm_batch,trim_apm_traces}_job_test.rb`, `test/integration/apm_ingest_flow_test.rb`
- **Fixtures:** `checkout_create` (storefront, production, web, `CheckoutsController#create`, `POST /checkout`), `products_show` (web), `place_order_job` (job, sidekiq, critical), `storefront_web_total`, `storefront_jobs_total`, `billing_invoices` (billing), `umbrella_home` (umbrella_app); minute stats for the last 2 hours and hourly stats for the last 25 hours (ERB-relative) for these, with `checkout_create` Slower; traces `checkout_slow` (N+1 group of 38 with call site and code context carrying `apm-fixture-secret`), `checkout_failed` (status 500, `error_event_uuid` = `nomethod_latest`'s uuid), `checkout_old_hour` (a closed hour), `umbrella_trace`; one unprocessed `apm_inbound_batches` row.
- **Required tests:** the histogram literal and `index` edges (0, 0.999, 1, 47,999, 48,000, 10⁶); envelope validation and every error code (401/413/415/422/429 with `ActionController::Base.cache_store = :memory_store`), gzip, `Parameters: {}` for both paths, no quota check (accepted when over quota), separate rate counters from error ingest; a duplicate `batch_id` stored and counted once; processing adds minute, hourly and total rows element-wise, merges duplicate keys in Ruby, sorts rows; two concurrent batches for one transaction-minute sum correctly; the transaction cap folds into `(other)`; minutes outside the window are skipped; a slower trace replaces, a faster one doesn't; the hourly trim keeps the 3 slowest per transaction-hour and never touches the open hour; percentile and layer-split math on known histograms (single bucket, spread, overflow bucket, empty → nil, split sums to the value); Slower thresholds including the minimum counts; entitlements (hosted default 1, stored value wins, invalid ignored, self-hosted setting and clamping, `allows_apm_range?`); prune per account cutoff (including a hosted downgrade), minute rows at 2 days, inbound batches, stale transactions; `TraceLookup` found / trimmed / retention / plan / unknown / non-v7 / future; ciphertext columns; the fixture secret absent from job args, logs and cache; the statement budgets of §13.4.

**Web UI** (`_apm_ui`)
- `app/controllers/projects/performance/{overviews,transactions,traces}_controller.rb`
- `app/models/apm/{selection,overview,endpoint_report,trace_list,trace_page,n_plus_one_hint}.rb`
- `app/views/projects/performance/**` (`overviews/show`, `_header`, `_range_picker`, `_environment_menu`, `_tiles`, `_tile`, `_layer_chart`, `_tabs`, `_table`, `_row`, `_empty`; `transactions/show`, `_hero`, `_ribbon`, `_response_chart`, `_where_time_goes`, `_issues`, `_traces`; `traces/show`, `_hero`, `_chips`, `_layers`, `_timeline`, `_n_plus_one`, `_request`, `_errors`, `expired`)
- `app/helpers/performance_helper.rb`, `app/helpers/performance_chart_helper.rb`, `app/helpers/icon_helper.rb` (`:performance`), `app/views/layouts/_sidebar.html.erb` (the link), `app/helpers/setup_helper.rb` and `app/views/projects/setups/**` (the snippet)
- Tests: `test/controllers/projects/performance/**`, `test/models/apm/{selection,overview,endpoint_report,trace_list,trace_page,n_plus_one_hint}_test.rb`, `test/helpers/{performance,performance_chart}_helper_test.rb`, `test/integration/shell_test.rb` (the sidebar link), `test/system/performance_test.rb` (tabs, range and trace sort through the DOM, `press`/`type_into`)
- **Required tests:** §13.10 authorization on every action; the overview tiles are Requests per minute, Average, p75, p90, p95, p99, Failed (no p50) each with a "Last hour" subline, and the p95 subline is coral with the % change only when Slower; the table shows p75/p90/p95/p99 and no p50; tabs, filter, sort, "show all"; Slower and N+1 chips; the empty state with the snippet; the environment menu; locked ranges with "Upgrade to unlock" hosted, none self-hosted, a crafted locked range falls back to 1d; the endpoint ribbon (Requests, Average, p75, p90, p95, p99, Failed with the issues link), the five-line legend, five bars and the summary sentence; "Errors on this endpoint" lists only unresolved issues of that transaction and environment; traces sorted Slowest/Newest, 20 per page, error chip linking to the issue; trace chips, grouped timeline rows and N+1 detail copy ("Values become $1, $2 inside your app, before anything is sent."), "Traces carry no params, headers, cookies or bodies.", errors in the request; older/newer; the expired page (410) with "Upgrade to keep more days" hosted only; SQL containing `<script>` renders escaped; `no-store`; fixed query counts (overview 1 vs 5 transactions; endpoint and trace pages constant); the overview cache holds numbers only; the setup snippet shows `config.performance_monitoring`.

**Integration (lead, after the slices):** check the gem and server agree (an end-to-end run: a dummy Rails app with the gem against `bin/dev`, data visible on all three pages), update `CLAUDE.md` ("Current state", gotchas: `Apm` naming, write-time rollup, the trace upsert, encrypted traces), then run the full test, system, lint, Brakeman and audit pass.
