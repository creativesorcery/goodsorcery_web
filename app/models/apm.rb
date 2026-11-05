# Performance monitoring (docs/ARCHITECTURE.md §13). The Apm namespace holds
# the histogram math, the ingest validation and processing objects and the
# query objects behind the Performance pages; the records are the top-level
# Apm* models (ApmTransaction, ApmMinuteStat, ApmHourlyStat, ApmTrace,
# ApmInboundBatch).
module Apm
  # Distinct transaction names kept per app, environment and kind; further
  # names are counted under ApmTransaction::OTHER_NAME.
  MAX_TRANSACTIONS = 500
  # A grouped SQL span repeated this many times in one trace is an N+1.
  N_PLUS_ONE_MIN = 10

  # "Slower": the last hour's p95 is at least SLOWER_RATIO times the past 24
  # hours' p95, with enough requests in both windows to mean something.
  SLOWER_RATIO = 1.5
  SLOWER_MIN_LAST_HOUR = 30
  SLOWER_MIN_PAST_DAY = 100
end
