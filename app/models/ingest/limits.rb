# Hard bounds for everything accepted by the ingest API (docs/INGEST_API.md › Limits).
# Oversized values are truncated; only an oversized request body is rejected.
module Ingest::Limits
  BODY_BYTES = 512.kilobytes

  EXCEPTION_CLASS = 255
  MESSAGE = 10_000
  TITLE = 1_024
  CULPRIT = 500

  FRAMES = 250
  FRAME_FILE = 1_024
  FRAME_METHOD = 255
  CONTEXT_LINES = 11
  CONTEXT_LINE = 500
  LOCALS = 25
  LOCAL_VALUE = 500

  BREADCRUMBS = 100
  BREADCRUMB_MESSAGE = 1_000
  BREADCRUMB_DATA_KEYS = 20

  TAGS = 25
  TAG_KEY = /\A[a-z0-9_.\-]{1,32}\z/i
  TAG_VALUE = 200

  DEPTH = 6
  ARRAY_ITEMS = 50
  HASH_KEYS = 100
  STRING = 4_096
  KEY = 200

  USER_FIELD = 255
  FINGERPRINT_PARTS = 10
  FINGERPRINT_PART = 200
  RELEASE = 64
  TRANSACTION = 255
  SHORT_FIELD = 128

  RATE_PER_KEY = 1_200
  RATE_PER_IP = 6_000
  RATE_PER_ACCOUNT = 6_000
  RATE_WINDOW = 1.minute
end
