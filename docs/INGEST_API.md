# Good Sorcery Ingest API (v1)

Client libraries such as the `goodsorcery` Ruby gem use this API to report errors. It is the same on the hosted service and on self-hosted instances: point your client's `endpoint` at your own host.

- **Endpoint:** `POST {endpoint}/api/v1/events` (one event), or `POST {endpoint}/api/v1/events/batch` (up to 100 events, see [Batches](#batches))
- **Auth:** `Authorization: Bearer <api key>`
- **Body:** one JSON object per request, describing one error event (or `{"events":[…]}` for a batch)
- **Result:** `202 Accepted` with the event id. Processing (grouping, counting, live updates) happens in the background, usually within a second.
- **Key check:** `GET {endpoint}/api/v1/verify` confirms a key without sending an event (see [Verifying a key](#verifying-a-key)).
- **Performance data:** `POST {endpoint}/api/v1/apm/metrics` and `POST {endpoint}/api/v1/apm/traces` (see [Performance monitoring](#performance-monitoring-apm)).

API keys are **ingest-only** and belong to one project environment (for example `production` or `staging`). A key can only submit events. It cannot read anything. Keep keys in server-side configuration and never ship them to browsers or mobile apps.

---

## Request

```http
POST /api/v1/events HTTP/1.1
Host: app.goodsorcery.com
Authorization: Bearer gs_live_9f2c...e81a
Content-Type: application/json
Content-Encoding: gzip              (optional)
User-Agent: goodsorcery-ruby/0.1.0  (recommended)
```

| Header | Required | Notes |
|---|---|---|
| `Authorization` | yes | `Bearer` followed by the project key. Keys start with `gs_live_` (production) or `gs_test_` (other environments). |
| `Content-Type` | yes | Must be `application/json`. |
| `Content-Encoding` | no | `gzip` is supported (any other encoding gets `415`). |
| `User-Agent` | no | `<notifier>/<version>` helps with support. |

The event's **environment always comes from the API key**. Any environment field in the body is ignored.

## Body

Only `exception.class` is required. Every other field is optional, but the more you send, the more useful the issue page becomes.

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
        "file": "app/services/cart_total.rb",
        "line": 42,
        "method": "line_total",
        "in_app": true,
        "context": {
          "start_line": 39,
          "lines": [
            "def line_total(item)",
            "  variant = item.variant || item.product.default_variant",
            "  # TODO: handle discontinued variants",
            "  variant.price_cents * item.quantity",
            "end"
          ]
        },
        "locals": { "item": "#<CartItem id: 88123, variant_id: 4410>", "variant": "nil" }
      },
      { "file": "app/models/order.rb", "line": 112, "method": "build_from_cart", "in_app": true },
      { "file": "gems/activerecord-8.0.1/lib/active_record/relation.rb", "line": 338, "method": "records", "in_app": false }
    ]
  },
  "request": {
    "url": "https://shop.acme.dev/checkout",
    "method": "POST",
    "format": "text/html",
    "request_id": "7d4c2a91-1e0f-4b8e-a2d1-55f0c8e1b0aa",
    "remote_ip": "81.2.69.160",
    "params": { "cart_id": 88123, "shipping_rate": "ups_ground", "coupon": "FALL25", "card_token": "[FILTERED]" },
    "headers": { "Accept": "text/html", "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)", "Referer": "https://shop.acme.dev/cart" },
    "session": { "user_id": 5521, "cart_id": 88123 }
  },
  "user": { "id": "5521", "email": "mara@example.com", "username": "mara", "name": "Mara Lindqvist" },
  "breadcrumbs": [
    { "timestamp": "2026-10-04T09:14:02.700Z", "category": "request", "message": "POST /checkout" },
    { "timestamp": "2026-10-04T09:14:02.714Z", "category": "controller", "message": "CheckoutsController#create as HTML" },
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
  "fingerprint": ["checkout", "missing-variant"],
  "notifier": { "name": "goodsorcery-ruby", "version": "0.1.0" }
}
```

### Fields

| Field | Type | Notes |
|---|---|---|
| `event_id` | UUID string | Optional. It makes retries idempotent: a repeated `event_id` within the same project is accepted but counted once. If missing or not a valid UUID, the server generates one (UUIDv7). |
| `occurred_at` | ISO 8601 timestamp | When the error happened. Defaults to the receive time. Values more than 30 days in the past or 5 minutes in the future are replaced by the receive time. |
| `level` | string | One of `fatal`, `error`, `warning`, `info`. Defaults to `error`. |
| `release` | string | Version or commit SHA, up to 64 chars. |
| `transaction` | string | What was running: `Controller#action`, a job class, or a rake task name. The issue list shows a redacted copy (emails, ids, query strings and tokens replaced, as for the title); the original is kept only in the encrypted event. |
| `exception.class` | string | **Required**, 1–255 chars. |
| `exception.message` | string | Up to 10,000 chars. |
| `exception.backtrace[]` | array of frames | Innermost first. `file` (string, app-relative paths preferred), `line` (integer), `method` (string), `in_app` (boolean, optional: the server infers it from `app/`, `lib/` and `config/` paths outside `gems/` and `vendor/bundle`), `context` (`start_line` plus up to 11 `lines`), and `locals` (string to string, up to 25). Absolute paths are normalised server-side: deploy roots (`/…/releases/<x>/`, `/…/current/`, `/rails/`, `/app/`) are stripped to app-relative paths, gem paths become `gems/<name>-<version>/…`, Ruby stdlib paths become `ruby/<version>/…` and home directories become `~/`. |
| `request` | object | `url`, `method`, `format`, `request_id`, `remote_ip`, and the nested objects `params`, `headers` and `session`. Other request keys are dropped. |
| `job` | object | The background job the error happened in, instead of (or as well as) `request`. Known keys: `framework` (`active_job`, `sidekiq`), `class`, `mailer` and `action` (Action Mailer `deliver_later`), `id`, `provider_job_id`, `queue`, `priority`, `executions`, `retry_count` (Sidekiq), `enqueued_at`, `scheduled_at` (strings or numbers, stored as strings of up to 255 chars), and `arguments` (an array, or an object for mailer params). Other job keys are dropped. Arguments are bounded like `request.params` and scrubbed by key at any depth; key filtering cannot protect a secret passed as a bare positional argument, so clients should let apps turn arguments off. Shown on the issue page's Job tab. See [Background jobs](#background-jobs). |
| `user` | object | `id`, `email`, `username`, `name` (strings or numbers). Other user keys are dropped. The server stores identifiers only as keyed hashes for counting and search. The values themselves are kept encrypted with the event. |
| `breadcrumbs[]` | array | `timestamp` (ISO 8601), `category` (`request`, `controller`, `sql`, `http`, `cache`, `log`, `job`, `custom`; other values become `custom`), `level` (`debug`, `info`, `warning`, `error`), `message`, and `data` (object). The most recent 100 are kept. |
| `context` | object | Free-form runtime details shown on the Environment tab. Use `runtime.ruby` and `runtime.rails` to label the project, and `host` to add a `host` tag automatically. |
| `tags` | object | String keys matching `/\A[a-z0-9_.\-]{1,32}\z/i` mapped to scalar values (strings, numbers, booleans; stored as strings). Up to 25 pairs; invalid keys and nested values are dropped. Shown as distribution bars on the issue page. The server adds `environment` (always from the key, overriding any client value), `release` and `host` (from `context.host`) unless the client sent those keys. |
| `fingerprint` | array of strings | Optional custom grouping. Events with the same fingerprint array are grouped into one issue. Up to 10 strings (or numbers), 200 chars each; other values are ignored. |
| `notifier` | object | `name` and `version` of the client library. |

### Background jobs

An error raised in a background job sends a `job` section in place of `request`, with the job class as `transaction`:

```json
{
  "transaction": "ChargeCustomerJob",
  "exception": { "class": "Stripe::CardError", "message": "Your card was declined." },
  "job": {
    "framework": "active_job",
    "class": "ChargeCustomerJob",
    "id": "5f0c8e1b-7d4c-4b8e-a2d1-2a911e0f55aa",
    "provider_job_id": "b1e0f3c2a9d8e7f6a5b4c3d2",
    "queue": "billing",
    "priority": 10,
    "executions": 3,
    "enqueued_at": "2026-10-04T09:14:01.000Z",
    "scheduled_at": "2026-10-04T09:15:00.000Z",
    "arguments": ["gid://shop/Customer/88123", { "amount_cents": 4200, "card_token": "[FILTERED]" }]
  }
}
```

A mailer delivered with `deliver_later` adds `"mailer": "UserMailer", "action": "welcome"` and sends the mailer method's args or params as `arguments`. A Sidekiq job not wrapped by Active Job sends `"framework": "sidekiq"`, its `jid` as `id` and `retry_count`. Records are sent as their GlobalID strings, never loaded or dumped.

### Grouping

Without a custom `fingerprint`, events are grouped by:

1. the exception class plus the file and method of the **top in-app frame** (line numbers are ignored, so editing the file doesn't split the issue); or
2. if there is no in-app frame, the exception class plus the message with numbers, ids, emails, IPs and tokens normalised.

A resolved issue that receives a new event becomes **unresolved and regressed**.

## Privacy and scrubbing

Scrub as much as you can **in the client**. The Ruby gem applies `Rails.application.config.filter_parameters` before sending. The server scrubs again as a second layer of defence:

- Values under keys that match `password`, `secret`, `token`, `api_key`, `access_key`, `private_key`, `authorization`, `cookie`, `csrf`, `xsrf`, `credit_card`, `card_number`, `cvv`, `cvc`, `ssn`, `otp` or `session_id` (plus each project's extra scrub keys) become `"[FILTERED]"`.
- Card-shaped numbers that pass the Luhn check (identifiers are left whole: UUIDs such as job and request ids, and words of 20 or more hex characters such as Sidekiq job ids and git SHAs), `Bearer …`/`Basic …`/`Digest …`/`ApiKey …` credentials (and `Token …` with a token-like value), JWT-like strings, sensitive URL query parameters, passwords in URLs (`postgres://user:[FILTERED]@host`, `redis://:[FILTERED]@host`) and sensitive keys written as text (`password=…`, `api_key: …`, `"token"=>"…"`, `"secret": "…"`) are replaced with `[FILTERED]` inside any string, including the exception message, code context, locals and breadcrumbs.
- Locals sent as objects are scrubbed by key before they are turned into text.
- User fields `id`, `email`, `username` and `name` are kept as sent (encrypted) because they identify affected users.
- Job arguments are scrubbed by key like params, and bare string arguments like any other string.
- Everything captured (backtraces, code context, locals, request, params, headers, session, job, user, breadcrumbs, context and tag values) is stored **encrypted at rest**. The searchable issue title is a redacted copy of the message (emails, IPs, UUIDs, numbers, tokens, query strings and value dumps such as `Failing row contains (…)`, `Key (…)=(…)` and `'column'=value` are replaced with placeholders). The transaction name and culprit shown in the issue list are redacted the same way.

## Responses

| Status | Body | Meaning |
|---|---|---|
| `202 Accepted` | `{"id":"0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1"}` | Stored and queued for processing. |
| `400 Bad Request` | `{"error":"invalid_json"}` | The body is not valid JSON. |
| `401 Unauthorized` | `{"error":"invalid_api_key"}` | Missing, malformed, unknown or rotated key. Includes `WWW-Authenticate: Bearer realm="ingest"`. |
| `413 Payload Too Large` | `{"error":"payload_too_large"}` | Body over 512 KiB (2 MiB for a batch), compressed or decompressed. |
| `415 Unsupported Media Type` | `{"error":"unsupported_media_type"}` | `Content-Type` is not `application/json`, or `Content-Encoding` is neither absent, `identity` nor `gzip`. |
| `422 Unprocessable Entity` | `{"error":"invalid_payload","messages":["exception.class is required"]}` | Valid JSON with the wrong shape. |
| `429 Too Many Requests` | `{"error":"rate_limited"}` | Includes a `Retry-After` header in seconds (`60`). A rejected request uses up none of the key's or account's allowance. |
| `429 Too Many Requests` | `{"error":"quota_exceeded"}` | The account has used its monthly event quota: on the hosted service, 3,000 error events per UTC month unless the account has another quota. Self-hosted instances have no quota. A changed quota applies at the next request; otherwise the answer can lag the count by a few minutes. |

Checks run in this order: per-IP rate limit, API key (`401`), per-key and per-account rate limits, monthly quota, media type (`415`), body size (`413`), JSON (`400`), shape (`422`). For a batch, the per-key and per-account limits are charged one unit per event: one unit before the body is read (as for a single event, so a key or account with no room left gets `429` straight away), and the rest once the body is parsed and the `events` array checked (after `422` for a malformed array, before the events themselves are validated).

Clients should retry `429` and `5xx` responses with backoff, reusing the same `event_id`. They should not retry `400`, `401`, `413`, `415` or `422`.

## Batches

`POST /api/v1/events/batch` takes up to 100 events in one request. Same headers, auth, gzip and quota rules as the single endpoint. One request with keep-alive and gzip costs far less than 100, so clients that queue events (the Ruby gem does by default) should use it.

```json
{ "events": [ { "event_id": "…", "exception": { "class": "NoMethodError" } }, { "exception": { "class": "Timeout::Error" } } ] }
```

- The body is at most **2 MiB**, compressed and decompressed (`413` otherwise).
- `events` must be an array of **1 to 100** events. A missing, non-array, empty or longer `events` array gets `422 {"error":"invalid_payload","messages":["events must be an array"]}` (or `events must not be empty`, `events must hold at most 100 events`) and nothing is stored.
- Each event is validated exactly like a single request body and stored on its own. An event that does not validate, or that is over 512 KiB once re-serialised, is rejected by its index; the others are accepted.
- Rate limits count **events**: a batch of 25 uses 25 of the key's and the account's per-minute allowance, the same allowance single events use one at a time. If the whole batch does not fit, it gets `429` with `Retry-After`, nothing is stored and nothing is used up. A batch refused as a whole with `400`, `413`, `415` or `422` uses one unit, like a single request. The per-IP limit counts requests.

| Status | Body | Meaning |
|---|---|---|
| `202 Accepted` | `{"accepted":[{"index":0,"id":"0192f7a4-…"}],"rejected":[{"index":3,"error":"invalid_payload","messages":["exception.class is required"]}]}` | At least one event was stored and queued. `rejected` lists the others (`invalid_payload` with `messages`, or `payload_too_large`). |
| `422 Unprocessable Entity` | the same shape, with an empty `accepted` | No event was accepted. |
| `400`, `401`, `413`, `415`, `422 invalid_payload`, `429` | as for the single endpoint | The whole request was refused; nothing was stored. |

Retry the whole batch on `429` and `5xx`, reusing every `event_id` (events that were in fact stored are counted once). Do not resend rejected events: they will be rejected again. On `413`, split the batch.

## Verifying a key

`GET /api/v1/verify` with the same `Authorization: Bearer <api key>` header checks that the endpoint is reachable and the key valid. It creates nothing and does not count toward the event rate limits or the monthly quota.

| Status | Body |
|---|---|
| `200 OK` | `{"ok":true,"environment":"staging"}` (the key's environment) |
| `401 Unauthorized` | `{"error":"invalid_api_key"}` |
| `429 Too Many Requests` | `{"error":"rate_limited"}` with `Retry-After` (60 checks a minute per key) |

The Ruby gem uses it for its install check (`bin/rails goodsorcery:verify`).

## Performance monitoring (APM)

Two endpoints receive performance data. Clients aggregate in process and send **once a minute per process**: one metrics payload, and one traces payload when there are traces. The Ruby gem does this when `config.performance_monitoring = true`.

- `POST {endpoint}/api/v1/apm/metrics`: per-transaction, per-minute counts and histograms.
- `POST {endpoint}/api/v1/apm/traces`: timelines of the slowest request per transaction per minute.

Both use the same `Authorization`, `Content-Type: application/json` and optional `Content-Encoding: gzip` headers as error events (gzip is recommended; the gem always compresses bodies of 1 KiB or more). The **environment comes from the API key**. Performance data **does not count toward the monthly event quota** and is accepted when the quota is used up; it has its own rate limits (below).

### Transactions

A transaction is what ran:

| `kind` | `name` | Labels |
|---|---|---|
| `web` | `Controller#action`, e.g. `CheckoutsController#create` | `method` (`POST`) and `route`, the route **pattern** (`/products/:slug`), never the real path |
| `job` | the job class, e.g. `Orders::PlaceJob` | `adapter` (`sidekiq`, `async`, …) and `queue` |

Both kinds may send `source`, the app-relative file of the controller or job class (`app/controllers/checkouts_controller.rb`). The server keeps at most 500 names per app, environment and kind; data for further names is counted under the name `(other)`. Clients should fold names past their own cap into `(other)` too.

### Histogram buckets (scheme `gs-v1`)

Durations are counted in 31 fixed buckets on a log scale. These are the upper bounds of buckets 0–29 in milliseconds; bucket 30 holds everything from 48,000 ms up:

```
1, 1.5, 2, 3, 4.5, 6.5, 9.5, 14, 20, 28,
40, 60, 85, 125, 180, 260, 380, 550, 800, 1150,
1700, 2450, 3550, 5100, 7500, 11000, 16000, 23000, 33000, 48000
```

Bucket `i` holds durations `d` with `bound[i-1] <= d < bound[i]` (bucket 0 starts at 0). In other words, the index is the number of bounds that are `<= d`: 0.4 ms goes in bucket 0, exactly 1 ms in bucket 1, 250 ms in bucket 15 and 60 s in bucket 30. Each edge is about 1.45× the one before, so a reported percentile is within about ±20% of the true value. Queue wait uses the same buckets.

### Metrics payload

```json
{
  "batch_id": "0192f7b0-1a2b-7c3d-8e4f-5a6b7c8d9e0f",
  "histogram": "gs-v1",
  "notifier": { "name": "goodsorcery-ruby", "version": "0.2.0" },
  "minutes": [
    {
      "minute": "2026-11-04T14:32:00Z",
      "transactions": [
        {
          "kind": "web",
          "name": "CheckoutsController#create",
          "method": "POST",
          "route": "/checkout",
          "source": "app/controllers/checkouts_controller.rb",
          "count": 42,
          "failed": 1,
          "duration_ms": 14280.5,
          "buckets": [[15, 30, 2101.4, 3302.0, 1500.2, 1040.1], [17, 10, 1820.1, 2640.2, 300.4, 410.0], [20, 2, 1210.0, 1180.3, 80.2, 96.0]]
        },
        {
          "kind": "job",
          "name": "Orders::PlaceJob",
          "adapter": "sidekiq",
          "queue": "critical",
          "source": "app/jobs/orders/place_job.rb",
          "count": 38,
          "failed": 0,
          "duration_ms": 16012.0,
          "buckets": [[17, 37, 8020.5, 4100.0, 0, 3471.5], [19, 1, 300.0, 600.0, 0, 120.0]],
          "queue_wait_ms": 4210.0,
          "queue_wait": [[11, 30], [15, 8]]
        }
      ]
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `batch_id` | UUID string | Optional but recommended. The idempotency key: a payload resent with the same `batch_id` is accepted and counted once. Reuse it when retrying. Missing or invalid → the server generates one (and cannot deduplicate). |
| `histogram` | string | **Required**, `"gs-v1"`. Any other value gets `422`. |
| `notifier` | object | `name` and `version` of the client library. |
| `minutes[]` | array | **Required**, 1–5 entries, one per minute (a client sends more than one only after a failed flush). |
| `minutes[].minute` | ISO 8601 timestamp | **Required**, the UTC start of the minute (seconds and fractions must be 0). The minute in which the requests **finished**. Minutes more than 24 hours old or more than 2 minutes in the future are skipped. |
| `minutes[].transactions[]` | array | **Required**, 1–1,000 entries. A transaction should appear at most once per minute (repeats are added together). |
| `kind` | string | **Required**, `web` or `job`. |
| `name` | string | **Required**, 1–255 chars (longer is truncated). `All web requests` and `All background jobs` are reserved for the app-wide totals; data sent under them is counted under `(other)`. |
| `method`, `route` | strings | Web only; `method` ≤ 16 chars, `route` ≤ 255 chars. Optional. |
| `adapter`, `queue` | strings | Jobs only; ≤ 32 and ≤ 128 chars. Optional. |
| `source` | string | Optional, ≤ 500 chars, app-relative. |
| `count` | integer | **Required**, ≥ 1: requests (or job runs) that finished in this minute. |
| `failed` | integer | **Required**, 0..`count`. Web: status ≥ 500 or an exception escaped. Job: an exception escaped (each attempt counts). |
| `duration_ms` | number | **Required**, ≥ 0: the sum of the total durations. |
| `buckets[]` | array of arrays | **Required**, 1–31 entries `[index, count, db_ms, http_ms, view_ms, ruby_ms]`, one per bucket that has requests, in any order: `index` 0..30 (each at most once), `count` ≥ 1, and the summed time per layer of the requests in that bucket (numbers ≥ 0). The counts must add up to `count`. Layers: `db_ms` is SQL time (not schema or cached queries), `http_ms` outgoing HTTP calls, `view_ms` template rendering (without double-counting nested renders or the queries inside them), `ruby_ms` the rest (per request: total − the other three, floored at 0). |
| `queue_wait_ms` | number | Jobs only, optional: the summed queue wait (start − `enqueued_at`, or − `scheduled_at` for scheduled jobs). |
| `queue_wait[]` | array of arrays | Jobs only, optional, ≤ 31 entries `[index, count]`; the counts add up to at most `count` (jobs without an enqueue time have no wait). |

Numbers are JSON numbers (integers or decimals; `NaN`/`Infinity` are invalid). Unknown fields are ignored. The server merges metrics by **addition**: any number of processes may report the same transaction and minute.

### Traces payload

```json
{
  "batch_id": "0192f7b0-1a2c-7d4e-9f50-6b7c8d9e0f1a",
  "notifier": { "name": "goodsorcery-ruby", "version": "0.2.0" },
  "traces": [
    {
      "id": "0192f7af-9c1e-7a3b-8c2d-4e5f6a7b7f3a",
      "kind": "web",
      "name": "CheckoutsController#create",
      "method": "POST",
      "route": "/checkout",
      "minute": "2026-11-04T14:32:00Z",
      "started_at": "2026-11-04T14:32:08.114Z",
      "duration_ms": 2940.2,
      "db_ms": 1220.4, "http_ms": 1230.0, "view_ms": 320.1, "ruby_ms": 169.7,
      "status": 200,
      "failed": false,
      "error_event_id": null,
      "request": { "method": "POST", "path": "/checkout", "request_id": "7f3a9c1e-55d2-4c1a-9e0b-2d1f0a9b8c7d" },
      "host": "web-2",
      "process": "Puma worker 3",
      "runtime": { "ruby": "3.4.1", "rails": "8.0.2" },
      "gc": { "time_ms": 14.0, "count": 3 },
      "allocations": 1400000,
      "sql_count": 43,
      "http_count": 2,
      "spans_dropped": 0,
      "spans": [
        { "type": "sql", "offset_ms": 12.1, "duration_ms": 3.0, "name": "User Load",
          "sql": "SELECT \"users\".* FROM \"users\" WHERE \"users\".\"id\" = $1 LIMIT $2", "rows": 1 },
        { "type": "sql", "offset_ms": 40.1, "duration_ms": 1180.0, "span_ms": 1215.2, "count": 38, "rows": 38,
          "name": "Product Load",
          "sql": "SELECT \"products\".* FROM \"products\" WHERE \"products\".\"id\" = $1 LIMIT $2",
          "call_site": { "file": "app/services/cart_total.rb", "line": 27, "method": "total_cents",
                         "context": { "start_line": 25, "lines": ["def total_cents", "  items.sum do |item|", "    item.product.price_cents * item.quantity", "  end", "end"] } } },
        { "type": "http", "offset_ms": 1260.0, "duration_ms": 550.0, "method": "POST", "host": "api.taxjar.com", "path": "/v2/taxes", "status": 200 },
        { "type": "view", "offset_ms": 2560.3, "duration_ms": 320.1, "template": "checkouts/create.html.erb" },
        { "type": "enqueue", "offset_ms": 2900.0, "duration_ms": 4.0, "job": "Orders::PlaceJob", "queue": "critical" }
      ]
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `batch_id` | UUID string | As for metrics. |
| `traces[]` | array | **Required**, 1–50 traces. |
| `id` | UUID string | The trace id, a **UUIDv7** (its first 48 bits are the start time in Unix ms). Missing or invalid → generated. |
| `kind`, `name`, `method`, `route`, `adapter`, `queue` | | As for metrics; `kind` and `name` are required. |
| `minute` | ISO 8601 timestamp | **Required**, the UTC start of the minute in which the request finished (the metrics minute). Traces more than 2 hours old or more than 2 minutes in the future are skipped. |
| `started_at` | ISO 8601 timestamp | **Required**, with milliseconds. |
| `duration_ms` | number | **Required**, ≥ 0. |
| `db_ms`, `http_ms`, `view_ms`, `ruby_ms` | numbers | The request's time per layer (as in metrics buckets). |
| `status` | integer | Web: the HTTP status (500 when an exception escaped). Omit for jobs. |
| `failed` | boolean | As for metrics. |
| `error_event_id` | UUID string or null | The `event_id` of the error event reported for this request, if any. The trace page links to its issue. |
| `request` | object | Web only: `method`, `path` (≤ 1,024 chars, **no query string**) and `request_id` (≤ 128 chars). Nothing else: no params, headers, cookies or bodies. |
| `job` | object | Jobs only: `adapter`, `queue`, `queue_wait_ms`, `executions` (integer). |
| `host`, `process` | strings | ≤ 255 chars each: server host name and a process label. |
| `runtime` | object | `ruby` and `rails` version strings (≤ 64 chars). |
| `gc` | object | `time_ms` (number) and `count` (integer) during the request. |
| `allocations` | integer | Objects allocated during the request. |
| `sql_count`, `http_count` | integers | Calls made, counting every call in a grouped span. |
| `spans_dropped` | integer | Spans not sent because of the client's cap. |
| `spans[]` | array | ≤ 300 spans (more are dropped and counted in `spans_dropped`), in start order. Common fields: `type` (`sql`, `http`, `view`, `enqueue`; others are dropped), `offset_ms` (from the request start), `duration_ms`. A **grouped** span (the same normalised SQL repeated, or the same template rendered repeatedly) adds `count` (≥ 2), `span_ms` (first start to last end) and has `duration_ms` = the total of its calls. |
| `sql` spans | | `sql` (≤ 2,000 chars, **normalised**: no literal values, see below), `name` (≤ 255, e.g. `Product Load`), `rows` (integer, optional), and for a group `call_site`: `file` (app-relative), `line`, `method`, and optional `context` (`start_line` plus ≤ 5 `lines` of ≤ 200 chars). |
| `http` spans | | `method`, `host` (≤ 255, never `user:pass@`), `path` (≤ 1,024, **no query string**), `status` (integer, absent when no response). |
| `view` spans | | `template` (≤ 255, relative to `app/views`). |
| `enqueue` spans | | `job` (class name) and `queue`. |

**SQL must be normalised by the client.** String and dollar-quoted literals and numbers become `?`, `IN (…)` lists of placeholders collapse to `IN (…)`, comments are removed and whitespace is collapsed; bind placeholders such as `$1` stay. The server repeats this and scrubs secrets from every string as a second layer, and drops any key not listed above. Repeated identical SQL in one trace counts as an **N+1 query** when it ran 10 or more times.

The server keeps at most one trace per transaction per minute while that hour is open (a slower trace for the same minute replaces the stored one) and the 3 slowest per transaction for each earlier hour. Traces are stored encrypted.

### Responses

| Status | Body | Meaning |
|---|---|---|
| `202 Accepted` | `{"id":"0192f7b0-1a2b-7c3d-8e4f-5a6b7c8d9e0f"}` | Stored and queued (or already received: the same `batch_id` is never counted twice). |
| `400 Bad Request` | `{"error":"invalid_json"}` | |
| `401 Unauthorized` | `{"error":"invalid_api_key"}` | |
| `413 Payload Too Large` | `{"error":"payload_too_large"}` | Metrics over 512 KiB, traces over 2 MiB, compressed or decompressed. |
| `415 Unsupported Media Type` | `{"error":"unsupported_media_type"}` | |
| `422 Unprocessable Entity` | `{"error":"invalid_payload","messages":["minutes[0].transactions[3].buckets must add up to count"]}` | The payload is checked as a whole; nothing is stored. Messages (at most 20) name fields, never values. |
| `429 Too Many Requests` | `{"error":"rate_limited"}` | With `Retry-After: 60`. |

Checks run in this order: per-IP rate limit, API key (`401`), per-key and per-account rate limits, media type (`415`), body size (`413`), JSON (`400`), shape (`422`). There is no quota check.

Clients should keep a payload and retry it (same `batch_id`) on `429` (after `Retry-After`) and `5xx`, for a few minutes at most, and drop it on `400`, `401`, `413`, `415` and `422`. A `404` means the server has no performance endpoints (an older version); the gem then turns performance monitoring off for the process.

## Limits

| Item | Limit |
|---|---|
| Request body | 512 KiB, compressed and decompressed; 2 MiB for a batch |
| Batch | 1–100 events; each event ≤ 512 KiB once re-serialised |
| Rate | 1,200 events/minute per API key; 6,000 events/minute per account (a batch of N counts N); 6,000 requests/minute per IP |
| Key checks (`/verify`) | 60/minute per API key |
| Performance (`/apm/metrics`, `/apm/traces`) | 600 requests/minute per API key; 3,000 requests/minute per account; 6,000 requests/minute per IP. Not counted toward the event quota or the event rate limits |
| Performance metrics | body 512 KiB; 1–5 minutes; 1–1,000 transactions per minute; 500 transaction names per app, environment and kind (more become `(other)`) |
| Performance traces | body 2 MiB; 1–50 traces; 300 spans per trace; SQL 2,000 chars; code context 5 lines of 200 chars |
| Tag values | 100 distinct values per tag key per issue (later new values count as "Other values"); 40 tag keys per issue |
| Apps and keys | 100 apps per account; 10 API keys per app |
| Exception message | 10,000 chars |
| Backtrace | first 250 frames; context ≤ 11 lines of ≤ 500 chars; ≤ 25 locals of ≤ 500 chars |
| Breadcrumbs | last 100; message ≤ 1,000 chars; `data` ≤ 20 keys |
| Tags | 25 pairs; value ≤ 200 chars |
| `request`, `params`, `headers`, `session`, `context`, `job.arguments` | nesting depth ≤ 6; arrays ≤ 50 items; objects ≤ 100 keys; strings ≤ 4,096 chars |
| Job fields (`job.class`, `job.queue`, …) | 255 chars each |
| User fields | 255 chars each |

Oversized values are truncated rather than rejected (deeper nesting becomes `"[truncated]"`). Only an oversized request body is rejected (413).

## Example with curl

```sh
curl -sS https://app.goodsorcery.com/api/v1/events \
  -H "Authorization: Bearer $GOODSORCERY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
        "exception": {
          "class": "RuntimeError",
          "message": "Cast a test error",
          "backtrace": [{ "file": "lib/tasks/goodsorcery.rake", "line": 3, "method": "block in <main>", "in_app": true }]
        },
        "transaction": "rake goodsorcery:test",
        "tags": { "source": "curl" }
      }'
# => {"id":"0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1"}
```

Gzip:

```sh
gzip -c event.json | curl -sS https://app.goodsorcery.com/api/v1/events \
  -H "Authorization: Bearer $GOODSORCERY_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Content-Encoding: gzip" \
  --data-binary @-
```

## Sending a test event

`bin/send_test_event` posts a realistic sample event (fictional data, including values the server scrubs):

```sh
bin/send_test_event gs_test_... http://localhost:3000
GOODSORCERY_API_KEY=gs_live_... GOODSORCERY_HOST=https://errors.example.com bin/send_test_event
EVENT_ID=0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1 bin/send_test_event gs_test_...   # same id twice: counted once
GZIP=1 EXCEPTION_CLASS=Demo::OtherError bin/send_test_event gs_test_...          # gzip body, a different issue
BATCH=25 GZIP=1 bin/send_test_event gs_test_...                                  # 25 events in one batch request
JOB=1 bin/send_test_event gs_test_...                                            # an error from a job, with a job section
```

It prints the status and body and exits non-zero unless the response is `202`. Sending it twice produces one issue with 2 events. `JOB=1` sends the error as raised in an Active Job (`job` section with arguments, no request), so the issue page opens on the Job tab. `BATCH=N` sends N copies (each with its own `event_id` unless `EVENT_ID` is set) in one request to the batch endpoint.

## Sending test performance data

`bin/send_test_apm` posts a metrics payload for the last closed minute (two endpoints and a job) and a traces payload with one slow checkout request (fictional data):

```sh
bin/send_test_apm gs_test_... http://localhost:3000
GZIP=1 MINUTES=3 bin/send_test_apm gs_test_...                                   # gzip bodies, three closed minutes
BATCH_ID=0192f7b0-1a2b-7c3d-8e4f-5a6b7c8d9e0f bin/send_test_apm gs_test_...      # same id twice: counted once
SLOW=1 bin/send_test_apm gs_test_...                                             # every request ten times slower
TRACES=0 bin/send_test_apm gs_test_...                                           # metrics only
```

It prints each status and body and exits non-zero unless both are `202`.

## Operating (self-hosted)

- Events are processed by Sidekiq on the `ingest` queue, with weights `ingest: 3`, `default: 2`, `mailers: 1`.
- Run `bin/rails goodsorcery:prune` daily (cron or a Kamal accessory). It deletes occurrences older than each project's retention period (30, 60 or 90 days, chosen in Settings › General; 30 by default, and on the hosted service 30 unless the account includes longer retention), affected-user records and tag values of issues not seen within that period, hourly issue counts older than 31 days, hourly project counts older than 90 days and inbound events that failed to process for over a day. Each issue keeps at most its newest 100 stored occurrences, and each project at most 3,000 (`CapStoredOccurrencesJob`, every 5 minutes): the issues with the most stored copies lose their oldest first, and every issue keeps its newest. Every event is still counted.
- Performance data is processed on the `apm` queue. `goodsorcery:prune` also deletes per-minute performance rows after 2 days, hourly rows and traces past the retention (`GOODSORCERY_APM_RETENTION_DAYS`, default and maximum 30 days on a self-hosted instance) and performance batches after a day. An hourly job trims each closed hour to the 3 slowest traces per transaction.
- `bin/rails goodsorcery:requeue_stale` re-enqueues events that were accepted but have not been processed after 10 minutes (for example after a Redis outage). Processing is idempotent, so a requeued event that was in fact processed is a no-op.
- Accepted bodies wait in the `inbound_events` table (encrypted) until processed; job arguments hold only the record's GlobalID, so Redis never sees event data. Events that turn out to be malformed or duplicates are discarded and logged by id only.
- Production needs the Active Record encryption keys as the env vars `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`. Generate them with `bin/rails db:encryption:init`. Losing them makes stored events unreadable.
- Other environment variables:
  - `GOODSORCERY_PUBLIC_URL` (**required in production**, for example `https://errors.example.com`) is this instance's public URL. It is the endpoint shown in the setup page's install snippets, the host of links in emails (password resets) and the only host the app answers to (DNS rebinding protection; `/up` answers on any host). Production refuses to boot without it.
  - `GOODSORCERY_EXTRA_HOSTS` adds comma-separated host names the app also answers to.
  - `GOODSORCERY_MAIL_FROM` sets the sender of emails; the default is `Good Sorcery <no-reply@<public host>>`.
  - Sign-up is open only until the first account exists. `GOODSORCERY_ENABLE_SIGNUPS=1` keeps it open (the hosted service); `GOODSORCERY_DISABLE_SIGNUPS=1` turns it off completely and sends visitors to sign-in.
  - `GOODSORCERY_HOSTED=1` marks the instance as the hosted service; leave it unset when self-hosting.
  - `GOODSORCERY_APM_RETENTION_DAYS` (1–30, default 30) is how many days a self-hosted instance keeps performance data.
