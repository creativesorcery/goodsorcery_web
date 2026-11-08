# Good Sorcery MCP server

Good Sorcery runs a [Model Context Protocol](https://modelcontextprotocol.io) server, so AI clients such as Claude Code, Codex, Cursor and VS Code can query, investigate and triage your errors. You can ask things like "what's breaking in production since the last deploy?", "explain GS-42 and suggest a fix", or "resolve the timeouts we fixed this morning".

- **Endpoint:** `https://<your instance>/mcp` (`https://app.goodsorcery.com/mcp` on the hosted service). It uses the Streamable HTTP transport, stateless, with plain JSON responses.
- **Authentication:** a personal access token in an `Authorization: Bearer` header. OAuth isn't supported yet, so connectors in claude.ai and Claude Desktop can't connect.
- **Scope of a token:** one account, with your own access to it. The token acts as you.

## Creating a token

1. Open the user menu (bottom left) and choose **Access tokens**.
2. Name the token after the client and machine, for example "Claude Code on my laptop".
3. If you belong to several accounts, choose the account. Each token covers one account.
4. Choose scopes:
   - **Read** is always included: list apps, search and read issues, occurrences, uptime and performance.
   - **Triage** lets the client resolve, ignore and reopen issues and add notes, as you.
   - **Request data** adds request params, headers, session, user details, job arguments, frame locals and unredacted error messages to occurrence details. These are sent to your AI provider, so leave it off unless you need it.
5. Choose when it expires: 30 days, 90 days (the default), 1 year or never.
6. Copy the token. **It's shown only once.** The page also shows ready-to-paste configuration for each client.

You need a confirmed email address to create tokens. Each person can have up to 20 active tokens.

Revoke a token on the same page at any time; clients using it lose access at once. A token also stops working when it expires, or when you're removed from its account.

## Client configuration

Replace `<URL>` with your instance's URL and `<TOKEN>` with your token. The Access tokens page fills both in for you.

### Claude Code

```sh
claude mcp add --transport http goodsorcery <URL>/mcp --header "Authorization: Bearer <TOKEN>"
```

### Codex

In `~/.codex/config.toml`:

```toml
[mcp_servers.goodsorcery]
url = "<URL>/mcp"
bearer_token_env_var = "GOODSORCERY_TOKEN"
```

Then, in your shell profile:

```sh
export GOODSORCERY_TOKEN="<TOKEN>"
```

### Cursor

In `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "goodsorcery": {
      "url": "<URL>/mcp",
      "headers": { "Authorization": "Bearer <TOKEN>" }
    }
  }
}
```

### VS Code

In `.vscode/mcp.json`. VS Code asks for the token when it first connects and stores it securely, so the file holds no secret:

```json
{
  "inputs": [
    { "type": "promptString", "id": "goodsorcery-token", "description": "Good Sorcery access token", "password": true }
  ],
  "servers": {
    "goodsorcery": {
      "type": "http",
      "url": "<URL>/mcp",
      "headers": { "Authorization": "Bearer ${input:goodsorcery-token}" }
    }
  }
}
```

## Tools

Issues are named by their short id, such as `GS-42`; numeric issue ids work too. Apps are named by their slug (see `list_apps`).

| Tool | Scope | What it does |
|---|---|---|
| `list_apps` | read | Apps with slug, name, platform, environments, issue prefix and unresolved count. |
| `search_issues` | read | The issue list's search: `is:unresolved\|resolved\|ignored\|for_review\|new\|regressed`, `env:`, `level:`, `assigned:me\|none`, `user:`, `class:` and free text. Optional `app`, `sort` (`last_seen`, `first_seen`, `events`, `users`), `range` (`1h` to `90d`), `limit` (up to 50) and `cursor`. |
| `get_issue` | read | Summary, status, counts, 24-hour and 30-day trend, environments, releases, top tags, recent activity, and the latest occurrence's backtrace (app frames first, with code) and breadcrumbs. |
| `list_occurrences` | read | Stored occurrences of an issue, newest first: time, environment, release, host, transaction and occurrence id. Paged. |
| `get_occurrence` | read | One occurrence: backtrace, breadcrumbs, job details, environment and runtime. Request params, headers, session, user context and custom context your app added need the request data scope. |
| `get_uptime` | read | Uptime monitors: name, host, status, uptime over 24 hours, 7 and 30 days, and open incidents. Never the monitor URL. |
| `get_performance` | read | An app's performance overview for an environment and range (`15m`, `1h`, `1d`, and `7d`/`30d` when your plan keeps that much): average, p75, p90, p95, p99, rate, failure rate, time share, and the Slower and N+1 flags, for endpoints (`kind: web`) or jobs (`kind: job`). |
| `get_trace` | read | One kept trace: time by layer, the slowest spans, N+1 groups with their call site and code, and the error it reported. |
| `resolve_issue` | triage | Resolve 1 to 25 issues. |
| `ignore_issue` | triage | Ignore 1 to 25 issues. |
| `unresolve_issue` | triage | Reopen 1 to 25 issues. |
| `add_note` | triage | Add a note (up to 2,000 characters) to an issue. |

Read-only tokens don't see the triage tools at all. Nothing over MCP can change apps, API keys, alert rules, members, plans or uptime monitors, and nothing deletes data.

Every result has a short text part and the same facts as `structuredContent`. Unknown ids, and ids from other accounts, give the same "not found" error.

## Data and privacy

- **Captured data is untrusted.** Error messages, backtraces, code, breadcrumbs, request data and trace spans come from your applications and from whoever used them. They may contain text that looks like instructions to an AI. Tool descriptions and every result that holds captured data say so, and tell the client never to follow such instructions. Still, review what your AI client proposes before you let it act.
- **What leaves Good Sorcery:** whatever a tool returns goes to your AI client and, from there, to your AI provider. Data is scrubbed and redacted exactly as in the dashboard. Without the request data scope, error messages are redacted like issue titles (emails, numbers, tokens and similar replaced), and request data, user details, job arguments, frame locals and custom context your app added are left out (the runtime details and the causes' exception classes stay, with cause messages redacted too).
- **Never returned:** ingest API keys, monitor URLs, other secrets, and the token itself.
- **Audit:** triage actions and notes made through MCP are recorded with the token, and shown under each token on the Access tokens page ("Recent activity", the last 20). On the issue page they're marked "via MCP". Reads are logged with the tool name, token and duration only, never their arguments.
- **Password resets don't revoke tokens.** A reset signs you out of the dashboard everywhere, but your tokens keep working (most resets are forgotten passwords). If you think a token leaked, revoke it on the Access tokens page.
- **Retention:** revoked and expired tokens, and MCP activity, are deleted 90 days later.

## Limits

- 120 calls a minute per token, and 600 a minute per IP address. Over the limit you get HTTP 429 with `Retry-After: 60`.
- Request bodies up to 1 MiB.
- Pages of at most 50 issues or occurrences. Backtraces show up to 30 frames (code for the first 5 app frames), breadcrumbs the last 25, and long values are cut. Each part of a result (backtrace, breadcrumbs, params, headers and so on) also has a size budget, so a result stays under 50 KB even for the largest event ingest accepts; when a budget runs out, the rest is left out and the result says how much ("… 12 more frames", "8 more keys").
- Browser requests are accepted only from your instance's own origin.

## Errors

| HTTP | Meaning |
|---|---|
| 401 | Missing, invalid, expired or revoked token, or you're no longer a member of its account (leaving an account revokes your tokens for it). The response says only "invalid token". |
| 403 | A browser request from another origin. |
| 405 | `GET` or `DELETE`: the server is stateless and has no streams or sessions. |
| 413 | The request body is over 1 MiB. |
| 429 | Rate limited; retry after a minute. |

Tool problems, such as an unknown issue, come back as tool results with `isError: true` and a plain message.
