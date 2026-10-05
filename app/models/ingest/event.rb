# A normalised, bounded and scrubbed error event, built from the raw JSON body
# of an InboundEvent. Readers feed the issue summary columns, rollups and the
# encrypted occurrence payload (`to_payload_json`, ARCHITECTURE.md §3.3).
class Ingest::Event
  USER_FIELDS = %w[id email username name].freeze

  attr_reader :project, :environment, :received_at

  def self.from_json(json, project:, environment:, received_at:)
    data = JSON.parse(json.to_s)
    raise Ingest::MalformedPayload, cause: nil unless Ingest::Event.usable?(data)

    new(data, project:, environment:, received_at:)
  rescue JSON::ParserError, EncodingError
    raise Ingest::MalformedPayload, cause: nil
  end

  def self.usable?(data)
    data.is_a?(Hash) && data["exception"].is_a?(Hash) && data["exception"]["class"].to_s.strip.present?
  end

  def initialize(data, project:, environment:, received_at:)
    @data, @project, @environment, @received_at = data, project, environment, received_at
    @scrubber = Ingest::Scrubber.new(extra_keys: project.scrub_fields)
  end

  def exception_class
    @exception_class ||= text(exception["class"], Ingest::Limits::EXCEPTION_CLASS).squish
  end

  def message
    @message ||= @scrubber.scrub_text(text(exception["message"], Ingest::Limits::MESSAGE))
  end

  def redacted_message
    @redacted_message ||= Ingest::MessageRedactor.new.redact(message)
  end

  def frames
    @frames ||= Array(exception["backtrace"]).grep(Hash).first(Ingest::Limits::FRAMES)
      .map { |frame| Ingest::Frame.from_hash(frame, scrubber: @scrubber) }
  end

  def top_app_frame = frames.find(&:in_app?)

  def culprit
    (top_app_frame || frames.first)&.location&.then { text(it, Ingest::Limits::CULPRIT) }.presence
  end

  def transaction_name
    @transaction_name ||= @scrubber.scrub_text(text(@data["transaction"], Ingest::Limits::TRANSACTION)).squish.presence
  end

  def level = Issue::LEVELS.include?(@data["level"]) ? @data["level"] : "error"

  def occurred_at
    @occurred_at ||= Ingest::Timestamp.clamp(Ingest::Timestamp.parse(@data["occurred_at"]), received_at:)
  end

  def release = text(@data["release"], Ingest::Limits::RELEASE).strip.presence

  def user
    @user ||= hash_at("user").slice(*USER_FIELDS).select { |_, value| value.is_a?(String) || value.is_a?(Numeric) }
      .transform_values { |value| text(value, Ingest::Limits::USER_FIELD) }.compact_blank
  end

  def user_identity = @user_identity ||= Ingest::UserIdentity.new(user)

  def tags
    @tags ||= Ingest::TagSet.new(@data["tags"], environment:, release:, host: context["host"], scrubber: @scrubber).to_h
  end

  def runtime_label = Ingest::RuntimeLabel.new(context["runtime"], api: project.rails_api?).to_s

  def fingerprint
    @fingerprint ||= Ingest::Fingerprint.new(exception_class:, top_app_frame:, redacted_message:,
                                             client_parts: @data["fingerprint"]).digest
  end

  def request = @request ||= Ingest::RequestSection.new(hash_at("request"), scrubber: @scrubber)

  def context = @context ||= bounded(hash_at("context"))

  def breadcrumbs = Ingest::Breadcrumb.list(@data["breadcrumbs"], occurred_at:, scrubber: @scrubber)

  def notifier = hash_at("notifier").slice("name", "version").transform_values { text(it, Ingest::Limits::SHORT_FIELD) }

  def to_payload_json = Ingest::Payload.new(self).to_json

  private
    def exception = @data["exception"]

    def hash_at(key) = @data[key].is_a?(Hash) ? @data[key] : {}

    def bounded(value) = @scrubber.scrub(Ingest::TreeLimiter.new.limit(value))

    def text(value, max)
      value.is_a?(String) || value.is_a?(Numeric) ? Ingest::TreeLimiter.truncate(value, max) : ""
    end
end
