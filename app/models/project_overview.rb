# Numbers for the projects overview cards. A fixed number of grouped queries
# covers every project, however many there are: unresolved counts, new counts,
# last error times, environments, 14-day series and 24-hour totals.
#
#   overview = ProjectOverview.new(Current.account.projects.order(:name))
#   overview.cards.each { |card| card.health.spiking? }
class ProjectOverview
  SPARKLINE_DAYS = 14
  HEALTH_HOURS = 24
  # One backward index probe per project on issues(project_id, last_seen_at),
  # instead of a grouped scan over every issue of every project.
  LAST_SEEN_SQL = "(SELECT MAX(issues.last_seen_at) FROM issues WHERE issues.project_id = projects.id)".freeze

  Card = Data.define(:project, :unresolved_count, :new_count, :last_seen_at, :environments, :daily_series, :health) do
    # Changes whenever anything drawn on the card changes. Only ids, names and
    # numbers go into it; never any captured error data.
    def cache_key
      "project_cards/#{project.id}-#{Digest::SHA256.hexdigest(cache_parts.to_json)}"
    end

    private
      def cache_parts
        [ project.cache_key_with_version, project.first_event_at, project.runtime_label, environments,
          unresolved_count, new_count, last_seen_at, daily_series, health.status, health.days_clean ]
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
    Card.new(project:, unresolved_count: unresolved_counts.fetch(project.id, 0), new_count: new_counts.fetch(project.id, 0),
      last_seen_at: last_seen.fetch(project.id, nil), environments: environments.fetch(project.id, []),
      daily_series: daily_series.fetch(project.id), health: health_for(project))
  end

  private
    def health_for(project)
      ProjectHealth.new(project, unresolved_count: unresolved_counts.fetch(project.id, 0),
        hourly_totals: hourly_totals.fetch(project.id), last_seen_at: last_seen.fetch(project.id, nil), now: @now)
    end

    def project_ids
      @project_ids ||= projects.map(&:id)
    end

    def issues
      Issue.where(project_id: project_ids)
    end

    def unresolved_counts
      @unresolved_counts ||= issues.unresolved.group(:project_id).count
    end

    def new_counts
      @new_counts ||= issues.unresolved.where(first_seen_at: (@now - 24.hours)..).group(:project_id).count
    end

    def last_seen
      @last_seen ||= Project.where(id: project_ids).pluck(:id, Arel.sql(LAST_SEEN_SQL)).to_h.compact
    end

    # Plucks names only, so no encrypted token is ever loaded for the overview.
    def environments
      @environments ||= ApiKey.where(project_id: project_ids).order(:id).pluck(:project_id, :environment)
        .group_by(&:first).transform_values { |rows| rows.map(&:last) }
    end

    def daily_series
      @daily_series ||= ProjectHourlyCount.daily_series(project_ids, days: SPARKLINE_DAYS)
    end

    def hourly_totals
      @hourly_totals ||= ProjectHourlyCount.hourly_totals(project_ids, hours: HEALTH_HOURS)
    end
end
