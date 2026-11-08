# The MCP tools, in the order tools/list shows them, and the ones a token's
# scopes allow: read tools always, triage tools with the triage scope.
# (request_data changes what get_issue and get_occurrence include, not the
# list.) Nothing touches apps, keys, alert rules, members, entitlements or
# uptime settings, and nothing deletes.
module Mcp::Catalog
  READ_TOOLS = [
    Mcp::Tools::ListApps, Mcp::Tools::SearchIssues, Mcp::Tools::GetIssue, Mcp::Tools::ListOccurrences,
    Mcp::Tools::GetOccurrence, Mcp::Tools::GetUptime, Mcp::Tools::GetPerformance, Mcp::Tools::GetTrace
  ].freeze
  TRIAGE_TOOLS = [ Mcp::Tools::ResolveIssue, Mcp::Tools::IgnoreIssue, Mcp::Tools::UnresolveIssue, Mcp::Tools::AddNote ].freeze
  TOOLS = (READ_TOOLS + TRIAGE_TOOLS).freeze

  module_function

  def tools_for(token) = TOOLS.select { |tool| token.scope?(tool.scope) }

  def names_for(token) = tools_for(token).map(&:tool_name)
end
