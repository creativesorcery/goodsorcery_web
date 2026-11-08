# The Access tokens page (docs/MCP.md): scope wording, status chips and the
# client configuration snippets shown once with a new token. Snippets are
# built as plain strings and rendered through ERB escaping.
module AccessTokensHelper
  SCOPE_LABELS = { "read" => "Read", "triage" => "Triage", "request_data" => "Request data" }.freeze
  SCOPE_DESCRIPTIONS = {
    "read" => "List apps, search and read issues, occurrences, uptime and performance. Always included.",
    "triage" => "Resolve, ignore and reopen issues, and add notes, as you.",
    "request_data" => "Include request params, headers, session, user details, job arguments and frame locals " \
                      "in occurrence details."
  }.freeze
  REQUEST_DATA_WARNING = "Request data sends request params, headers and user details captured from your apps to your " \
                         "AI provider. Leave it off unless you need it.".freeze
  EXPIRY_LABELS = { "30" => "30 days", "90" => "90 days", "365" => "1 year", "never" => "Never" }.freeze
  CLIENTS = { "claude_code" => "Claude Code", "codex" => "Codex", "cursor" => "Cursor", "vscode" => "VS Code" }.freeze
  SERVER_NAME = "goodsorcery".freeze
  TOKEN_VARIABLE = "GOODSORCERY_TOKEN".freeze

  def access_token_expiry_options = EXPIRY_LABELS.map { |value, label| [ label, value ] }

  # The URL AI clients connect to: this instance's public URL plus /mcp.
  def mcp_endpoint_url
    "#{Rails.configuration.x.public_url&.to_s || request.base_url}/mcp"
  end

  def access_token_status_chip(token)
    return chip("Revoked", tone: :muted, small: true) if token.revoked?
    return chip("Expired", tone: :muted, small: true) if token.expired?

    chip("Active", tone: :mint, small: true)
  end

  def access_token_scope_chips(token)
    safe_join(token.scopes.map { |scope| chip(SCOPE_LABELS.fetch(scope, scope), tone: :iris, small: true) }, " ")
  end

  def access_token_expiry(token)
    return "Never expires" if token.expires_at.nil?

    "#{token.expired? ? 'Expired' : 'Expires'} #{token.expires_at.to_date.to_fs(:long)}"
  end

  def access_token_last_used(token)
    token.last_used_at ? "Last used #{time_ago_compact(token.last_used_at)}" : "Never used"
  end

  # "Resolved GS-1020, GS-1001 · 2h ago": issue short ids, linked when in the current account.
  def access_token_activity_issues(activity, issues)
    links = activity.issue_ids.filter_map { |id| issues[id] }.map do |issue|
      issue.project.account_id == Current.account.id ? link_to(issue.short_id, project_issue_path(issue.project, issue), class: "font-mono text-iris-300 hover:underline") : tag.span(issue.short_id, class: "font-mono")
    end
    links.any? ? safe_join(links, ", ") : tag.span("issues no longer stored", class: "text-ink-400")
  end

  # [[label, text], …] for one client: the command or file to paste.
  def mcp_client_snippets(client, token)
    case client
    when "claude_code" then [ [ "terminal", claude_code_snippet(token) ] ]
    when "codex" then [ [ "~/.codex/config.toml", codex_config_snippet ], [ "shell profile", "export #{TOKEN_VARIABLE}=\"#{token}\"" ] ]
    when "cursor" then [ [ "~/.cursor/mcp.json", cursor_config_snippet(token) ] ]
    when "vscode" then [ [ ".vscode/mcp.json", vscode_config_snippet ] ]
    end
  end

  private
    def claude_code_snippet(token)
      "claude mcp add --transport http #{SERVER_NAME} #{mcp_endpoint_url} --header \"Authorization: Bearer #{token}\""
    end

    def codex_config_snippet
      "[mcp_servers.#{SERVER_NAME}]\nurl = \"#{mcp_endpoint_url}\"\nbearer_token_env_var = \"#{TOKEN_VARIABLE}\""
    end

    def cursor_config_snippet(token)
      JSON.pretty_generate(mcpServers: { SERVER_NAME => { url: mcp_endpoint_url, headers: { Authorization: "Bearer #{token}" } } })
    end

    def vscode_config_snippet
      JSON.pretty_generate(
        inputs: [ { type: "promptString", id: "goodsorcery-token", description: "Good Sorcery access token", password: true } ],
        servers: { SERVER_NAME => { type: "http", url: mcp_endpoint_url, headers: { Authorization: "Bearer ${input:goodsorcery-token}" } } }
      )
    end
end
