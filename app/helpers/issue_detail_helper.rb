# Presentation for the issue detail page (slice F).
#
# Everything here may touch decrypted occurrence data, so it only ever builds
# escaped tags (tag.span / safe_join): never raw, html_safe or sanitize, and
# nothing here is ever cached.
module IssueDetailHelper
  FILTERED = "[FILTERED]".freeze
  JSON_TOKENS = /"(?:\\.|[^"\\])*"|-?\d[\d.eE+-]*|true|false|null|[\s{}\[\],:]+|./m
  QUOTED_CODE = /(`[^`'\n]{1,80}['`])/
  BREADCRUMB_FILTERS = %w[sql http log].freeze
  BREADCRUMB_TONES = {
    "sql" => { dot: "bg-lilac-400", chip: "text-lilac-300 border-lilac-400/30" },
    "http" => { dot: "bg-mint-400", chip: "text-mint-300 border-mint-400/30" },
    "log" => { dot: "bg-iris-400", chip: "text-iris-300 border-iris-400/30" }
  }.freeze
  BREADCRUMB_DEFAULT_TONE = { dot: "bg-paper-500", chip: "" }.freeze
  LOUD_LEVELS = { "warning" => "[warn]", "error" => "[error]" }.freeze
  TAG_PALETTE = [ ChartHelper::IRIS, ChartHelper::IRIS_DEEP, ChartHelper::IRIS_SOFT, ChartHelper::LILAC, ChartHelper::MINT ].freeze
  SUSPICIOUS_SHARE = 0.8
  CONTEXT_TABS = { "request" => "Request", "params" => "Params", "headers" => "Headers",
                   "session" => "Session", "environment" => "Environment" }.freeze
  CODE_LINE = {
    true => [ "flex px-4 bg-coral-500/15 border-l-2 border-coral-500 text-ink-50", "w-10 shrink-0 text-right pr-4 text-coral-300 select-none -ml-[2px]" ],
    false => [ "flex px-4 text-ink-400", "w-10 shrink-0 text-right pr-4 text-paper-500 select-none" ]
  }.freeze

  # ── hero ────────────────────────────────────────────────────

  def issue_class_tone(issue)
    issue.new? ? "text-coral-300" : "text-ink-50"
  end

  # The (redacted) message with `quoted' identifiers set in mono iris.
  def issue_message_parts(message)
    parts = message.to_s.split(QUOTED_CODE).map do |part|
      part.match?(QUOTED_CODE) ? tag.span(part[1..-2], class: "font-mono text-[0.82em] text-iris-300 bg-iris-500/10 px-1.5 rounded") : part
    end
    safe_join(parts)
  end

  # "CheckoutsController#create · app/services/cart_total.rb:42 in line_total"
  def issue_location(issue)
    location, _, method_name = issue.culprit.to_s.rpartition(" in ")
    culprit = location.empty? ? issue.culprit : safe_join([ location, " in ", tag.span(method_name, class: "text-ink-200") ])
    safe_join([ issue.transaction_name, culprit ].compact_blank, " · ")
  end

  # Reopening goes through whichever resource put the issue out of the inbox.
  def issue_reopen_path(project, issue)
    issue.ignored? ? project_issue_ignore_path(project, issue) : project_issue_resolution_path(project, issue)
  end

  # Members who can be assigned, for the Resolve ▾ menu (one query).
  def assignable_members
    @assignable_members ||= Current.account.users.order(:name).to_a
  end

  # ── chart ───────────────────────────────────────────────────

  def issue_chart_color(issue)
    return ChartHelper::CORAL if issue.new?
    return ChartHelper::LILAC if issue.regressed?

    ChartHelper::IRIS
  end

  # ── occurrence navigator ────────────────────────────────────

  def occurrence_navigator
    @occurrence_navigator ||= OccurrenceNavigator.new(@issue, occurrence: @occurrence)
  end

  # ‹ / › to a neighbour by uuid; a dimmed, inert button at either end.
  def occurrence_link(label, project, issue, target, aria: {})
    return tag.span(label, class: "btn btn-sm opacity-40", aria: aria.merge(disabled: true)) if target.nil?

    link_to label, project_issue_occurrence_path(project, issue, target), class: "btn btn-sm", aria:
  end

  def occurrence_shortcut_class(navigator, shortcut)
    base = "flex-1 rounded-md py-1 text-center transition"
    navigator.selected_shortcut == shortcut ? "#{base} bg-paper-700 text-ink-50" : "#{base} text-ink-400 hover:bg-paper-800"
  end


  # ── backtrace ───────────────────────────────────────────────

  def occurrence_backtrace(issue, occurrence)
    Backtrace.new(occurrence&.frames, exception_class: issue.exception_class, message: occurrence&.exception_message.to_s)
  end

  # The error line is highlighted coral.
  def code_line_classes(error_line) = CODE_LINE.fetch(error_line == true).first

  def code_number_classes(error_line) = CODE_LINE.fetch(error_line == true).last

  # "item = #<CartItem …>, variant = nil"
  def frame_locals(locals)
    pairs = locals.map do |name, value|
      safe_join([ tag.span(name, class: "font-mono text-ink-200"), " = ",
                  tag.span(context_text(value), class: "font-mono break-all #{local_value_class(value)}") ])
    end
    safe_join(pairs, ", ")
  end

  def local_value_class(value)
    case value.to_s
    when FILTERED then "text-ink-400"
    when "nil" then "text-coral-300"
    else "text-mint-300"
    end
  end

  # ── breadcrumbs ─────────────────────────────────────────────

  # -412 → "−412ms", -1204 → "−1,204ms"
  def breadcrumb_offset(offset_ms)
    milliseconds = offset_ms.to_i
    sign = milliseconds.negative? ? "−" : ""
    "#{sign}#{number_with_delimiter(milliseconds.abs)}ms"
  end

  def breadcrumb_tone(category)
    BREADCRUMB_TONES.fetch(category.to_s, BREADCRUMB_DEFAULT_TONE)
  end

  def breadcrumb_count(breadcrumbs, category)
    breadcrumbs.count { |crumb| crumb["category"].to_s == category }
  end

  def breadcrumb_level_prefix(crumb)
    LOUD_LEVELS[crumb["level"].to_s]
  end

  # sql → the statement; http → "200 · 212ms"; others → "key: value" pairs.
  def breadcrumb_details(crumb)
    data = crumb["data"].is_a?(Hash) ? crumb["data"] : {}
    case crumb["category"].to_s
    when "sql" then data["sql"].to_s
    when "http" then [ data["status"], (data["duration_ms"] && "#{data['duration_ms']}ms") ].compact_blank.join(" · ")
    else data.map { |key, value| "#{key}: #{context_text(value)}" }.join(" · ")
    end
  end

  # ── context tabs ────────────────────────────────────────────

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

  # A scalar from captured data; "[FILTERED]" renders muted.
  def context_value(value, tone: "text-ink-100")
    text = context_text(value)
    tag.span(text, class: text == FILTERED ? "text-ink-400" : tone)
  end

  def context_text(value)
    value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
  end

  # Pretty JSON with token colours, built from escaped spans only.
  def pretty_json(value)
    safe_join(JSON.pretty_generate(value).scan(JSON_TOKENS).map { |token| json_token(token) })
  end

  # ── affected user ───────────────────────────────────────────

  def affected_user_name(user)
    user["name"].presence || user["username"].presence || user["email"].to_s.split("@").first.presence || "Anonymous user"
  end

  # "id 5521 · mara@…": the email domain is never shown.
  def affected_user_identity(user)
    local = user["email"].to_s.split("@").first
    [ ("id #{user['id']}" if user["id"].present?), ("#{local}@…" if local.present?) ].compact.join(" · ")
  end

  def affected_user_hits(issue, occurrence)
    IssueUser.count_for(issue, occurrence.user_digest)
  end

  # ── tags ────────────────────────────────────────────────────

  def suspicious_tag?(key)
    key.distinct_count >= 2 && key.values.first&.share.to_f >= SUSPICIOUS_SHARE
  end

  def tag_segments(key)
    suspicious = suspicious_tag?(key)
    segments = key.values.each_with_index.map do |value, index|
      { share: value.share, color: tag_color(index, suspicious), title: "#{share_percent(value.share)} #{value.value}" }
    end
    segments << { share: tag_remainder(key), color: ChartHelper::PAPER } if tag_remainder(key).positive?
    segments
  end

  def share_percent(share)
    "#{(share.to_f * 100).round}%"
  end

  # ── activity ────────────────────────────────────────────────

  def activity_marker(activity)
    case activity.kind
    when "resolved" then tag.span("✓", class: "text-mint-300")
    when "regressed" then tag.span("↺", class: "text-lilac-300")
    when "note" then tag.span("✎", class: "text-ink-300")
    when "assigned", "unassigned", "reopened" then tag.span("✦", class: "text-iris-400")
    else tag.span("○", class: "text-ink-400")
    end
  end

  # "Philip assigned themselves", "Jo resolved this", "Regressed after being resolved"
  def activity_sentence(activity)
    return "Regressed: seen again after being resolved" if activity.regressed?

    safe_join([ tag.span(activity_actor(activity), class: "text-ink-100"), " ", activity_action(activity) ])
  end

  private
    def json_token(token)
      return tag.span(FILTERED, class: "text-ink-400") if token == "\"#{FILTERED}\""
      return tag.span(token, class: "tok-s") if token.start_with?('"')
      return tag.span(token, class: "tok-n") if token.match?(/\A(-?\d|true|false|null)/)

      token
    end

    def tag_color(index, suspicious)
      return (index.zero? ? ChartHelper::CORAL : ChartHelper::PAPER) if suspicious

      TAG_PALETTE.fetch(index, ChartHelper::IRIS_SOFT)
    end

    def tag_remainder(key)
      (1 - key.values.sum(&:share)).round(4)
    end

    def activity_actor(activity)
      activity.user&.first_name || "A former member"
    end

    def activity_action(activity)
      case activity.kind
      when "assigned" then "assigned #{activity_subject(activity)}"
      when "unassigned" then "unassigned #{activity_subject(activity)}"
      when "note" then "left a note"
      else "#{activity.kind} this"
      end
    end

    def activity_subject(activity)
      return "themselves" if activity.subject_user_id.present? && activity.subject_user_id == activity.user_id

      activity.subject_user&.first_name || "a former member"
    end
end
