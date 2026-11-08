# The environments an issue alert's scope is checked against: the triggering
# occurrence's when there is one (ingest passes its id), else all of the
# issue's. Looked up lazily and once, so IssueAlert and SlackIssueAlert can
# share it (IssueAlertJob), and an alert whose rule is off never queries.
#
#   environments = IssueAlert::TriggeringEnvironments.new(issue, occurrence_id)
#   environments.to_a   # => ["production"]
class IssueAlert::TriggeringEnvironments
  def initialize(issue, occurrence_id)
    @issue, @occurrence_id = issue, occurrence_id
  end

  def to_a
    @to_a ||= triggering_environment ? [ triggering_environment ] : @issue.environments
  end

  private
    def triggering_environment
      return @triggering_environment if defined?(@triggering_environment)

      @triggering_environment = @occurrence_id && @issue.occurrences.where(id: @occurrence_id).pick(:environment)
    end
end
