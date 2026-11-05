# POST /api/v1/apm/traces: timelines of the slowest request per transaction
# per minute (docs/INGEST_API.md › Traces payload). The checks live in
# ApmIngestEndpoint.
class Api::V1::Apm::TracesController < ActionController::API
  include ApmIngestEndpoint

  def create
    accept_batch(::Apm::TracesEnvelope, kind: "traces", max: ::Apm::Limits::TRACES_BODY_BYTES)
  end
end
