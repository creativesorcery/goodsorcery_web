# The staff form for one account's entitlements (/staff/accounts/:id/edit,
# docs/ARCHITECTURE.md §12.2), translated to and from
# accounts.entitlement_values:
#
# - Each key is set to "default" or "custom" (entitlements[setting][key]).
#   A key set to "default", or not set at all, is left out of the document,
#   so the account follows config/entitlements.yml; its fields are ignored.
# - Every custom key is stored as a JSON integer, a list of integers or, for
#   a cap ticked "No limit" or left blank, null. A cap ticked "No limit"
#   with a number beside it is a problem, so the number is never dropped
#   silently. monthly_event_quota has no "No limit".
# - Text that isn't a whole number is passed on as it came, so
#   Entitlements.problems rejects it and nothing is saved: a string is never
#   stored.
#
# Saving goes through Account#update, so the account's commit callbacks
# (fitting to the entitlements, the cached quota answer) run as for any
# other change.
class Staff::EntitlementsForm
  include ActiveModel::Model

  # The form's names for the keys, in the order the form and the show page
  # list them.
  LABELS = {
    "uptime_intervals" => "Uptime check intervals",
    "max_monitors" => "Uptime monitors per app",
    "max_projects" => "Apps",
    "monthly_event_quota" => "Error events per month",
    "retention_days" => "Error retention choices",
    "apm_retention_days" => "Performance data retention"
  }.freeze
  KEYS = LABELS.keys.freeze

  PERMITTED = [ :max_monitors, :max_projects, :monthly_event_quota, :apm_retention_days,
                { uptime_intervals: [], retention_days: [], no_limit: [], setting: KEYS.map(&:to_sym) } ].freeze

  attr_reader :account

  # Without params the form shows what the account stores.
  def initialize(account, params = nil)
    @account = account
    @params = params&.to_h&.stringify_keys
  end

  # What each key resolves to with nothing stored, in hosted mode.
  def hosted_defaults
    @hosted_defaults ||= Entitlements.new({}, hosted: true)
  end

  # What applies to the account now in hosted mode, stored or default.
  def hosted_value(key)
    hosted_entitlements.public_send(key)
  end

  # Where hosted_value comes from: :stored, :default, or :invalid for a
  # stored value Entitlements ignores in favour of the default.
  def source(key)
    return :default unless stored.key?(key)

    Entitlements.valid_value?(key, stored[key]) ? :stored : :invalid
  end

  def use_default?(key)
    submitted? ? submitted_setting(key) != "custom" : !stored.key?(key)
  end

  def no_limit?(key)
    return submitted_list("no_limit").include?(key) if submitted?

    stored.key?(key) ? stored[key].nil? : hosted_defaults.public_send(key).nil?
  end

  # The number field's text, or the ticked choices of a list key.
  def field_value(key)
    return @params[key] if submitted?

    stored.fetch(key) { hosted_defaults.public_send(key) }
  end

  def chosen?(key, choice)
    Array(field_value(key)).map(&:to_s).include?(choice.to_s)
  end

  # The document to store: every key not left to its default.
  def entitlement_values
    Entitlements::KEYS.reject { |key| use_default?(key) }.index_with { |key| submitted_value(key) }
  end

  # Whole-sentence problems with the submitted form, by key (none for a
  # key left to its default).
  def problems
    return {} unless submitted?

    @problems ||= KEYS.reject { |key| use_default?(key) }.index_with { |key| problem_with(key) }.compact
  end

  def problem(key) = problems[key]

  def save
    problems.each_value { |message| errors.add(:base, message) }
    return false if errors.any?
    return true if account.update(entitlement_values:)

    account.errors[:base].each { |message| errors.add(:base, message) }
    account.restore_attributes([ :entitlement_values ])
    false
  end

  private
    def submitted? = !@params.nil?

    def stored
      @stored ||= account.entitlement_values.is_a?(Hash) ? account.entitlement_values : {}
    end

    def hosted_entitlements
      @hosted_entitlements ||= Entitlements.new(stored, hosted: true, account_id: account.id)
    end

    def submitted_setting(key)
      settings = @params["setting"]
      settings[key].to_s if settings.is_a?(Hash)
    end

    def submitted_list(key)
      Array(@params[key]).compact_blank.map(&:to_s)
    end

    def submitted_value(key)
      return submitted_list(key).map { |choice| whole_number(choice) } if Entitlements::CHOICE_KEYS.key?(key)
      return nil if Entitlements::CAP_KEYS.include?(key) && (no_limit?(key) || number_blank?(key))

      whole_number(@params[key])
    end

    def problem_with(key)
      # Named like Entitlements::PROBLEMS ("Max monitors ..."), after the key shown under each label.
      return "#{key.humanize} must be a number or No limit, not both." if no_limit_with_number?(key)

      Entitlements::PROBLEMS[key] unless Entitlements.valid_value?(key, submitted_value(key))
    end

    def no_limit_with_number?(key)
      Entitlements::CAP_KEYS.include?(key) && no_limit?(key) && !number_blank?(key)
    end

    def number_blank?(key) = @params[key].to_s.strip.empty?

    # "25" → 25; anything else stays text, for Entitlements.problems to reject.
    def whole_number(text)
      text = text.to_s.strip
      Integer(text, 10, exception: false) || text
    end
end
