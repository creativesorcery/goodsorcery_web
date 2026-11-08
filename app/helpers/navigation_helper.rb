module NavigationHelper
  Crumb = Data.define(:label, :path)

  SWITCHER_LIMIT = 50
  NAV_BADGE_CLASSES = "text-[11px] font-mono border rounded px-1.5".freeze
  ALL_ENVIRONMENTS_BADGE = "text-coral-300 bg-coral-500/10 border-coral-500/20".freeze
  # Running monitors that are down, per project, read with the switcher list
  # so the sidebar's Uptime dot costs no query of its own.
  DOWN_MONITORS_SQL = "(SELECT COUNT(*) FROM uptime_monitors WHERE uptime_monitors.project_id = projects.id " \
    "AND uptime_monitors.status = 'down' AND uptime_monitors.paused_at IS NULL)".freeze

  # In a view: <% breadcrumb Current.account.name, projects_path %> … <% breadcrumb "Issues" %>
  def breadcrumb(label, path = nil)
    breadcrumbs << Crumb.new(label:, path:)
    nil
  end

  def breadcrumbs
    @breadcrumbs ||= []
  end

  # Sidebar link; aria-current="page" when the view did `provide :nav, key`.
  def nav_link_to(label, path, key:, icon:, badge: nil)
    link_to path, class: "nav-link", aria: { current: ("page" if current_nav?(key)) } do
      safe_join([ icon(icon), tag.span(label, class: "flex-1"), badge ].compact)
    end
  end

  # A non-link sidebar row (Issues, Alerts, Uptime before any app exists).
  def nav_placeholder(label, icon:, note: nil)
    note_tag = note && tag.span(note, class: "text-[10px] uppercase tracking-wider text-ink-400/60")
    tag.span class: "nav-link", aria: { disabled: true } do
      safe_join([ icon(icon), tag.span(label, class: "flex-1"), note_tag ].compact)
    end
  end

  # Unresolved count, tinted in the tone of the environment it counts (coral
  # across all environments); the title says which.
  def nav_badge(count, environment: nil)
    return if count.to_i.zero?

    tone = environment ? environment_bar_classes(environment) : ALL_ENVIRONMENTS_BADGE
    scope = environment ? "in #{environment}" : "across all environments"
    tag.span compact_count(count), class: "#{NAV_BADGE_CLASSES} #{tone}", title: "#{delimited(count)} unresolved #{scope}"
  end

  def current_nav?(key)
    content_for(:nav).to_s == key.to_s
  end

  # The project the sidebar is about: the page's project, else the one last
  # viewed (ProjectScoped remembers it), else the most recently active one.
  def sidebar_project
    return @sidebar_project if defined?(@sidebar_project)

    @sidebar_project = @project.try(:persisted?) ? @project : remembered_project || most_recently_active_project
  end

  # Switcher list: one query, including each project's latest issue activity.
  def sidebar_projects
    return [] unless Current.account

    @sidebar_projects ||= Current.account.projects.order(:name).limit(SWITCHER_LIMIT)
      .select("projects.*", "#{ProjectOverview::LAST_SEEN_SQL} AS last_issue_seen_at", "#{DOWN_MONITORS_SQL} AS down_monitors_count").to_a
  end

  # Every app of the account, counted from the switcher list unless that
  # was cut short at SWITCHER_LIMIT.
  def account_project_count
    projects = sidebar_projects
    projects.size < SWITCHER_LIMIT ? projects.size : Current.account.projects.count
  end

  def remembered_project
    id = session[:last_project_id]
    return unless id && Current.account

    sidebar_projects.find { |project| project.id == id } || Current.account.projects.find_by(id:)
  end

  # From the switcher's own query (no extra one); ties keep name order.
  def most_recently_active_project
    sidebar_projects.min_by.with_index { |project, index| [ -project.last_issue_seen_at.to_i, index ] }
  end

  # "staging · Rails 8.0 · Ruby 3.4": the environment the project's issue list
  # shows (and the badge counts), in its tone, or "all environments".
  def sidebar_project_subtitle(project)
    environment = issues_environment_for(project)
    scope = environment ? environment_text(environment) : tag.span("all environments", class: "text-ink-400")
    safe_join [ scope, project_runtime_label(project) ].compact, " · "
  end

  def sidebar_issues_badge
    nav_badge sidebar_unresolved_count, environment: issues_environment_for(sidebar_project)
  end

  # A coral dot when any running monitor of the sidebar project is down, titled "2 down".
  def sidebar_uptime_badge
    count = sidebar_down_monitors_count
    return if count.zero?

    tag.span class: "coral-dot", role: "img", title: "#{count} down", "aria-label": "#{count} down"
  end

  # From the switcher's query; one count query only when the project isn't in that list.
  def sidebar_down_monitors_count
    return 0 unless sidebar_project

    listed = sidebar_projects.find { |project| project.id == sidebar_project.id }
    listed ? listed.down_monitors_count.to_i : sidebar_project.uptime_monitors.active.down.count
  end

  # Badge count for the environment the project's issue list shows
  # (RemembersEnvironment): a number only, cached briefly (never any issue text).
  def sidebar_unresolved_count
    return 0 unless sidebar_project

    sidebar_project.cached_unresolved_count(issues_environment_for(sidebar_project))
  end

  # "Acme Labs · Hosted" / "Acme Labs · Self-hosted"
  def account_plan_label(account)
    [ account&.name, hosted? ? "Hosted" : "Self-hosted" ].compact.join(" · ")
  end

  # Keeps the global box filled in on the search results page only.
  def global_search_query
    params[:q] if controller_name == "searches"
  end

  # Signed, authorised Turbo Stream subscription (AuthorizedStreamsChannel, slice G).
  def live_stream_from(*streamables)
    turbo_stream_from(*streamables, channel: "AuthorizedStreamsChannel")
  end
end
