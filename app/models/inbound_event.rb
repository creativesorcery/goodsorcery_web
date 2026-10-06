# Transient, encrypted copy of an accepted ingest request body. Only its id is
# handed to the job queue, so no payload bytes ever reach Redis.
class InboundEvent < ApplicationRecord
  belongs_to :project
  belongs_to :api_key

  encrypts :body

  attribute :received_at, :datetime, default: -> { Time.current }

  scope :stale, -> { where(received_at: ...10.minutes.ago) }

  class << self
    # Stores the events of one request for an authenticated key: one INSERT
    # (multi-row for a batch), with no validation queries because every id
    # comes from the key. insert_all casts through the attribute types, so
    # bodies are encrypted exactly as with save. Returns id-only records,
    # which is all ProcessInboundEventJob needs.
    def store_for(credential, events, received_at: Time.current)
      rows = events.map { |event_uuid, body| row_for(credential, event_uuid, body, received_at) }
      insert_all!(rows, returning: :id).map { instantiate(it) }
    end

    private
      def row_for(credential, event_uuid, body, received_at)
        { project_id: credential.project_id, api_key_id: credential.id, environment: credential.environment,
          event_uuid:, body:, received_at: }
      end
  end
end
