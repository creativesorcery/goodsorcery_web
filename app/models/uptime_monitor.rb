# A URL of an app that Good Sorcery requests on a schedule (docs/ARCHITECTURE.md
# §12). Named UptimeMonitor because Ruby's own Monitor class is used by Rails.
#
# The URL is encrypted and treated like captured data: it may carry tokens in
# its query string. It is shown only on the edit form and the detail page;
# everywhere else uses #name and #host. Job arguments, broadcasts, logs,
# validation messages and check rows never hold it.
#
# Entitlements are enforced here, so crafted requests can't get past them:
# the interval must be allowed for the account, and creating counts the
# monitors of every app in the account (under a lock on the account row).
class UptimeMonitor < ApplicationRecord
  include UptimeMonitor::Checking, UptimeMonitor::Broadcasting, UptimeMonitor::Alerting

  INTERVALS = Entitlements::UPTIME_INTERVALS
  INTERVAL_LABELS = { 1 => "Every minute", 5 => "Every 5 minutes", 10 => "Every 10 minutes", 60 => "Every hour" }.freeze
  STATUSES = %w[pending up down].freeze
  # A monitor checked this recently is not checked again (stale claims, "Check now").
  RECHECK_GAP = 30.seconds
  URL_MESSAGE = "must be a public http:// or https:// address".freeze

  belongs_to :project, inverse_of: :uptime_monitors
  has_many :checks, class_name: "UptimeCheck", inverse_of: :uptime_monitor
  has_many :hourly_counts, class_name: "UptimeHourlyCount", inverse_of: :uptime_monitor
  has_many :incidents, class_name: "UptimeIncident", inverse_of: :uptime_monitor

  encrypts :url

  enum :status, STATUSES.index_by(&:itself), validate: true

  normalizes :name, with: ->(name) { name.squish }
  normalizes :url, with: ->(url) { UptimeUrl.normalize(url) }

  scope :active, -> { where(paused_at: nil) }
  scope :due, ->(now = Time.current) { active.where(next_check_at: ..now) }

  before_validation :name_from_host
  validates :name, length: { in: 1..60 }
  validate :url_public
  validates :interval_minutes, inclusion: { in: INTERVALS }
  validate :interval_entitled, if: -> { new_record? || interval_minutes_changed? }
  validate :within_monitor_limit, on: :create

  before_save :schedule_now, if: -> { new_record? || url_changed? || interval_minutes_changed? }
  after_destroy_commit :refit_account

  # Also the "limit reached" panel's text on the new monitor page.
  def self.limit_message(max_monitors)
    "This account has reached its limit of #{max_monitors} #{'monitor'.pluralize(max_monitors)}."
  end

  def paused? = paused_at.present?

  def checked_recently?(now = Time.current)
    last_checked_at.present? && last_checked_at > now - RECHECK_GAP
  end

  # The only part of the URL shown outside the edit form and the detail page.
  def host = UptimeUrl.parse(url)&.host

  def interval_label = INTERVAL_LABELS.fetch(interval_minutes, "Every #{interval_minutes} minutes")

  def open_incident = incidents.open.order(:id).last

  private
    def entitlements = project.account.entitlements

    def name_from_host
      self.name = host.to_s.first(60) if name.blank?
    end

    # The message never echoes the value.
    def url_public
      return errors.add(:url, :blank) if url.blank?

      errors.add(:url, URL_MESSAGE) unless UptimeUrl.new(url).public?
    end

    def interval_entitled
      return if project.nil? || !INTERVALS.include?(interval_minutes)
      return if entitlements.allows_uptime_interval?(interval_minutes)

      errors.add(:interval_minutes, "isn't available on this account")
    end

    # Validations run inside save's transaction, so the account row lock
    # serialises concurrent creates and the count sees committed monitors.
    def within_monitor_limit
      return if project.nil? || entitlements.max_monitors.nil?

      Account.where(id: project.account_id).lock("FOR NO KEY UPDATE").pick(:id)
      count = self.class.uncached { project.account.uptime_monitors.count }
      return unless entitlements.monitor_limit_reached?(count)

      errors.add(:base, self.class.limit_message(entitlements.max_monitors))
    end

    def schedule_now
      self.next_check_at = Time.current
    end

    # A deleted monitor frees a place under the account's limit.
    def refit_account
      project.account.fit_uptime_monitors_to_entitlements
    end
end
