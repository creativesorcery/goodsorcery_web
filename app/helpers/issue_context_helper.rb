# The issue page's context tabs (request, params, headers, session,
# environment) and affected-user card. Decrypted occurrence data: escaped
# tags only (see CapturedDataHelper).
module IssueContextHelper
  TABS = { "request" => "Request", "params" => "Params", "headers" => "Headers",
           "session" => "Session", "environment" => "Environment" }.freeze

  # [label, value, extra class] rows for the Request tab; blanks are skipped.
  def request_rows(occurrence)
    request = occurrence.request
    [ [ "URL", request["url"] ], [ "Method", request["method"] ],
      [ "Controller", occurrence.transaction_name, "text-lilac-300" ], [ "Format", request["format"] ],
      [ "Request ID", request["request_id"] ], [ "Remote IP", request["remote_ip"] ] ].select { |row| row[1].present? }
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
end
