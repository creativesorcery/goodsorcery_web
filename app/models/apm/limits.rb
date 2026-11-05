# Bounds for the performance ingest endpoints (docs/INGEST_API.md ›
# Performance monitoring and › Limits). Payloads over the structural limits
# are rejected whole (422); oversized strings are truncated.
module Apm::Limits
  METRICS_BODY_BYTES = 512.kilobytes
  TRACES_BODY_BYTES = 2.megabytes

  MINUTES = 1..5
  TRANSACTIONS_PER_MINUTE = 1..1_000
  TRACES = 1..50
  SPANS = 300

  # Accepted time windows, relative to the server clock when processed.
  METRICS_PAST = 24.hours
  TRACES_PAST = 2.hours
  FUTURE = 2.minutes

  NAME = 255
  HTTP_METHOD = 16
  ROUTE = 255
  ADAPTER = 32
  QUEUE = 128
  SOURCE = 500
  SQL = 2_000
  SPAN_NAME = 255
  PATH = 1_024
  REQUEST_ID = 128
  HOST = 255
  PROCESS = 255
  VERSION = 64
  TEMPLATE = 255
  FILE = 500
  METHOD_NAME = 255
  CONTEXT_LINES = 5
  CONTEXT_LINE = 200

  # Requests, not data points: a gem process sends at most two a minute.
  RATE_PER_IP = 6_000
  RATE_PER_KEY = 600
  RATE_PER_ACCOUNT = 3_000
  RATE_WINDOW = 1.minute
  RATE_SCOPE = "api/v1/apm".freeze
end
