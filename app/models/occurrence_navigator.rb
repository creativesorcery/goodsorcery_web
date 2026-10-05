# Moves between the stored occurrences of one issue for the issue page's
# right rail: latest / oldest / random shortcuts, older / newer by id, and the
# "N of M" position. Every lookup goes through issue.occurrences, so it can
# never reach another issue's (or account's) events.
#
#   navigator = OccurrenceNavigator.new(issue)
#   navigator.find("oldest")   # also "latest", "random" or an occurrence uuid
#   navigator.newer_uuid       # => uuid of the next occurrence by id, or nil
class OccurrenceNavigator
  SHORTCUTS = %w[latest oldest random].freeze

  attr_reader :issue, :occurrence

  def initialize(issue, occurrence: nil)
    @issue = issue
    @occurrence = occurrence
  end

  # The occurrence for a route param. Raises ActiveRecord::RecordNotFound for
  # an unknown uuid; returns nil for a shortcut when nothing is stored.
  def find(param)
    @requested = param.to_s
    @counts = @user_hits = nil
    @occurrence = SHORTCUTS.include?(@requested) ? public_send(@requested) : occurrences.find_by!(uuid: @requested)
  end

  def latest = occurrences.latest

  # How often the shown occurrence's user hit this issue (one query, memoised).
  def user_hits
    return 0 if occurrence&.user_digest.blank?

    @user_hits ||= IssueUser.count_for(issue, occurrence.user_digest)
  end

  def oldest = occurrences.oldest

  def random
    occurrences.order(:id).offset(rand([ occurrences.count, 1 ].max)).first
  end

  # uuids only: neighbours are links, so their encrypted payloads are never loaded.
  def older_uuid
    occurrence && occurrences.where(id: ...occurrence.id).latest_first.pick(:uuid)
  end

  def newer_uuid
    occurrence && occurrences.where("occurrences.id > ?", occurrence.id).order(:id).pick(:uuid)
  end

  # 1-based position counting from the oldest stored occurrence.
  def position = counts.first

  def stored_count = counts.last

  # Retention keeps the newest Occurrence::RETAINED_PER_ISSUE (and prunes by age),
  # so fewer may be stored than the issue has counted.
  def truncated? = stored_count < issue.events_count

  def latest? = occurrence.present? && position == stored_count

  def oldest? = occurrence.present? && position == 1

  # Which shortcut button reads as selected.
  def selected_shortcut
    return if occurrence.nil?
    return "random" if @requested == "random"
    return "latest" if latest?

    "oldest" if oldest?
  end

  private
    def occurrences = issue.occurrences

    # [position, stored count] in one query.
    def counts
      @counts ||= occurrence ? occurrences.pick(Arel.sql(position_sql), Arel.sql("COUNT(*)")) : [ 0, occurrences.count ]
    end

    def position_sql
      Occurrence.sanitize_sql_array([ "COUNT(*) FILTER (WHERE occurrences.id <= ?)", occurrence.id ])
    end
end
