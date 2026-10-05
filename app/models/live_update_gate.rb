# Throttles live-update broadcasts through the shared cache store (Redis in
# production), so a burst of ingested events turns into one broadcast per
# record per window instead of one per event.
#
# The key holds only a record id and a counter; nothing captured is cached.
#
#   LiveUpdateGate.new(:issue, issue.id).first_in_window?        # debounce
#   LiveUpdateGate.new(:new_issues, project.id).within_limit?(10) # cap
class LiveUpdateGate
  WINDOW = 2.seconds

  def initialize(kind, id)
    @key = [ "live", kind.to_s, id ]
  end

  # True for exactly one caller per window (atomic SET NX on Redis).
  def first_in_window?
    Rails.cache.write(@key, 1, unless_exist: true, expires_in: WINDOW)
  end

  # True for the first +limit+ callers per window. A store without counters
  # (the null store) lets everything through.
  def within_limit?(limit)
    Rails.cache.increment(@key, 1, expires_in: WINDOW).to_i <= limit
  end
end
