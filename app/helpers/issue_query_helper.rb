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

  def issues_query_path(project, query, sort: IssueList::DEFAULT_SORT)
    project_issues_path(project, q: query.to_s, sort: (sort unless sort == IssueList::DEFAULT_SORT))
  end

  # Pill with a × link that drops the chip; status chips are iris.
  def issue_query_chip(project, query, chip, sort:)
    key, value = chip.label.split(":", 2)
    remove = link_to "×", issues_query_path(project, query.without_chip(chip), sort:),
      class: "text-ink-400 hover:text-ink-50", "aria-label": "Remove #{chip.label}"
    classes = chip.key == "is" ? "chip chip-iris font-mono" : "chip font-mono"
    text = tag.span(safe_join([ "#{key}:", tag.span(value, class: "text-ink-50") ]))
    tag.span safe_join([ text, remove ]), class: classes
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
      safe_join [ tag.span(label || "#{key}:#{value}", class: "font-mono"), (icon(:check, classes: "w-3.5 h-3.5 text-iris-300") if current) ].compact
    end
  end

  # "storefront · production" / "storefront · all environments"
  def issues_eyebrow(project, environment)
    "#{project.name} · #{environment.presence || 'all environments'}"
  end

  private
    def issue_tab_count(list, tab)
      return unless COUNTED_TABS.include?(tab)

      tone = tab == "for_review" ? "text-coral-300" : "text-ink-400"
      tag.span compact_count(list.tab_counts[tab]), class: "ml-1 font-mono text-[11px] #{tone}"
    end
end
