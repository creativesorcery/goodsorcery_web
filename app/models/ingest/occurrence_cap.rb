# Holds each project to Occurrence::RETAINED_PER_PROJECT stored occurrences.
#
# Every event is still counted (issue counters, rollups and alerts); only
# stored copies are dropped, and fairly: the issues with the most copies lose
# their oldest first, down to a level every issue can keep, and every issue
# keeps at least its newest copy. A project with more issues than the cap can
# therefore stay a little over it.
class Ingest::OccurrenceCap
  BATCH = 1_000

  # Trims every project over the cap; returns the number of occurrences deleted.
  def self.enforce_all(cap: Occurrence::RETAINED_PER_PROJECT)
    ApplicationRecord.uncached do
      projects_over(cap).sum { |project_id| new(project_id, cap:).enforce }
    end
  end

  def self.projects_over(cap)
    Occurrence.group(:project_id).having("COUNT(*) > ?", cap).pluck(:project_id)
  end

  def initialize(project_id, cap: Occurrence::RETAINED_PER_PROJECT)
    @project_id, @cap = project_id, cap
  end

  # Returns the number of occurrences deleted.
  def enforce
    counts = occurrences.group(:issue_id).count.values
    return 0 if counts.sum <= @cap

    delete(ids_beyond(level(counts)))
  end

  # The most copies each issue may keep, at least 1, with the total within the cap.
  def level(counts)
    first_over = (1..counts.max).bsearch { |keep| kept(counts, keep) > @cap }
    [ (first_over || (counts.max + 1)) - 1, 1 ].max
  end

  private
    def occurrences = Occurrence.where(project_id: @project_id)

    def kept(counts, keep) = counts.sum { |count| [ count, keep ].min }

    # Ids past each issue's newest `keep`, ranked by id like TrimOccurrencesJob.
    def ids_beyond(keep)
      ranked = occurrences.select(:id, "ROW_NUMBER() OVER (PARTITION BY issue_id ORDER BY id DESC) AS newest_rank")
      Occurrence.from(ranked, :ranked).where("ranked.newest_rank > ?", keep).pluck(Arel.sql("ranked.id"))
    end

    def delete(ids)
      deleted = ids.each_slice(BATCH).sum { |slice| Occurrence.where(id: slice).delete_all }
      Rails.logger.info { "Occurrence cap deleted #{deleted} occurrences of project #{@project_id}" }
      deleted
    end
end
