# Presentation for the issue detail page (slice F): hero, chart, occurrence
# navigator and backtrace. Breadcrumbs, context tabs, tags and activity have
# their own helpers; captured values render through CapturedDataHelper.
#
# Everything here may touch decrypted occurrence data, so it only ever builds
# escaped tags (tag.span / safe_join): never raw, html_safe or sanitize, and
# nothing here is ever cached.
module IssueDetailHelper
  QUOTED_CODE = /(`[^`'\n]{1,80}['`])/
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
    when CapturedDataHelper::FILTERED then "text-ink-400"
    when "nil" then "text-coral-300"
    else "text-mint-300"
    end
  end
end
