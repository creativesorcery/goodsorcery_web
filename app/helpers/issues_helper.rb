# Issue list rows: tone (new / regressed / steady), stripes, chips, histograms.
# Issue text is always rendered through ERB escaping.
module IssuesHelper
  # The Last 24h histogram column shows from xl up, so the issue column keeps
  # a usable width on narrower screens. Below md a row is a card: checkbox and
  # issue only, with the counts on a line under the title (ROW_META);
  # md has narrower metric columns than lg.
  ROW_GRID = "grid grid-cols-[28px_minmax(0,1fr)] md:grid-cols-[28px_minmax(0,1fr)_64px_56px_92px_32px] " \
    "lg:grid-cols-[28px_1fr_90px_90px_110px_44px] xl:grid-cols-[28px_1fr_150px_90px_90px_110px_44px] " \
    "items-center gap-x-3 gap-y-4 md:gap-4".freeze
  HISTOGRAM_CELL = "hidden xl:block".freeze
  # Columns that only show as columns from md (the card line covers them below).
  METRIC_CELL = "max-md:hidden".freeze
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
    [ ROW_GRID, "group relative px-4 sm:px-5 py-4 border-b border-paper-700/70 hover:bg-iris-500/[.04] transition", quiet ].compact.join(" ")
  end

  # Titles of issues never seen in production are drawn in a softer ink, so
  # production issues stand out. Colour rather than opacity keeps the text
  # readable and leaves the row's quick actions at full strength.
  def issue_title_classes(issue)
    tone = issue.only_outside_production? ? "text-ink-300" : "text-ink-50"
    "block text-[14.5px] #{tone} truncate mt-0.5 after:absolute after:inset-0 focus:outline-none"
  end

  # Small chips for where the issue was seen: the first three, then "+N".
  def issue_environment_chips(issue)
    shown = issue.environments.first(ROW_ENVIRONMENTS).map { |environment| environment_chip(environment, small: true) }
    hidden = issue.environments.size - ROW_ENVIRONMENTS
    shown << chip("+#{hidden}", tone: :muted, small: true) if hidden.positive?
    tag.span safe_join(shown), class: "flex items-center gap-1 shrink-0 font-sans" if shown.any?
  end

  # Small coral marker for an issue that escaped to production after being
  # seen only elsewhere; the title says when.
  def issue_reached_production_chip(issue, small: true)
    return unless issue.reached_production?

    tag.span chip("▲ Reached production", tone: :coral, small:), class: "shrink-0",
      title: "First seen in production #{time_ago_compact(issue.reached_production_at)}"
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
      (tag.span(issue.culprit, class: "truncate min-w-0") if issue.culprit.present?)
    ].compact
    return tag.span("unknown origin", class: "truncate text-ink-400/70") if spans.empty?

    safe_join spans, tag.span("•", class: "text-paper-500")
  end

  # 24 hourly bars; the last (current hour) highlighted for new and regressed issues.
  def issue_histogram(issue, values)
    tone = issue_tone(issue)
    chart = histogram_svg values, color: HISTOGRAM_COLORS.fetch(tone), width: 150, height: 30,
      highlight_last: tone != :steady, titles: hourly_titles(values)
    tag.div chart, class: HISTOGRAM_CELL
  end

  def issue_assignee_avatar(issue, size: :md)
    issue.assignee ? initials_avatar(issue.assignee.name, size:) : empty_avatar(size:)
  end

  # The card line under a row's title below md: "1,284 events · 212 users · 4d ago".
  def issue_card_meta(issue)
    parts = [ pluralize(delimited(issue.events_count), "event"), pluralize(delimited(issue.users_count), "user"),
              "seen #{time_ago_compact(issue.last_seen_at)}" ]
    tag.div class: "md:hidden mt-2 flex items-center gap-2 text-[12px] text-ink-300" do
      safe_join([ tag.span(parts.join(" · "), class: "min-w-0 truncate"), (issue_assignee_avatar(issue, size: :sm) if issue.assignee) ].compact)
    end
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
