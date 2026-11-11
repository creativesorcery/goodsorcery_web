# Security policy

Good Sorcery stores error data that may contain personal information, so we
take vulnerability reports seriously.

## Reporting a vulnerability

Please **don't open a public issue, discussion or pull request** for a
vulnerability. Report it privately through GitHub's private vulnerability
reporting: go to the repository's **Security** tab and choose **Report a
vulnerability**, or open
<https://github.com/creativesorcery/goodsorcery_web/security/advisories/new>
directly.

Include what you can: the affected version or commit, steps to reproduce, and
the impact you expect. We'll acknowledge the report, keep you updated while we
work on a fix, and credit you in the advisory unless you'd rather stay
anonymous.

If that form isn't available to you, open a public issue (the bug report
template will do) that only asks a maintainer to get in touch about a security
report, with no details of the problem, and we'll arrange a private channel.

## Scope

- This repository: the Good Sorcery server (web app, ingest API, MCP endpoint,
  background jobs, Docker image and the deploy configuration).
- The hosted service at <https://app.goodsorcery.com>, which runs this code.
  Please test only against accounts you own, don't access or modify other
  people's data, and don't run load or denial-of-service tests against it.
- The client libraries have their own policies:
  [goodsorcery-ruby](https://github.com/creativesorcery/goodsorcery-ruby/security)
  and [goodsorcery-rust](https://github.com/creativesorcery/goodsorcery-rust/security).

## Supported versions

Fixes land on `main` and ship in the next release. Self-hosted instances run
pending database migrations when they boot, so upgrading is a redeploy of the
latest release (or `main`). Only the latest version gets security fixes.

## Security notes for self-hosters

These are deliberate design choices, not vulnerabilities, but you should know
them when you run an instance:

- **Every member of an account has full admin rights over it.** The
  owner/member role is recorded but not enforced: any member can change app
  settings and retention, reveal and rotate ingest keys, change Slack alerts
  and create or delete uptime monitors. There is no invite flow yet; members
  can only be added from the Rails console.
- **Tokenised links appear in proxy access logs.** Password-reset, email
  verification and alert-mute links carry their token in the query string.
  Rails filters it from its own logs, but reverse proxies in front of the app
  (kamal-proxy, Thruster, Cloudflare or your own) may log the full URL. Reset
  tokens are single-use and expire after 15 minutes; verification links expire
  after 3 days and mute links after 60 days. Treat proxy logs as sensitive.
- **Sign-up on a fresh instance is open until the first account exists.** Set
  `GOODSORCERY_DISABLE_SIGNUPS=1` and create the owner with
  `bin/rails goodsorcery:create_owner`, or sign up immediately after the first
  deploy (see README › First owner).
- **Production must be served over HTTPS.** The app sets `force_ssl`, so
  session and CSRF cookies are `Secure`.
