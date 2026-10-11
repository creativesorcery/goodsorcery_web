class ProjectHourlyCount < ApplicationRecord
  belongs_to :project, inverse_of: :project_hourly_counts

  scope :in_environment, ->(environment) { environment.present? ? where(environment:) : all }

  class << self
    # { project_id => { environment => [count] * days } } of UTC days, oldest
    # first, in one query. Only environments with events in the window appear.
    def daily_series_by_environment(project_ids, days: 14)
      from = TimeSeries.window_start(1.day, days)
      counts = where(project_id: project_ids, hour: from..)
        .group(:project_id, :environment, TimeSeries.bucket_sql(1.day)).sum(:count)
      by_environment = counts.group_by { |(id, environment, _), _| [ id, environment ] }
      result = project_ids.index_with { {} }
      by_environment.each do |(id, environment), rows|
        result[id][environment] = TimeSeries.new(rows.to_h { |(*, time), n| [ time, n ] }, from:, step: 1.day, buckets: days).values
      end
      result
    end

    # { project_id => [count] * hours }, oldest first, in one query.
    def hourly_totals(project_ids, hours: 24)
      grouped_series(project_ids, step: 1.hour, buckets: hours)
    end

    def total(project, from:, to:, environment: nil)
      where(project:, hour: from...to).in_environment(environment).sum(:count)
    end

    # [count] * buckets starting at `from` (aligned to `step`), for one project.
    def series(project, from:, buckets:, step: 1.hour, environment: nil)
      from = TimeSeries.align(from, step)
      counts = where(project:, hour: from..).in_environment(environment).group(TimeSeries.bucket_sql(step)).sum(:count)
      TimeSeries.new(counts, from:, step:, buckets:).values
    end

    private
      def grouped_series(project_ids, step:, buckets:)
        from = TimeSeries.window_start(step, buckets)
        counts = where(project_id: project_ids, hour: from..).group(:project_id, TimeSeries.bucket_sql(step)).sum(:count)
        by_project = counts.group_by { |(id, _), _| id }.transform_values { |pairs| pairs.to_h { |(_, time), n| [ time, n ] } }
        project_ids.index_with { |id| TimeSeries.new(by_project.fetch(id, {}), from:, step:, buckets:).values }
      end
  end
end
