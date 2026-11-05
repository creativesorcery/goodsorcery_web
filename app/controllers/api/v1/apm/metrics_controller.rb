# POST /api/v1/apm/metrics: one process's per-minute transaction histograms
# (docs/INGEST_API.md › Metrics payload). The checks live in ApmIngestEndpoint.
class Api::V1::Apm::MetricsController < ActionController::API
  include ApmIngestEndpoint

  def create
    accept_batch(::Apm::MetricsEnvelope, kind: "metrics", max: ::Apm::Limits::METRICS_BODY_BYTES)
  end
end
