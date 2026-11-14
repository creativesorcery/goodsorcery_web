# The job part of an event (Active Job, Action Mailer `deliver_later`,
# Sidekiq): known summary fields as bounded, scrubbed strings, plus the job's
# arguments bounded like request params and scrubbed by key. Unknown keys are
# dropped. Stored only in the encrypted occurrence payload.
class Ingest::JobSection
  FIELDS = %w[framework class mailer action id provider_job_id queue priority executions retry_count
              enqueued_at scheduled_at].freeze

  def initialize(job, scrubber:)
    @job, @scrubber = job, scrubber
  end

  # The stored section: the present fields, then `arguments` when any were sent.
  def to_h
    section = summary
    section["arguments"] = arguments if arguments.present?
    section
  end

  def summary
    @job.slice(*FIELDS).select { |_, value| value.is_a?(String) || value.is_a?(Numeric) }
      .transform_values { |value| @scrubber.scrub_text(value, limit: Ingest::Limits::JOB_FIELD) }
      .compact_blank
  end

  # An array (positional arguments) or object (mailer params); anything else is dropped.
  def arguments
    @arguments ||= bounded_arguments if @job["arguments"].is_a?(Array) || @job["arguments"].is_a?(Hash)
  end

  private
    def bounded_arguments
      Ingest::TreeLimiter.new.limit(@scrubber.scrub(@job["arguments"]))
    end
end
