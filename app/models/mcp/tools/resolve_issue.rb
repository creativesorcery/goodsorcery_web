# resolve_issue: Mark issues as resolved (fixed). They reopen automatically as regressions if the error happens again. Needs the triage scope (Mcp::Tools::TriageIssues).
class Mcp::Tools::ResolveIssue < Mcp::Tools::TriageIssues
  self.tool_name = "resolve_issue"
  self.title = "Resolve issues"
  self.scope = "triage"
  self.annotations = TRIAGE
  self.triage_method = :resolve_all
  self.audit_action = "resolve"
  self.verb = "Resolved"
  self.description = "Mark issues as resolved (fixed). They reopen automatically as regressions if the error happens again. Takes 1 to #{MAX_ISSUES} issue short ids. Returns each issue's new status."
  self.input_schema = issues_schema
end
