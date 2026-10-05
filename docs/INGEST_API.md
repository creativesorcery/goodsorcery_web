# Good Sorcery Ingest API (v1)

Client libraries such as the `goodsorcery` Ruby gem use this API to report errors. It is the same on the hosted service and on self-hosted instances: point your client's `endpoint` at your own host.

- **Endpoint:** `POST {endpoint}/api/v1/events`
- **Auth:** `Authorization: Bearer <api key>`
- **Body:** one JSON object per request, describing one error event
- **Result:** `202 Accepted` with the event id. Processing (grouping, counting, live updates) happens in the background, usually within a second.

API keys are **ingest-only** and belong to one project environment (for example `production` or `staging`). A key can only submit events. It cannot read anything. Keep keys in server-side configuration and never ship them to browsers or mobile apps.

---

## Request

```http
POST /api/v1/events HTTP/1.1
Host: errors.goodsorcery.dev
Authorization: Bearer gs_live_9f2c...e81a
Content-Type: application/json
Content-Encoding: gzip              (optional)
User-Agent: goodsorcery-ruby/0.1.0  (recommended)
```

| Header | Required | Notes |
|---|---|---|
| `Authorization` | yes | `Bearer` followed by the project key. Keys start with `gs_live_` (production) or `gs_test_` (other environments). |
| `Content-Type` | yes | Must be `application/json`. |
| `Content-Encoding` | no | `gzip` is supported. |
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
| `transaction` | string | What was running: `Controller#action`, a job class, or a rake task name. |
| `exception.class` | string | **Required**, 1–255 chars. |
| `exception.message` | string | Up to 10,000 chars. |
| `exception.backtrace[]` | array of frames | Innermost first. `file` (string, app-relative paths preferred), `line` (integer), `method` (string), `in_app` (boolean, optional: the server infers it from `app/`, `lib/` and `config/` paths), `context` (`start_line` plus up to 11 `lines`), and `locals` (string to string, up to 25). |
| `request` | object | `url`, `method`, `format`, `request_id`, `remote_ip`, and the nested objects `params`, `headers` and `session`. |
| `user` | object | `id`, `email`, `username`, `name`. The server stores identifiers only as keyed hashes for counting and search. The values themselves are kept encrypted with the event. |
| `breadcrumbs[]` | array | `timestamp` (ISO 8601), `category` (`request`, `controller`, `sql`, `http`, `cache`, `log`, `job`, `custom`; other values become `custom`), `level` (`debug`, `info`, `warning`, `error`), `message`, and `data` (object). The most recent 100 are kept. |
| `context` | object | Free-form runtime details shown on the Environment tab. Use `runtime.ruby` and `runtime.rails` to label the project, and `host` to add a `host` tag automatically. |
| `tags` | object | String keys matching `/\A[a-z0-9_.\-]{1,32}\z/i` mapped to scalar values. Up to 25 pairs. Shown as distribution bars on the issue page. |
| `fingerprint` | array of strings | Optional custom grouping. Events with the same fingerprint array are grouped into one issue. Up to 10 strings, 200 chars each. |
| `notifier` | object | `name` and `version` of the client library. |

### Grouping

Without a custom `fingerprint`, events are grouped by:

1. the exception class plus the file and method of the **top in-app frame** (line numbers are ignored, so editing the file doesn't split the issue); or
2. if there is no in-app frame, the exception class plus the message with numbers, ids, emails, IPs and tokens normalised.

A resolved issue that receives a new event becomes **unresolved and regressed**.

## Privacy and scrubbing

Scrub as much as you can **in the client**. The Ruby gem applies `Rails.application.config.filter_parameters` before sending. The server scrubs again as a second layer of defence:

- Values under keys that match `password`, `secret`, `token`, `api_key`, `access_key`, `private_key`, `authorization`, `cookie`, `csrf`, `xsrf`, `credit_card`, `card_number`, `cvv`, `cvc`, `ssn`, `otp` or `session_id` (plus each project's extra scrub keys) become `"[FILTERED]"`.
- Card-shaped numbers that pass the Luhn check, `Bearer …` credentials, JWT-like strings, and sensitive URL query parameters are replaced with `[FILTERED]` inside any string.
- Everything captured (backtraces, code context, locals, request, params, headers, session, user, breadcrumbs, context and tag values) is stored **encrypted at rest**. The searchable issue title is a redacted copy of the message (emails, IPs, UUIDs, numbers and tokens are replaced with placeholders).

## Responses

| Status | Body | Meaning |
|---|---|---|
| `202 Accepted` | `{"id":"0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1"}` | Stored and queued for processing. |
| `400 Bad Request` | `{"error":"invalid_json"}` | The body is not valid JSON. |
| `401 Unauthorized` | `{"error":"invalid_api_key"}` | Missing, malformed, unknown or rotated key. |
| `413 Payload Too Large` | `{"error":"payload_too_large"}` | Body over 512 KiB (compressed or decompressed). |
| `415 Unsupported Media Type` | `{"error":"unsupported_media_type"}` | `Content-Type` is not `application/json`. |
| `422 Unprocessable Entity` | `{"error":"invalid_payload","messages":["exception.class is required"]}` | Valid JSON with the wrong shape. |
| `429 Too Many Requests` | `{"error":"rate_limited"}` | Includes a `Retry-After` header in seconds. |

Clients should retry `429` and `5xx` responses with backoff, reusing the same `event_id`. They should not retry `400`, `401`, `413`, `415` or `422`.

## Limits

| Item | Limit |
|---|---|
| Request body | 512 KiB, compressed and decompressed |
| Rate | 1,200 requests/minute per API key; 6,000 requests/minute per IP |
| Exception message | 10,000 chars |
| Backtrace | first 250 frames; context ≤ 11 lines of ≤ 500 chars; ≤ 25 locals of ≤ 500 chars |
| Breadcrumbs | last 100; message ≤ 1,000 chars; `data` ≤ 20 keys |
| Tags | 25 pairs; value ≤ 200 chars |
| `request`, `params`, `headers`, `session`, `context` | nesting depth ≤ 6; arrays ≤ 50 items; objects ≤ 100 keys; strings ≤ 4,096 chars |
| User fields | 255 chars each |

Oversized values are truncated rather than rejected. Only an oversized request body is rejected (413).

## Example with curl

```sh
curl -sS https://errors.goodsorcery.dev/api/v1/events \
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
gzip -c event.json | curl -sS https://errors.goodsorcery.dev/api/v1/events \
  -H "Authorization: Bearer $GOODSORCERY_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Content-Encoding: gzip" \
  --data-binary @-
```

## Operating (self-hosted)

- Events are processed by Sidekiq on the `ingest` queue, with weights `ingest: 3`, `default: 2`, `mailers: 1`.
- Run `bin/rails goodsorcery:prune` daily (cron or a Kamal accessory). It deletes occurrences older than each project's retention period (default 90 days) and hourly rollups older than 90 days. Each issue keeps at most its newest 1,000 occurrences.
- `bin/rails goodsorcery:requeue_stale` re-enqueues events that were accepted but have not been processed after 10 minutes (for example after a Redis outage).
- Production needs the Active Record encryption keys, either in credentials (`active_record_encryption.primary_key`, `deterministic_key`, `key_derivation_salt`) or as the env vars `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`. Generate them with `bin/rails db:encryption:init`. Losing them makes stored events unreadable.
