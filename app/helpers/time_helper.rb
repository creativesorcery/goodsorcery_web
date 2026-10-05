module TimeHelper
  # "just now", "2 min ago", "3h ago", "12d ago", "9mo ago", "1y ago" ("never" for nil)
  def time_ago_compact(time)
    return "never" if time.nil?

    seconds = (Time.current - time).to_i
    seconds < 1.minute ? "just now" : "#{compact_duration(seconds)} ago"
  end

  # "first 3h ago"
  def first_seen_label(time)
    "first #{time_ago_compact(time)}"
  end

  # "Today 09:14", "Oct 3 09:14", or "Oct 3 2025 09:14" in the current (user's) zone.
  def clock_label(time)
    return "—" if time.nil?

    local = time.in_time_zone
    "#{clock_day(local)} #{local.strftime('%H:%M')}"
  end

  private
    def compact_duration(seconds)
      return "#{seconds / 1.minute} min" if seconds < 1.hour
      return "#{seconds / 1.hour}h" if seconds < 1.day
      return "#{seconds / 1.day}d" if seconds < 30.days
      return "#{seconds / 30.days}mo" if seconds < 365.days

      "#{seconds / 365.days}y"
    end

    def clock_day(local)
      today = Time.zone.today
      return "Today" if local.to_date == today
      return local.strftime("%b %-d") if local.year == today.year

      local.strftime("%b %-d %Y")
    end
end
