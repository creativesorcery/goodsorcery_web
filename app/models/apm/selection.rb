# The query params shared by the Performance pages (docs/ARCHITECTURE.md
# §13.8), read once and checked: the environment, the range, the overview's
# tab, sort, filter and "show all", and the endpoint page's trace sort and
# page. Anything unknown falls back to its default; a locked range falls
# back to 1d (Apm::Range.pick). Every link on these pages carries env and
# range (#link_params).
#
#   selection = Apm::Selection.new(project, params, entitlements: Current.account.entitlements)
#   selection.environment  # => "production"
#   selection.link_params(tab: "jobs")  # => { env: "production", range: "1d", tab: "jobs" }
class Apm::Selection
  TABS = { "web" => "web", "jobs" => "job" }.freeze
  DEFAULT_TAB = "web".freeze
  TRACE_SORTS = ApmTrace::SORTS
  QUERY_LIMIT = 100

  attr_reader :project, :entitlements, :now

  # environment: fixes the environment (a transaction's own page) instead
  # of reading the env param.
  def initialize(project, params, entitlements:, now: Time.current, environment: nil)
    @project = project
    @params = params
    @entitlements = entitlements
    @now = now
    @fixed_environment = environment
  end

  def range = @range ||= Apm::Range.pick(param(:range), entitlements:, now:)

  # Environments of the app with performance data, most recently seen first.
  def environments = @environments ||= ApmTransaction.environments_of(project)

  # The env param when it has data, else the app's default environment when
  # it has data, else the busiest environment of the past day, else the
  # first with any data; nil when the app has none.
  def environment
    return @fixed_environment if @fixed_environment
    return @environment if defined?(@environment)

    @environment = pick_environment
  end

  # The tab in the URL, or nil (Apm::Overview picks the default).
  def requested_tab = TABS.key?(param(:tab)) ? param(:tab) : nil

  def sort = Apm::StatsQuery::SORTS.key?(param(:sort)) ? param(:sort) : Apm::StatsQuery::DEFAULT_SORT

  # The filter text, stripped and capped.
  def query = param(:q).to_s.strip.first(QUERY_LIMIT)

  def all? = param(:all) == "1"

  def trace_sort = TRACE_SORTS.include?(param(:traces)) ? param(:traces) : TRACE_SORTS.first

  # 1..ApmTrace::MAX_PAGE, so a crafted number can't overflow the offset.
  def page = param(:page).to_i.clamp(1, ApmTrace::MAX_PAGE)

  # env and range plus the overrides, without blank values.
  def link_params(**overrides)
    { env: environment, range: range.key }.merge(overrides).compact_blank
  end

  private
    # Only plain string values count; arrays and hashes are ignored.
    def param(name)
      value = @params[name]
      value if value.is_a?(String)
    end

    def pick_environment
      return param(:env) if environments.include?(param(:env))
      return project.default_environment if environments.include?(project.default_environment)

      busiest_environment || environments.first
    end

    def busiest_environment
      return if environments.size < 2

      requests = ApmHourlyStat.requests_by_environment(project, since: range.past_day_start)
      environments.max_by { |name| requests.fetch(name, 0) } if requests.values.any?(&:positive?)
    end
end
