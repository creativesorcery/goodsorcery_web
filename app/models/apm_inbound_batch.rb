# Transient, encrypted copy of an accepted performance payload
# (docs/ARCHITECTURE.md §13.3). Only its integer id is handed to
# ProcessApmBatchJob, so no payload bytes reach Redis; the body is cleared
# once processed. [project_id, kind, uuid] is unique, so a payload resent
# with the same batch_id is stored and counted once.
class ApmInboundBatch < ApplicationRecord
  KINDS = %w[metrics traces].freeze
  KEPT_FOR = 1.day

  belongs_to :project, inverse_of: :apm_inbound_batches

  encrypts :body

  validates :kind, inclusion: { in: KINDS }

  # One INSERT … ON CONFLICT DO NOTHING RETURNING id for an authenticated
  # key; insert_all casts through the attribute types, so the body is
  # encrypted exactly as with save. Returns the new id, or nil for a batch
  # already received.
  def self.store(credential, kind:, uuid:, body:, received_at: Time.current)
    row = { project_id: credential.project_id, environment: credential.environment, kind:, uuid:, body:, received_at: }
    insert_all([ row ], unique_by: %i[project_id kind uuid], returning: :id).rows.dig(0, 0)
  end

  def metrics? = kind == "metrics"

  def processed? = processed_at.present?
end
