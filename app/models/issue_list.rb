# One page of a project's issue list for an IssueQuery: the rows, their 24h
# histograms (one query for the whole page), tab counts (one query) and paging.
# Pages are OFFSET-based and capped; past the cap, refine the search instead.
class IssueList
  PER_PAGE = 25
  MAX_PAGE = 40
  DEFAULT_SORT = "last_seen".freeze
  HISTOGRAM_HOURS = 24

  SORT_LABELS = {
    "last_seen" => "Last seen",
    "first_seen" => "First seen",
    "events" => "Events",
    "users" => "Users"
  }.freeze

  TAB_CONDITIONS = {
    "unresolved" => "issues.status = 'unresolved'",
    "for_review" => "issues.status = 'unresolved' AND (issues.first_seen_at >= :new_since OR issues.regressed_at IS NOT NULL)",
    "assigned" => "issues.status = 'unresolved' AND issues.assignee_id = :user_id",
    "ignored" => "issues.status = 'ignored'",
    "resolved" => "issues.status = 'resolved'"
  }.freeze

  attr_reader :project, :query, :page, :sort

  def initialize(project, query, page: 1, sort: nil)
    @project = project
    @query = query
    @page = page.to_i.clamp(1, MAX_PAGE)
    @sort = SORT_LABELS.key?(sort.to_s) ? sort.to_s : DEFAULT_SORT
  end

  def issues
    page_with_lookahead.first(PER_PAGE)
  end

  def empty? = issues.empty?

  def histogram_for(issue)
    histograms.fetch(issue.id) { Array.new(HISTOGRAM_HOURS, 0) }
  end

  def next_page? = more? && page < MAX_PAGE

  def next_page = page + 1

  # More rows exist than the page cap lets us show.
  def capped? = more? && page >= MAX_PAGE

  def shown_count = ((page - 1) * PER_PAGE) + issues.size

  def total_count
    @total_count ||= filtered.count
  end

  # { "unresolved" => 23, "for_review" => 5, ... } in one query, honouring the
  # query's other chips and text.
  def tab_counts
    @tab_counts ||= IssueQuery::TABS.keys.zip(Array(tab_count_scope.pick(*tab_count_columns))).to_h
  end

  def sort_label = SORT_LABELS.fetch(sort)

  # Unfiltered first page: where live-created issues get prepended.
  def default_state?
    page == 1 && sort == DEFAULT_SORT && query.default?
  end

  private
    def filtered
      query.issues(project.issues)
    end

    def page_with_lookahead
      @page_with_lookahead ||= filtered.sorted_by(sort).includes(:assignee)
        .limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE).to_a
    end

    def more? = page_with_lookahead.size > PER_PAGE

    def histograms
      @histograms ||= issues.empty? ? {} : IssueHourlyCount.histograms(issues.map(&:id), hours: HISTOGRAM_HOURS)
    end

    def tab_count_scope
      query.issues_ignoring_tabs(project.issues)
    end

    def tab_count_columns
      binds = { new_since: 24.hours.ago, user_id: query.user&.id }
      TAB_CONDITIONS.values.map do |condition|
        Arel.sql(Issue.sanitize_sql_array([ "COUNT(*) FILTER (WHERE #{condition})", binds ]))
      end
    end
end
