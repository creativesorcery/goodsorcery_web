# What one MCP request may reach: the token's account, its apps and their
# issues, occurrences, monitors and performance data, nothing else
# (docs/ARCHITECTURE.md §14.4). Every tool starts its lookups here, so ids of
# other accounts are simply not found.
#
#   context = Mcp::Context.new(token, base_url: "https://app.goodsorcery.com")
#   context.project!("storefront")   # raises Mcp::NotFound for any other slug
#   context.issue!("GS-42")
class Mcp::Context
  attr_reader :token, :base_url

  delegate :account, :user, to: :token

  def initialize(token, base_url:)
    @token = token
    @base_url = base_url
  end

  # The SDK wraps the server context in its own object and forwards method
  # calls; tools read the context itself through this.
  def mcp_context = self

  def scope?(scope) = token.scope?(scope)

  # The account's apps, loaded once per request (an account has at most
  # Project::MAX_PER_ACCOUNT); slug and prefix lookups use them in memory.
  def projects
    @projects ||= account.projects.order(:name).includes(:api_keys).to_a
  end

  def project_ids = projects.map(&:id)

  def project!(slug)
    projects.find { |project| project.slug == slug.to_s } ||
      raise(Mcp::NotFound, "No app with the slug #{Mcp::Text.quote(slug)}. Use list_apps to see the app slugs.")
  end

  # The app for an optional slug: nil (all apps) when blank.
  def optional_project(slug) = slug.present? ? project!(slug) : nil

  def issues = Issue.where(project_id: project_ids)

  def issue!(reference) = Mcp::IssueReferences.new(self, [ reference ]).issues!.first

  # Gives records their project from the loaded apps, without a query.
  def attach_projects(records)
    ActiveRecord::Associations::Preloader.new(records:, associations: :project, available_records: projects).call
    records
  end

  def entitlements = @entitlements ||= account.entitlements

  def issue_url(issue) = routes.project_issue_url(issue.project, issue, **url_options)

  def issues_url(project) = routes.project_issues_url(project, **url_options)

  def trace_url(trace) = routes.project_performance_trace_url(trace.project, trace, **url_options)

  private
    def routes = Rails.application.routes.url_helpers

    def url_options
      @url_options ||= PublicUrl.new(base_url).url_options
    end
end
