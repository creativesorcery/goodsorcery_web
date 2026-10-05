# The pointers that live updates carry: which stream, which frame id and
# which URL each browser should re-fetch with its own session. Broadcasts
# never include captured error data, only these dom ids and paths (§4.4).
#
#   LiveFrames.new(issue.project, issue).issue_frames.each(&:reload)
#   LiveFrames.new(project).project_frames.each(&:reload)
#   LiveFrames.recent_issues(account).reload
class LiveFrames
  include ActionView::RecordIdentifier
  include Rails.application.routes.url_helpers

  # One Turbo Frame on one stream. #reload sends a `reload_frame` stream
  # action (app/javascript/stream_actions.js) carrying only target and src.
  Frame = Data.define(:streamables, :target, :src) do
    def reload
      Turbo::StreamsChannel.broadcast_action_to(*streamables, action: :reload_frame, target:, attributes: { src: })
    end
  end

  # All issue-list rows on screen at once: #reload sends a `reload_rows`
  # stream action carrying only the list's dom id and the rows endpoint, and
  # each browser fetches its visible rows in one request.
  Rows = Data.define(:streamables, :target, :src) do
    def reload
      Turbo::StreamsChannel.broadcast_action_to(*streamables, action: :reload_rows, target:, attributes: { src: })
    end
  end

  # Stream names, shared by the broadcasts below and the views' live_stream_from.
  class << self
    def projects_stream(account) = [ account, :projects ]
    def issues_stream(project) = [ project, :issues ]
    def issue_stream(issue) = [ issue ]
    def setup_stream(project) = [ project, :setup ]

    # The account-wide feed on the overview; broadcast once per account per window.
    def recent_issues(account)
      helpers = Rails.application.routes.url_helpers
      Frame.new(projects_stream(account), ActionView::RecordIdentifier.dom_id(account, :recent_issues), helpers.recent_issues_path)
    end
  end

  attr_reader :project, :issue

  def initialize(project, issue = nil)
    @project = project
    @issue = issue
  end

  # The issue page's frames; list rows reload with the project (#rows).
  def issue_frames = [ stats, chart ]

  def project_frames = [ summary, card, listening, rows ]

  def row = Frame.new(issues_stream, dom_id(issue, :row), project_issue_row_path(project, issue))

  def stats = Frame.new(issue_stream, dom_id(issue, :stats), project_issue_stats_path(project, issue))

  def chart = Frame.new(issue_stream, dom_id(issue, :chart), project_issue_chart_path(project, issue))

  def summary = Frame.new(issues_stream, dom_id(project, :summary), project_summary_path(project))

  def card = Frame.new(projects_stream, dom_id(project, :card), project_card_path(project))

  def recent_issues = self.class.recent_issues(account)

  def rows = Rows.new(issues_stream, rows_target, project_rows_path(project))

  # The issue list section whose row frames `reload_rows` refreshes.
  def rows_target = dom_id(project, :issues)

  def listening = Frame.new(setup_stream, dom_id(project, :listening), project_listening_path(project))

  # Container above the issue list rows that new issues are prepended into.
  def new_issues_target = dom_id(project, :new_issues)

  # Prepends an empty, lazily-filled row frame for a brand-new issue.
  def prepend_new_row
    Turbo::StreamsChannel.broadcast_prepend_to(*issues_stream, target: new_issues_target,
      partial: "live/new_issue_row", locals: { frame: row })
  end

  private
    def account = project.account

    def projects_stream = self.class.projects_stream(account)

    def issues_stream = self.class.issues_stream(project)

    def issue_stream = self.class.issue_stream(issue)

    def setup_stream = self.class.setup_stream(project)
end
