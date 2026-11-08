# unresolve_issue: Reopen resolved or ignored issues (mark them unresolved again). Needs the triage scope (Mcp::Tools::TriageIssues).
class Mcp::Tools::UnresolveIssue < Mcp::Tools::TriageIssues
  self.tool_name = "unresolve_issue"
  self.title = "Reopen issues"
  self.scope = "triage"
  self.annotations = TRIAGE
  self.triage_method = :reopen_all
  self.audit_action = "unresolve"
  self.verb = "Reopened"
  self.description = "Reopen resolved or ignored issues (mark them unresolved again). Takes 1 to #{MAX_ISSUES} issue short ids. Returns each issue's new status."
  self.input_schema = issues_schema
end
