# Transient, encrypted copy of an accepted ingest request body. Only its id is
# handed to the job queue, so no payload bytes ever reach Redis.
class InboundEvent < ApplicationRecord
  belongs_to :project
  belongs_to :api_key

  encrypts :body

  attribute :received_at, :datetime, default: -> { Time.current }

  scope :stale, -> { where(received_at: ...10.minutes.ago) }
end
