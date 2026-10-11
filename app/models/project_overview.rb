# Numbers for the projects overview cards. A fixed number of grouped queries
# covers every project, however many there are: unresolved and new counts,
# unresolved counts per environment, last error times, environments, 14-day
# series per environment and 24-hour totals.
#
#   overview = ProjectOverview.new(Current.account.projects.order(:name))
#   overview.cards.each { |card| card.health.spiking? }
class ProjectOverview
  SPARKLINE_DAYS = 14
  HEALTH_HOURS = 24
  # One backward index probe per project on issues(project_id, last_seen_at),
  # instead of a grouped scan over every issue of every project.
  LAST_SEEN_SQL = "(SELECT MAX(issues.last_seen_at) FROM issues WHERE issues.project_id = projects.id)".freeze
  # One row per (issue, environment it was seen in).
  ISSUE_ENVIRONMENTS_JOIN = "CROSS JOIN LATERAL unnest(issues.environments) AS issue_environments(name)".freeze

  Card = Data.define(:project, :unresolved_count, :new_count, :last_seen_at, :environments,
                     :environment_unresolved_counts, :environment_series, :health) do
    # Changes whenever anything drawn on the card changes. Only ids, names and
    # numbers go into it; never any captured error data.
    def cache_key
      "project_cards/#{project.id}-#{Digest::SHA256.hexdigest(cache_parts.to_json)}"
    end

    # [[environment, count]] of environments with unresolved issues, production
    # first. An issue seen in two environments counts in both.
    def unresolved_by_environment
      in_display_order(environment_unresolved_counts).select { |_, count| count.positive? }
    end

    # [[environment, [count] * 14]], production first, so it stacks at the bottom.
    def series_by_environment
      in_display_order(environment_series)
    end

    # Events per day across every environment.
    def daily_series
      environment_series.values.transpose.map(&:sum).presence || Array.new(SPARKLINE_DAYS, 0)
    end

    private
      def cache_parts
        [ project.cache_key_with_version, project.first_event_at, project.runtime_label, environments,
          unresolved_count, new_count, last_seen_at, unresolved_by_environment, series_by_environment,
          health.status, health.days_clean ]
      end

      # Production-like environments first, then the project's key order, then
      # any other environment by name.
      def in_display_order(by_environment)
        names = (environments & by_environment.keys) | by_environment.keys.sort
        names = names.sort_by.with_index { |name, index| [ EnvironmentTone.production?(name) ? 0 : 1, index ] }
        names.map { |name| [ name, by_environment.fetch(name) ] }
      end
  end

  attr_reader :projects

  def initialize(projects, now: Time.current)
    @projects = projects.to_a
    @now = now
  end

  def cards
    projects.map { |project| card_for(project) }
  end

  def card_for(project)
    unresolved, fresh = issue_counts.fetch(project.id, [ 0, 0 ])
    Card.new(project:, unresolved_count: unresolved, new_count: fresh, last_seen_at: last_seen.fetch(project.id, nil),
      environments: environments.fetch(project.id, []),
      environment_unresolved_counts: environment_unresolved_counts.fetch(project.id, {}),
      environment_series: environment_series.fetch(project.id), health: health_for(project, unresolved))
  end

  private
    def health_for(project, unresolved_count)
      ProjectHealth.new(project, unresolved_count:, hourly_totals: hourly_totals.fetch(project.id),
        last_seen_at: last_seen.fetch(project.id, nil), now: @now)
    end

    def project_ids
      @project_ids ||= projects.map(&:id)
    end

    def issues
      Issue.where(project_id: project_ids)
    end

    # { project_id => [unresolved, new in the last 24 hours] } in one query.
    def issue_counts
      @issue_counts ||= issues.unresolved.group(:project_id)
        .pluck(:project_id, Arel.sql("COUNT(*)"), Arel.sql(new_count_sql))
        .to_h { |id, unresolved, fresh| [ id, [ unresolved, fresh ] ] }
    end

    def new_count_sql
      Issue.sanitize_sql_array([ "COUNT(*) FILTER (WHERE issues.first_seen_at >= ?)", @now - 24.hours ])
    end

    # { project_id => { environment => unresolved count } } in one query.
    def environment_unresolved_counts
      @environment_unresolved_counts ||= issues.unresolved.joins(ISSUE_ENVIRONMENTS_JOIN)
        .group(:project_id, "issue_environments.name").count
        .each_with_object(Hash.new { |hash, id| hash[id] = {} }) { |((id, name), count), counts| counts[id][name] = count }
    end

    def last_seen
      @last_seen ||= Project.where(id: project_ids).pluck(:id, Arel.sql(LAST_SEEN_SQL)).to_h.compact
    end

    # Plucks names only, so no encrypted token is ever loaded for the overview.
    def environments
      @environments ||= ApiKey.where(project_id: project_ids).order(:id).pluck(:project_id, :environment)
        .group_by(&:first).transform_values { |rows| rows.map(&:last) }
    end

    def environment_series
      @environment_series ||= ProjectHourlyCount.daily_series_by_environment(project_ids, days: SPARKLINE_DAYS)
    end

    def hourly_totals
      @hourly_totals ||= ProjectHourlyCount.hourly_totals(project_ids, hours: HEALTH_HOURS)
    end
end
