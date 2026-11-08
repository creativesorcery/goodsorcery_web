# Keeping each app's error retention within its account's retention_days
# entitlement (docs/ARCHITECTURE.md §12.3.2). An app whose retention_days
# isn't allowed moves to the nearest allowed value, a tie going to the longer
# one (Entitlements#nearest_retention_days). Self-hosted every choice is
# allowed, so only values outside Project::RETENTION_CHOICES move.
#
# Set-based: one UPDATE whatever the number of apps, with the nearest value
# picked by a CASE over the midpoints between allowed values. Runs from
# Account#fit_to_entitlements.
module Account::ProjectRetention
  extend ActiveSupport::Concern

  # The nearest allowed value as SQL: for [30, 60],
  # "CASE WHEN retention_days * 2 < 90 THEN 30 ELSE 60 END". Below a midpoint
  # goes down, a midpoint itself goes up.
  def self.nearest_value(allowed)
    allowed = allowed.map { Integer(it) }.sort
    return Arel::Nodes.build_quoted(allowed.first) if allowed.one?

    doubled = Arel::Nodes::Multiplication.new(Project.arel_table[:retention_days], Arel::Nodes.build_quoted(2))
    allowed.each_cons(2).reduce(Arel::Nodes::Case.new) { |sql, (low, high)| sql.when(doubled.lt(low + high)).then(low) }
      .else(allowed.last)
  end

  def fit_project_retention_to_entitlements(now: Time.current)
    allowed = entitlements.retention_days
    projects.where.not(retention_days: allowed)
      .update_all(retention_days: Account::ProjectRetention.nearest_value(allowed), updated_at: now)
  end
end
