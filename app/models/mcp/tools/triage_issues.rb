# The shared shape of resolve_issue, ignore_issue and unresolve_issue: 1 to
# MAX_ISSUES issues of the account change status through the same domain
# method as the dashboard's bulk bar (Issue::Triage, with its activity rows,
# count expiry and live-update broadcasts), marked "via MCP". Unknown ids
# change nothing. Each call is recorded in the token's audit log
# (AccessTokenActivity) and the result lists every issue's new status.
class Mcp::Tools::TriageIssues < Mcp::Tools::Base
  MAX_ISSUES = 25

  class_attribute :triage_method, :audit_action, :verb, instance_writer: false

  def self.issues_schema
    { properties: { issues: { type: "array", minItems: 1, maxItems: MAX_ISSUES, items: ID_SCHEMA,
                              description: "1 to #{MAX_ISSUES} issue short ids (e.g. GS-42) or numeric ids." } },
      required: %w[issues], additionalProperties: false }
  end

  private
    def issues = @issues ||= Mcp::IssueReferences.new(context, arguments[:issues]).issues!

    def build_payload
      changed_ids = Issue.where(id: issues.map(&:id)).public_send(triage_method, by: context.user, via: "mcp")
      AccessTokenActivity.record(context.token, audit_action, changed_ids) if changed_ids.any?
      statuses = Issue.where(id: issues.map(&:id)).pluck(:id, :status).to_h
      { changed: changed_ids.size, issues: issues.map { |issue| result(issue, statuses, changed_ids) } }
    end

    def result(issue, statuses, changed_ids)
      { short_id: issue.short_id, id: issue.id, status: statuses.fetch(issue.id), changed: changed_ids.include?(issue.id) }
    end

    def text_lines
      [ "#{verb} #{payload[:changed]} of #{issues.size} #{'issue'.pluralize(issues.size)}.",
        *payload[:issues].map { |row| "#{row[:short_id]}: #{row[:status]}#{' (unchanged)' unless row[:changed]}" } ]
    end
end
