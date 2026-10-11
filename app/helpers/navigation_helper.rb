module NavigationHelper
  Crumb = Data.define(:label, :path)

  SWITCHER_LIMIT = 50
  FIRST_ENVIRONMENT_SQL = <<~SQL.squish.freeze
    (SELECT api_keys.environment FROM api_keys
     WHERE api_keys.project_id = projects.id ORDER BY api_keys.id LIMIT 1) AS first_environment
  SQL

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

  # A non-link sidebar row, e.g. Alerts / Uptime with a "soon" note.
  def nav_placeholder(label, icon:, note: nil)
    note_tag = note && tag.span(note, class: "text-[10px] uppercase tracking-wider text-ink-400/60")
    tag.span class: "nav-link", aria: { disabled: true } do
      safe_join([ icon(icon), tag.span(label, class: "flex-1"), note_tag ].compact)
    end
  end

  def nav_badge(count)
    return if count.to_i.zero?

    tag.span compact_count(count), class: "text-[11px] font-mono text-coral-300 bg-coral-500/10 border border-coral-500/20 rounded px-1.5"
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

  # Switcher list: one query, including each project's first environment and
  # latest issue activity.
  def sidebar_projects
    return [] unless Current.account

    @sidebar_projects ||= Current.account.projects.order(:name).limit(SWITCHER_LIMIT)
      .select("projects.*", FIRST_ENVIRONMENT_SQL, "#{ProjectOverview::LAST_SEEN_SQL} AS last_issue_seen_at").to_a
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

  # "production · Rails 8.0 · Ruby 3.4", the environment in its tone.
  def sidebar_project_subtitle(project)
    environment = sidebar_projects.find { |item| item.id == project.id }&.first_environment
    safe_join [ (environment_text(environment) if environment), project_runtime_label(project) ].compact, " · "
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
