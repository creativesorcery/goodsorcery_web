# Shared helpers for the ingest tests (slice C).
module IngestTestSupport
  EVENTS_DIR = Rails.root.join("test/fixtures/files/events")

  # Records broadcast_changes_later calls without changing their behaviour.
  module BroadcastRecorder
    def self.calls = (Thread.current[:ingest_broadcast_calls] ||= [])

    def broadcast_changes_later(**options)
      BroadcastRecorder.calls << [ self.class.name, id, options ] if Thread.current[:ingest_record_broadcasts]
      super
    end
  end
  Issue.prepend(BroadcastRecorder)
  Project.prepend(BroadcastRecorder)

  # The JSON of a sample event file with fresh timestamps and deep-merged overrides.
  def event_json(name = "full", overrides = {})
    template = EVENTS_DIR.join("#{name}.json").read
      .gsub("OCCURRED_AT", 1.minute.ago.utc.iso8601(3)).gsub("CRUMB_AT", 70.seconds.ago.utc.iso8601(3))
    JSON.parse(template).deep_merge(overrides.deep_stringify_keys).to_json
  end

  def minimal_json(overrides = {}) = event_json("minimal", overrides)

  def build_event(json = event_json, project: projects(:storefront), environment: "production", received_at: Time.current)
    Ingest::Event.from_json(json, project:, environment:, received_at:)
  end

  def inbound_event_for(json, key: api_keys(:storefront_production), event_uuid: nil)
    InboundEvent.create!(project_id: key.project_id, api_key_id: key.id, environment: key.environment,
                         event_uuid: event_uuid || Ingest::Envelope.new(json).event_uuid, body: json, received_at: Time.current)
  end

  def process_event(json, **options)
    Ingest::Processor.new(inbound_event_for(json, **options)).process
  end

  def recording_broadcasts
    BroadcastRecorder.calls.clear
    Thread.current[:ingest_record_broadcasts] = true
    yield
    BroadcastRecorder.calls.dup
  ensure
    Thread.current[:ingest_record_broadcasts] = false
  end

  def raw_column(model, column, id)
    model.connection.select_value(model.where(id:).select(column).to_sql)
  end
end
