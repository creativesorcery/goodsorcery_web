# The issue page's context tabs (request, params, headers, session, job,
# environment) and affected-user card. Decrypted occurrence data: escaped
# tags only (see CapturedDataHelper).
module IssueContextHelper
  TABS = { "request" => "Request", "params" => "Params", "headers" => "Headers",
           "session" => "Session", "job" => "Job", "environment" => "Environment" }.freeze

  JOB_ROWS = { "framework" => "Framework", "class" => "Job class", "mailer" => "Mailer", "action" => "Mailer action",
               "id" => "Job ID", "provider_job_id" => "Provider job ID", "queue" => "Queue", "priority" => "Priority",
               "executions" => "Executions", "retry_count" => "Retry count", "enqueued_at" => "Enqueued at",
               "scheduled_at" => "Scheduled at" }.freeze
  JOB_FRAMEWORKS = { "active_job" => "Active Job", "sidekiq" => "Sidekiq" }.freeze

  # The tab shown first: Job for an error raised in a job outside any request.
  def initial_context_tab(occurrence)
    occurrence.request.empty? && occurrence.job.any? ? "job" : "request"
  end

  def context_panel(id, selected, &)
    tag.div(id: "context-#{id}", role: "tabpanel", aria: { labelledby: "context-tab-#{id}" },
            data: { tabs_target: "panel" }, hidden: id != selected, &)
  end

  # [label, value, extra class] rows for the Request tab; blanks are skipped.
  # No request section means no rows (a job's transaction is not a controller).
  def request_rows(occurrence)
    request = occurrence.request
    return [] if request.empty?

    [ [ "URL", request["url"] ], [ "Method", request["method"] ],
      [ "Controller", occurrence.transaction_name, "text-lilac-300" ], [ "Format", request["format"] ],
      [ "Request ID", request["request_id"] ], [ "Remote IP", request["remote_ip"] ] ].select { |row| row[1].present? }
  end

  # [label, value, extra class] rows for the Job tab, in JOB_ROWS order; blanks are skipped.
  def job_rows(occurrence)
    occurrence.job.slice(*JOB_ROWS.keys).filter_map do |key, value|
      [ JOB_ROWS[key], job_value(key, value), ("text-lilac-300" if key == "class") ] if value.present?
    end
  end

  # The job's arguments: an array, or an object for mailer params.
  def job_arguments(occurrence)
    arguments = occurrence.job["arguments"]
    arguments.is_a?(Array) || arguments.is_a?(Hash) ? arguments : []
  end

  # Nested context flattened to dotted keys: { "runtime.ruby" => "3.4.1", … }
  def flatten_context(hash, prefix = nil)
    hash.each_with_object({}) do |(key, value), flat|
      path = [ prefix, key ].compact.join(".")
      nested = value.is_a?(Hash) && value.any?
      nested ? flat.merge!(flatten_context(value, path)) : flat.store(path, value)
    end
  end

  def affected_user_name(user)
    user["name"].presence || user["username"].presence || user["email"].to_s.split("@").first.presence || "Anonymous user"
  end

  # "id 5521 · mara@…": the email domain is never shown.
  def affected_user_identity(user)
    local = user["email"].to_s.split("@").first
    [ ("id #{user['id']}" if user["id"].present?), ("#{local}@…" if local.present?) ].compact.join(" · ")
  end

  private
    def job_value(key, value)
      key == "framework" ? JOB_FRAMEWORKS.fetch(value, value) : value
    end
end
