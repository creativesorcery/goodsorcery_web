# The issue list's search language: chips plus free text.
#
#   IssueQuery.new("is:unresolved env:production level:error checkout", user: Current.user)
#     .issues(project.issues)
#
# Chips: is:unresolved|resolved|ignored|for_review|new|regressed, env:<name>,
# level:<level>, assigned:me|none, user:<id, email, username or digest>,
# class:<ExceptionClass>. Everything else is free text over class, message,
# culprit and transaction (Issue.matching).
class IssueQuery
  DEFAULT = "is:unresolved".freeze
  MAX_LENGTH = 500
  UNRESOLVED_STATUSES = %w[unresolved for_review new regressed].freeze

  # Triage tabs, in display order, and the status/assignment chips each one means.
  TABS = {
    "unresolved" => %w[is:unresolved],
    "for_review" => %w[is:for_review],
    "assigned" => %w[is:unresolved assigned:me],
    "ignored" => %w[is:ignored],
    "resolved" => %w[is:resolved]
  }.freeze

  class << self
    # q wins (links, global search); otherwise the filter bar's hidden chips
    # plus its text input; with neither, the default unresolved view.
    def from_params(params, user: nil)
      new(compose(params), user:)
    end

    private
      def compose(params)
        return string_param(params[:q]) if params.key?(:q)
        return "#{string_param(params[:chips])} #{string_param(params[:text])}" if params.key?(:chips) || params.key?(:text)

        DEFAULT
      end

      def string_param(value)
        value.is_a?(String) ? value : ""
      end
  end

  attr_reader :chips, :text, :user

  def initialize(query = DEFAULT, user: nil)
    tokens = query.to_s.first(MAX_LENGTH).split
    @chips = tokens.filter_map { |token| Chip.parse(token) }.uniq
    @text = tokens.reject { |token| Chip.parse(token) }.join(" ")
    @user = user
  end

  # The scope narrowed by every chip and the free text.
  def issues(scope)
    filter(scope, chips)
  end

  # Everything except the status/assignment chips: the base for tab counts.
  def issues_ignoring_tabs(scope)
    filter(scope, chips.reject(&:tab?))
  end

  def to_s
    [ *chips.map(&:to_s), text ].compact_blank.join(" ")
  end

  def chips_string
    chips.join(" ")
  end

  def default? = to_s == DEFAULT

  # The default unresolved view, whichever environment it is scoped to.
  def default_view? = without_key("env").default?

  def blank? = to_s.blank?

  def tab
    selected = chips.select(&:tab?).map(&:to_s).sort
    TABS.find { |_, tab_chips| tab_chips.sort == selected }&.first
  end

  def value_of(key)
    chips.find { |chip| chip.key == key }&.value
  end

  def environment = value_of("env")

  def level = value_of("level")

  def status = value_of("is")

  # Every issue in this view is unresolved (so "Reopen" makes no sense).
  def unresolved_only? = UNRESOLVED_STATUSES.include?(status)

  # New queries for links: each keeps the free text.
  def for_tab(tab)
    rebuild(TABS.fetch(tab).map { |token| Chip.parse(token) } + chips.reject(&:tab?))
  end

  def with_chip(key, value)
    rebuild(chips.reject { |chip| chip.key == key } + [ Chip.new(key:, value:) ])
  end

  def without_chip(chip)
    rebuild(chips - [ chip ])
  end

  def without_key(key)
    rebuild(chips.reject { |chip| chip.key == key })
  end

  # Scoped to one environment, or to all of them (nil).
  def with_environment(environment)
    return self if self.environment == environment

    environment ? with_chip("env", environment) : without_key("env")
  end

  private
    def filter(scope, selected_chips)
      scope = selected_chips.inject(scope) { |relation, chip| chip.apply(relation, user:) }
      text.present? ? scope.matching(text) : scope
    end

    def rebuild(new_chips)
      self.class.new([ *new_chips.map(&:to_s), text ].join(" "), user:)
    end
end
