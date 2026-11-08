# ignore_issue: Ignore issues: they leave the unresolved list and stop alerting, and stay ignored even if the error keeps happening. Needs the triage scope (Mcp::Tools::TriageIssues).
class Mcp::Tools::IgnoreIssue < Mcp::Tools::TriageIssues
  self.tool_name = "ignore_issue"
  self.title = "Ignore issues"
  self.scope = "triage"
  self.annotations = TRIAGE
  self.triage_method = :ignore_all
  self.audit_action = "ignore"
  self.verb = "Ignored"
  self.description = "Ignore issues: they leave the unresolved list and stop alerting, and stay ignored even if the error keeps happening. Takes 1 to #{MAX_ISSUES} issue short ids. Returns each issue's new status."
  self.input_schema = issues_schema
end
