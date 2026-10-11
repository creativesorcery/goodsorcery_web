# One alert rule of one app, switched on or off on its own. Every app has
# one row per kind (created with the app; a migration backfilled older apps):
#
#   new_issue           the first occurrence of a brand-new issue
#   regression          a resolved issue happens again
#   reached_production  an issue seen elsewhere gets its first production event
#   still_happening     an issue's events in the last hour reach `threshold`
#   daily_digest        09:00 in each recipient's zone: open issues seen in 24h
#
#   project.alert_rule(:still_happening).threshold  # => 100
#   AlertRule.enabled.still_happening.includes(:project)
class AlertRule < ApplicationRecord
  DEFAULTS = {
    "new_issue" => { enabled: true },
    "regression" => { enabled: true },
    "reached_production" => { enabled: true },
    "still_happening" => { enabled: true, threshold: 100 },
    "daily_digest" => { enabled: false }
  }.freeze
  KINDS = DEFAULTS.keys.freeze
  # Rules that send an email per issue as it happens; a member's
  # "Email alerts" switch (NotificationPreference#alerts_muted) covers these.
  INSTANT_KINDS = (KINDS - %w[daily_digest]).freeze
  THRESHOLD_RANGE = 1..100_000
  THRESHOLD_MESSAGE = "must be a whole number from #{THRESHOLD_RANGE.min} to #{THRESHOLD_RANGE.max.to_fs(:delimited)}".freeze

  belongs_to :project, inverse_of: :alert_rules

  enum :kind, KINDS.index_by(&:itself), validate: true

  scope :enabled, -> { where(enabled: true) }

  validates :kind, uniqueness: { scope: :project_id }
  validates :threshold, numericality: { only_integer: true, in: THRESHOLD_RANGE, message: THRESHOLD_MESSAGE }, if: :still_happening?
  validates :threshold, absence: true, unless: :still_happening?

  # The default rule set as insert_all rows for one app.
  def self.default_rows_for(project)
    KINDS.map { |kind| { project_id: project.id, kind:, threshold: nil, **DEFAULTS.fetch(kind) } }
  end

  # An unsaved rule with the default settings, for an app missing that row.
  # Built by id so it never joins (and gets autosaved with) project.alert_rules.
  def self.build_default(project, kind)
    new(project_id: project.id, kind: kind.to_s, **DEFAULTS.fetch(kind.to_s))
  end

  def to_param = kind

  def instant? = INSTANT_KINDS.include?(kind)
end
