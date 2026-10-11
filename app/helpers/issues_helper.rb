# Issue list rows: tone (new / regressed / steady), stripes, chips, histograms.
# Issue text is always rendered through ERB escaping.
module IssuesHelper
  ROW_GRID = "grid grid-cols-[28px_1fr_150px_90px_90px_110px_44px] items-center gap-4".freeze
  CLASS_NAME_TONES = { new: "text-coral-300", regressed: "text-lilac-300", steady: "text-ink-100" }.freeze
  EDGE_STRIPES = { new: "edge-stripe edge-coral", regressed: "edge-stripe edge-lilac" }.freeze
  HISTOGRAM_COLORS = { new: ChartHelper::CORAL, regressed: ChartHelper::LILAC, steady: ChartHelper::IRIS_SOFT }.freeze
  ROW_ENVIRONMENTS = 3

  def issue_tone(issue)
    return :new if issue.new?
    return :regressed if issue.regressed?

    :steady
  end

  # Rows not seen for over an hour fade back a little.
  def issue_row_classes(issue)
    quiet = issue.last_seen_at < 1.hour.ago ? "opacity-80" : nil
    [ ROW_GRID, "group relative px-5 py-4 border-b border-paper-700/70 hover:bg-iris-500/[.04] transition", quiet ].compact.join(" ")
  end

  # The title block of issues never seen in production fades back, so
  # production issues stand out.
  def issue_summary_classes(issue)
    issue.only_outside_production? ? "min-w-0 opacity-60" : "min-w-0"
  end

  # Small chips for where the issue was seen: the first three, then "+N".
  def issue_environment_chips(issue)
    shown = issue.environments.first(ROW_ENVIRONMENTS).map { |environment| environment_chip(environment, small: true) }
    hidden = issue.environments.size - ROW_ENVIRONMENTS
    shown << chip("+#{hidden}", tone: :muted, small: true) if hidden.positive?
    tag.span safe_join(shown), class: "flex items-center gap-1 shrink-0 font-sans" if shown.any?
  end

  def issue_edge_stripe(issue)
    stripe = EDGE_STRIPES[issue_tone(issue)]
    tag.span(class: stripe, "aria-hidden": true) if stripe
  end

  def issue_class_name(issue)
    tag.span issue.exception_class, class: "font-mono text-[13.5px] font-semibold truncate #{CLASS_NAME_TONES.fetch(issue_tone(issue))}"
  end

  def issue_badge(issue)
    case issue_tone(issue)
    when :new then chip("New", tone: :coral, dot: true)
    when :regressed then chip("↺ Regressed", tone: :lilac)
    end
  end

  def issue_title(issue)
    issue.message.presence || issue.exception_class
  end

  # "CheckoutsController#create • app/services/cart_total.rb:42 in line_total"
  def issue_origin(issue)
    spans = [
      (tag.span(issue.transaction_name, class: "truncate shrink-0 max-w-[50%]") if issue.transaction_name.present?),
      (tag.span(issue.culprit, class: "truncate") if issue.culprit.present?)
    ].compact
    return tag.span("unknown origin", class: "text-ink-400/70") if spans.empty?

    safe_join spans, tag.span("•", class: "text-paper-500")
  end

  # 24 hourly bars; the last (current hour) highlighted for new and regressed issues.
  def issue_histogram(issue, values)
    tone = issue_tone(issue)
    histogram_svg values, color: HISTOGRAM_COLORS.fetch(tone), width: 150, height: 30,
      highlight_last: tone != :steady, titles: hourly_titles(values)
  end

  def issue_assignee_avatar(issue)
    issue.assignee ? initials_avatar(issue.assignee.name, size: :md) : empty_avatar(size: :md)
  end

  # "▲ 34% vs. prev. day" (coral) / "▼ 8% vs. prev. day" (mint) under the events count.
  def summary_change(summary)
    change = summary.events_change
    text, tone = summary_change_parts(change, summary.period.comparison)
    tag.div text, class: "text-[12px] mt-2 #{tone}"
  end

  private
    def summary_change_parts(change, comparison)
      return [ "No events in the #{comparison}", "text-ink-400" ] if change.nil?
      return [ "▲ #{change}% vs. #{comparison}", "text-coral-300" ] if change.positive?
      return [ "▼ #{change.abs}% vs. #{comparison}", "text-mint-300" ] if change.negative?

      [ "No change vs. #{comparison}", "text-ink-400" ]
    end

    # "14:00 · 3 events" in the viewer's time zone.
    def hourly_titles(values)
      from = TimeSeries.window_start(1.hour, values.size)
      values.each_with_index.map do |count, index|
        "#{(from + index.hours).in_time_zone.strftime('%H:%M')} · #{pluralize(delimited(count), 'event')}"
      end
    end
end
