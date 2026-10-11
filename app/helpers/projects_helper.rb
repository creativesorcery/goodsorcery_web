# Projects overview cards, the recent feed and project settings.
module ProjectsHelper
  HEALTH_CHIPS = {
    listening: [ "Listening…", :muted ],
    all_clear: [ "✦ All clear", :mint ],
    spiking: [ "Spiking", :coral ],
    steady: [ "Steady", :iris ]
  }.freeze

  CARD_RISES = [ "rise rise-1", "rise rise-2", "rise rise-3", "rise rise-4", "rise rise-5" ].freeze

  PING_SIZES = { sm: "w-3 h-3", md: "w-3.5 h-3.5", lg: "w-5 h-5" }.freeze

  FEED_DOTS = {
    regressed: "w-[7px] h-[7px] shrink-0 rounded-full bg-lilac-400",
    seen: "w-[7px] h-[7px] shrink-0 rounded-full bg-coral-500",
    resolved: "w-[7px] h-[7px] shrink-0 rounded-full bg-mint-400"
  }.freeze

  def project_health_chip(health)
    label, tone = HEALTH_CHIPS.fetch(health.status)
    chip label, tone:, dot: health.spiking?
  end

  # Events per day stacked by environment, each in its colour (production at
  # the bottom). With no events in the window, a flat line in the health colour.
  def project_sparkline(card)
    layers = card.series_by_environment.map { |name, values| { values:, color: environment_color(name) } }
    return sparkline_svg(card.daily_series, color: project_sparkline_color(card.health), width: 140, height: 44) if layers.empty?

    stacked_sparkline_svg layers, width: 140, height: 44
  end

  # "9 production · 3 staging", each count and name in its environment's colour.
  def project_environment_breakdown(card)
    parts = card.unresolved_by_environment.map do |name, count|
      tag.span safe_join([ environment_dot(name), "#{delimited(count)} #{name}" ], " "),
        class: "inline-flex items-center gap-1 #{environment_text_classes(name)}"
    end
    safe_join parts, tag.span("·", class: "text-paper-500") if parts.any?
  end

  # Coral when spiking, mint when all clear, iris otherwise.

  def project_sparkline_color(health)
    return ChartHelper::CORAL if health.spiking?

    health.all_clear? ? ChartHelper::MINT : ChartHelper::IRIS
  end

  # "unresolved · 4 new" (coral when any) or "unresolved · 12 days clean".
  def project_card_caption(card)
    detail = card.health.all_clear? ? "#{pluralize(card.health.days_clean, 'day')} clean" : project_new_count(card.new_count)
    safe_join [ "unresolved · ", detail ]
  end

  def project_new_count(count)
    count.positive? ? tag.span("#{delimited(count)} new", class: "text-coral-300") : "0 new"
  end

  # Listening projects go to setup; the rest to their issues.
  def project_card_destination(card)
    card.health.listening? ? project_setup_path(card.project) : project_issues_path(card.project)
  end

  def project_card_subtitle(card)
    card.health.listening? ? "Created #{time_ago_compact(card.project.created_at)}" : project_runtime_label(card.project)
  end

  def project_last_error_label(card)
    card.last_seen_at ? "last error #{time_ago_compact(card.last_seen_at)}" : "no errors yet"
  end

  def project_card_rise(index)
    CARD_RISES.fetch(index + 1, CARD_RISES.last)
  end

  # Pinging iris dot shown while a project waits for its first event.
  def listening_ping(size = :sm)
    box = PING_SIZES.fetch(size)
    tag.span class: "relative flex shrink-0 #{box}", "aria-hidden": true do
      tag.span(class: "absolute inset-0 rounded-full bg-iris-400/50 animate-ping") +
        tag.span(class: "relative rounded-full bg-iris-400 #{box}")
    end
  end

  # Coral pulse for new, lilac for regressed, solid coral otherwise, mint for resolved.
  def recent_entry_dot(entry)
    return tag.span(class: "coral-dot") if entry.kind == :new

    tag.span class: FEED_DOTS.fetch(entry.kind)
  end

  # "Pundit::NotAuthorizedError in RefundsController#create — by Jo M."
  def recent_resolution_summary(entry)
    issue = entry.issue
    summary = [ issue.exception_class, ("in #{issue.transaction_name}" if issue.transaction_name.present?) ].compact.join(" ")
    entry.user ? "#{summary} — by #{short_person_name(entry.user)}" : summary
  end

  def short_person_name(user)
    first, *rest = user.name.to_s.split
    [ first, rest.last&.first&.then { |initial| "#{initial}." } ].compact.join(" ")
  end

  def platform_options
    Project.platforms.keys.map { |platform| [ platform_label(platform), platform ] }
  end

  # The saved name, so a rejected rename doesn't leak into breadcrumbs.
  def project_crumb_label(project)
    project.persisted? ? project.name_in_database : project.name
  end
end
