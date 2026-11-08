# Links and pills for the issue list's query chips, tabs, filters and sort.
module IssueQueryHelper
  TAB_LABELS = {
    "unresolved" => "Unresolved",
    "for_review" => "For review",
    "assigned" => "Assigned to me",
    "ignored" => "Ignored",
    "resolved" => "Resolved"
  }.freeze
  COUNTED_TABS = %w[unresolved for_review assigned].freeze

  # Every list link states its environment, as an env: chip or as a blank env
  # param for all environments, so following it never falls back to a
  # remembered choice or the project's default (EnvironmentChoice).
  def issues_query_path(project, query, sort: IssueList::DEFAULT_SORT, **options)
    project_issues_path(project, q: query.to_s, env: (EnvironmentChoice::ALL unless query.environment),
      sort: (sort unless sort == IssueList::DEFAULT_SORT), **options)
  end

  # One segment of the environment switch: "All" (nil) or an environment.
  def environment_switch_link(project, list, environment)
    current = list.query.environment == environment
    link_to issues_query_path(project, list.query.with_environment(environment), sort: list.sort),
      class: "inline-flex items-center gap-1.5", aria: { current: current.to_s } do
      environment ? safe_join([ environment_dot(environment), environment ]) : "All"
    end
  end

  # The scope bar's way out of a non-production environment: to production
  # when the project has one, otherwise to all environments.
  def environment_scope_exit_link(project, list, choice)
    production = choice.production_environment
    label = production ? "Back to #{production}" : "Show all environments"
    link_to label, issues_query_path(project, list.query.with_environment(production), sort: list.sort),
      class: "font-semibold underline underline-offset-2 hover:opacity-80"
  end

  # Pill with a × link that drops the chip; status chips are iris, environment
  # chips take their environment's tone.
  def issue_query_chip(project, query, chip, sort:)
    key, value = chip.label.split(":", 2)
    remove = link_to "×", issues_query_path(project, query.without_chip(chip), sort:),
      class: "inline-flex items-center justify-center text-ink-400 hover:text-ink-50 max-lg:-my-2 max-lg:-mr-2 max-lg:h-8 max-lg:w-8", "aria-label": "Remove #{chip.label}"
    text = tag.span(safe_join([ "#{key}:", tag.span(value, class: ("text-ink-50" unless chip.key == "env")) ]))
    tag.span safe_join([ text, remove ]), class: "#{query_chip_tone(chip)} font-mono"
  end

  def issue_tab_link(project, list, tab)
    selected = list.query.tab == tab
    link_to issues_query_path(project, list.query.for_tab(tab), sort: list.sort), class: "tab",
      aria: { selected: selected.to_s, current: ("page" if selected) } do
      safe_join [ TAB_LABELS.fetch(tab), issue_tab_count(list, tab) ].compact
    end
  end

  def issue_sort_link(project, list, sort)
    link_to IssueList::SORT_LABELS.fetch(sort), issues_query_path(project, list.query, sort:),
      class: "menu-item", aria: { current: (true if list.sort == sort) }
  end

  # Filters menu entry: swaps in key:value (or drops the key when value is nil).
  def issue_filter_link(project, list, key, value, label: nil)
    query = value ? list.query.with_chip(key, value) : list.query.without_key(key)
    current = list.query.value_of(key) == value
    link_to issues_query_path(project, query, sort: list.sort), class: "menu-item justify-between",
      aria: { current: (true if current) } do
      safe_join [ filter_link_label(key, value, label), (icon(:check, classes: "w-3.5 h-3.5 text-iris-300") if current) ].compact
    end
  end

  # "storefront · production" (in its tone) / "storefront · all environments"
  def issues_eyebrow(project, environment)
    safe_join [ project.name, environment.present? ? environment_text(environment) : "all environments" ], " · "
  end

  private
    def query_chip_tone(chip)
      return ChipHelper::CHIP_TONES.fetch(environment_tone(chip.value)) if chip.key == "env"

      ChipHelper::CHIP_TONES.fetch(chip.key == "is" ? :iris : :neutral)
    end

    # "env:staging" with its swatch; other keys plain.
    def filter_link_label(key, value, label)
      text = tag.span(label || "#{key}:#{value}", class: "font-mono")
      return text unless key == "env" && value

      tag.span safe_join([ environment_dot(value), text ]), class: "flex items-center gap-2"
    end

    def issue_tab_count(list, tab)
      return unless COUNTED_TABS.include?(tab)

      tone = tab == "for_review" ? "text-coral-300" : "text-ink-400"
      tag.span compact_count(list.tab_counts[tab]), class: "ml-1 font-mono text-[11px] #{tone}"
    end
end
