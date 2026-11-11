# Deploying to production

Every push to `main` (a direct push or a merged pull request) runs CI. Once
every check passes, the `deploy` job in `.github/workflows/ci.yml` builds the
image, pushes it to GHCR and runs `bin/kamal deploy` over SSH. The deploy job
only runs in the upstream repository; to deploy your own fork, see
[Deploying from a fork](#deploying-from-a-fork). You can also run
`bin/kamal deploy` from your own machine with the same variables exported.

Cloudflare terminates TLS here. If you deploy differently, the app must still
be served over HTTPS (`force_ssl` is on); see "Plain Docker" in the README for
Thruster's built-in TLS.

Everything runs on one server:

```
visitor ──HTTPS──▶ Cloudflare (DNS proxy, TLS)
                        │
                        ▼  outbound-only tunnel
  server ┌──────────────────────── Docker network "kamal" ───────────────────────┐
         │ goodsorcery_web-tunnel (cloudflared) ──HTTP──▶ kamal-proxy ──▶ web     │
         │                                                               job (Sidekiq + sidekiq-cron)
         │ goodsorcery_web-db (Postgres 18)    goodsorcery_web-redis (Redis 8)    │
         └────────────────────────────────────────────────────────────────────────┘
  open inbound ports: SSH only (key only, on KAMAL_SSH_PORT). No HTTP ports are published.
```

## Keeping the server private in a public repo

- `config/deploy.yml` holds no hosts or secrets. Kamal reads the host, SSH
  port and domain from `KAMAL_WEB_HOST`, `KAMAL_SSH_PORT` (default 22) and
  `GOODSORCERY_HOST`, and every secret from
  the environment through `.kamal/secrets`.
- In GitHub, all of them live in the `production` environment, which only
  `main` may deploy from. `KAMAL_WEB_HOST` is stored as a **secret** (not a
  variable), so GitHub masks the IP wherever Kamal prints it in the public
  Actions log.
- Cloudflare Tunnel means no DNS record points at the server. Don't add `A` or
  `AAAA` records for it, and don't send mail directly from the server (use an
  SMTP provider), or its IP will show up in DNS or email headers.
- Fork pull requests run the tests without secrets and never reach the deploy
  job. The workflow uses `pull_request`, never `pull_request_target`.

## One-time setup

### 1. Server

Use Ubuntu LTS on amd64 (the image is built for `amd64`; change `builder.arch`
in `config/deploy.yml` for an arm64 server). As root:

```sh
curl -fsSL https://get.docker.com | sh
adduser --disabled-password --gecos "" deploy
usermod -aG docker deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
# Add your own public key and the CI deploy key (step 4) to:
#   /home/deploy/.ssh/authorized_keys   (owner deploy, mode 600)

# SSH: keys only, no root login. If you move SSH off port 22, also set
# KAMAL_SSH_PORT (below) and open that port instead of OpenSSH.
printf 'PasswordAuthentication no\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/00-hardening.conf
systemctl reload ssh
# sshd keeps the first value it reads, and cloud images often ship
# 50-cloud-init.conf with PasswordAuthentication yes, so the 00- prefix matters.
# Check: sshd -T | grep -i passwordauthentication   (should say no)

# Firewall: SSH only. Nothing else needs to be reachable; the tunnel connects out.
ufw default deny incoming && ufw allow OpenSSH && ufw --force enable   # or: ufw allow SSH_PORT/tcp
```

Docker-published ports bypass `ufw`, which is why `deploy.yml` publishes none:
kamal-proxy runs with `publish: false`, and Postgres, Redis and cloudflared
only listen on the private `kamal` network.

### 2. Cloudflare

1. Add your domain to Cloudflare.
2. **Zero Trust → Networks → Tunnels → Create a tunnel** (type *Cloudflared*).
   Name it, then copy the token from the install command. This is
   `CLOUDFLARE_TUNNEL_TOKEN`; you don't need to install anything on the server
   yourself, because Kamal runs cloudflared as an accessory.
3. Add a **public hostname** to the tunnel: your subdomain (for example
   `errors.example.com`) with service type **HTTP** and URL **`kamal-proxy:80`**.
   Cloudflare creates the proxied DNS record for you.
4. The ingest API is called by servers, not browsers. Make sure Bot Fight Mode,
   browser integrity checks and challenges don't apply to `/api/`: turn Bot
   Fight Mode off, or add a WAF custom rule that skips them for
   `starts_with(http.request.uri.path, "/api/")`.

### 3. Postmark (optional)

Mail (password resets, sign-up confirmations, alerts) goes through Postmark's
API when `POSTMARK_API_TOKEN` is set, which also keeps the server's IP out of
email headers. To use another provider over SMTP instead, skip this step and
follow "Email" in the README; `SMTP_USERNAME` and `SMTP_PASSWORD` then need
passing through as described in [Other variables](#other-variables).

1. Create a server in Postmark and copy its **Server API token**
   (`POSTMARK_API_TOKEN`). Use the default transactional stream.
2. **Sender Signatures → Add Domain** for the domain you send from (by default
   `GOODSORCERY_HOST`, or the domain in `GOODSORCERY_MAIL_FROM`), then add the
   DKIM and Return-Path DNS records it shows in Cloudflare.
3. Leave link tracking off for the server, so reset links go straight to
   your app instead of through Postmark's redirector.

### 4. Secrets

Generate the app secrets once and keep them in a password manager. Back up the
encryption keys separately from the database; losing them makes stored data
unreadable (see "Secrets" in `README.md`).

```sh
bin/rails secret                     # SECRET_KEY_BASE
bin/rails db:encryption:init         # the three ACTIVE_RECORD_ENCRYPTION_* values
openssl rand -hex 32                 # GOODSORCERY_WEB_DATABASE_PASSWORD

ssh-keygen -t ed25519 -N "" -C "goodsorcery_web deploy" -f goodsorcery_deploy
# goodsorcery_deploy.pub goes into the server's authorized_keys (step 1);
# goodsorcery_deploy (private) becomes SSH_PRIVATE_KEY.

ssh-keyscan -p SSH_PORT -t ed25519 SERVER_IP   # becomes SSH_KNOWN_HOSTS
```

Compare the `ssh-keyscan` output with `/etc/ssh/ssh_host_ed25519_key.pub` on
the server before you trust it. On a port other than 22 the line starts with
`[SERVER_IP]:SSH_PORT`; keep it that way, since that's how SSH matches it.

In GitHub: **Settings → Environments → New environment** named `production`.
Under *Deployment branches and tags*, choose *Selected branches* and allow
only `main`. Then add:

| Kind | Name | Value |
|---|---|---|
| secret | `KAMAL_WEB_HOST` | the server's IP address |
| secret | `KAMAL_SSH_PORT` | the server's SSH port (`22` if unchanged) |
| secret | `SSH_PRIVATE_KEY` | the private deploy key |
| secret | `SSH_KNOWN_HOSTS` | the `ssh-keyscan` line |
| secret | `SECRET_KEY_BASE` | from `bin/rails secret` |
| secret | `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | from `db:encryption:init` |
| secret | `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | from `db:encryption:init` |
| secret | `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | from `db:encryption:init` |
| secret | `GOODSORCERY_WEB_DATABASE_PASSWORD` | the database password |
| secret | `POSTMARK_API_TOKEN` | optional: the Postmark **server** API token (Servers → your server → API Tokens); without it, configure SMTP |
| secret | `GOODSORCERY_API_KEY` | optional: an ingest key for an app that tracks this instance's own errors (create the app on this instance or another one); unset, the gem sends nothing. See "Self-reporting" in the README |
| variable | `GOODSORCERY_HOST` | the public hostname, e.g. `errors.example.com` |
| variable | `GOODSORCERY_MAIL_FROM` | optional: the sender, e.g. `Good Sorcery <no-reply@example.com>`; defaults to `no-reply@GOODSORCERY_HOST` |
| variable | `GOODSORCERY_DISABLE_SIGNUPS` | recommended: `1` closes sign-up even before the first account exists; create the owner with `goodsorcery:create_owner` (step 6) |
| variable | `GOODSORCERY_ENABLE_SIGNUPS` | optional: `1` keeps public sign-up open after the first account; unset or anything else closes it |
| variable | `KAMAL_IMAGE` | optional: the GHCR image name without `ghcr.io/`, e.g. `your-user/goodsorcery_web` (lowercase). CI defaults it to the repository's own name; Kamal's own default is `creativesorcery/goodsorcery_web`, which only the upstream repository can push to |
| variable | `KAMAL_SSH_USER` | optional: the server user Kamal logs in as, if not `deploy` |
| variable | `GOODSORCERY_HOSTED` | optional: `1` turns on hosted mode (entitlements and "Upgrade to unlock"); unset is self-hosted. After switching, run `goodsorcery:fit_entitlements` (see below) |
| variable | `GOODSORCERY_APM_RETENTION_DAYS` | optional, self-hosted only: days of performance data to keep, 1–30 (default 30) |
| variable | `GOODSORCERY_UPGRADE_URL` | optional, hosted only: where "Upgrade to unlock" links to. Unset, locked options say "Coming soon" and no upgrade text shows |
| variable | `GOODSORCERY_TERMS_URL` | optional: an http(s) link to your Terms of Service. Set, the sign-up page says "By signing up you agree to the Terms of Service." with it linked |
| variable | `GOODSORCERY_PRIVACY_URL` | optional: an http(s) link to your Privacy Policy, linked the same way. With neither set, the sign-up page shows no agreement sentence |
| variable | `GOODSORCERY_ENDPOINT` | optional: where this instance's gem reports its own errors and performance data; self-hosted it defaults to this instance's own public URL (`https://GOODSORCERY_HOST`), hosted (`GOODSORCERY_HOSTED`) to `https://app.goodsorcery.com` |
| variable | `GOODSORCERY_PERFORMANCE_MONITORING` | optional: `0` turns off performance monitoring of this instance (on by default, with `GOODSORCERY_API_KEY` set and a gem version that supports it) |

The registry login uses the workflow's own `GITHUB_TOKEN`, so there's no
registry secret. The image goes to `ghcr.io/KAMAL_IMAGE` (by default the
repository's own package), and GHCR packages are private by default, which is
fine: the server pulls with the same login. `CLOUDFLARE_TUNNEL_TOKEN` stays out of GitHub: only the
one-time accessory boot below needs it.

### 5. Repository settings

- **Branch protection (or a ruleset) on `main`:** require pull requests and
  the CI checks, and block force pushes. Allow direct pushes only for yourself.
- **Settings → Actions → General:** require approval for workflows from
  outside contributors' forks.
- **Settings → Environments → production:** add yourself as a required
  reviewer, so no push to `main` reaches the production secrets unreviewed.
- **Settings → Advanced Security:** turn on private vulnerability reporting
  (the reporting link in `SECURITY.md` needs it), secret scanning with push
  protection, and Dependabot security updates. GitHub offers some of these
  only once the repository is public.

### 6. First boot

From your laptop, with the values from step 4 exported in your shell
(including `KAMAL_WEB_HOST`, `KAMAL_SSH_PORT`, `GOODSORCERY_HOST`,
`KAMAL_IMAGE` (the same image name CI uses, e.g. `your-user/goodsorcery_web`;
unset, Kamal uses `creativesorcery/goodsorcery_web`) and, if
your server user isn't `deploy`, `KAMAL_SSH_USER`). Kamal passes its own user
and port to SSH, overriding `User` and `Port` from an `~/.ssh/config` alias (plus a
GitHub personal access token with `read:packages` as `KAMAL_REGISTRY_PASSWORD`
and your GitHub username as `KAMAL_REGISTRY_USERNAME`):

```sh
bin/kamal accessory boot all     # Postgres, Redis and the tunnel
```

Then push to `main` (or re-run the latest CI run). The deploy job starts
kamal-proxy, boots the web and job containers and runs migrations
(`bin/docker-entrypoint` runs `db:prepare`; it never loads the development
demo data in `db/seeds.rb`).

**Create the first owner straight away.** Until the first account exists,
anyone who finds `https://GOODSORCERY_HOST` can sign up and become the
instance's owner. Either set `GOODSORCERY_DISABLE_SIGNUPS=1` (step 4) before
this first deploy and create the owner from your laptop:

```sh
bin/kamal app exec -i --reuse 'bin/rails goodsorcery:create_owner EMAIL=you@example.com NAME="Your Name" ACCOUNT="Acme"'
```

It prompts for the password without echoing it; add `STAFF=1` inside the
quotes to also grant the staff area. Or, without that variable, open
`https://GOODSORCERY_HOST` and sign up the moment the deploy finishes; sign-up
closes after the first account. Grant staff later with
`bin/kamal app exec --reuse 'bin/rails goodsorcery:make_staff EMAIL=you@example.com'`.

Request bodies over 4 MiB get a 413 before they are read: Puma enforces
`http_content_length_limit` (`config/puma.rb`) and Thruster `MAX_REQUEST_BODY`
(set in the `Dockerfile`). The largest ingest body is 2 MiB, so a server
without Cloudflare in front still refuses oversized uploads.

## Day to day

- **Deploy:** merge to `main`. Deploys queue rather than overlap.
- **Roll back:** `bin/kamal rollback VERSION` (a git SHA from `bin/kamal app images`), or revert the commit on `main`.
  Neither runs migrations backwards, so the previous release runs against the new schema. Migrations keep that working: a column the code stops using stays (ignored with `ignored_columns`) and is dropped one release later. The full rules are in [MIGRATIONS.md](MIGRATIONS.md).
- **Console, logs:** `bin/kamal console`, `bin/kamal logs`, `bin/kamal logs -r job`, `bin/kamal dbc`.
- **Scheduled jobs:** sidekiq-cron runs `config/schedule.yml` inside the job
  container (the full list is under "Scheduled tasks" in the README), so the
  server needs no cron. If the job container is down, retention, alerts,
  digests and uptime checks all stop. The rake tasks still work by hand:
  `bin/kamal app exec "bin/rails goodsorcery:prune"`.
- **Performance data:** batches from the gem (`config.performance_monitoring`)
  are processed on the `apm` Sidekiq queue (weight 2, after `ingest`). Each job
  is short and database-bound; a gem process sends at most two batches a
  minute. `GOODSORCERY_APM_RETENTION_DAYS` (self-hosted, 1–30, default 30)
  sets how long hourly figures and traces are kept.
- **Uptime checks:** they run on the `uptime` Sidekiq queue. A check waits on
  the network for up to about 20 seconds (two 10-second attempts), so one
  Sidekiq thread manages roughly 60 / (average check seconds) checks a minute,
  and the total is that times `SIDEKIQ_CONCURRENCY`. With many monitors, add a
  job role that runs only that queue (`bundle exec sidekiq -q uptime`, with its
  own `SIDEKIQ_CONCURRENCY`) so slow checks never hold up ingest or alerts.
  Keep the existing `job` role on `config/sidekiq.yml`, which runs every queue:
  a process started with a hand-picked `-q` list silently skips the queues it
  leaves out. Each due monitor is claimed once, so several processes can share
  the queue.
  After switching `GOODSORCERY_HOSTED` on or off, or editing
  `config/entitlements.yml`, run
  `bin/kamal app exec "bin/rails goodsorcery:fit_entitlements"` (formerly
  `goodsorcery:fit_uptime_monitors`, still an alias). It fits uptime monitors
  and each app's error retention. Switching it off without the task leaves
  monitors paused under hosted limits unchecked.
- **Accessories:** `bin/kamal accessory logs tunnel`. Upgrading Postgres to a
  new major version needs a dump and restore.

## Other variables

`config/deploy.yml` passes only some of the README's environment variables to
the containers: the required ones and the optional variables listed in the
table above. To use another one (for example `GOODSORCERY_EXTRA_HOSTS`,
`GOODSORCERY_DOCS_URL`, `REDIS_CACHE_URL`, `SIDEKIQ_CONCURRENCY`,
`WEB_CONCURRENCY`, or `SMTP_USERNAME` / `SMTP_PASSWORD`), add it to `env.clear`
(or `env.secret` and `.kamal/secrets` for secrets) in `config/deploy.yml`, and
to the deploy step's `env` in `.github/workflows/ci.yml` (from `vars.` or
`secrets.`) if CI deploys. A variable set only in GitHub has no effect on its
own.

## Deploying from a fork

The `deploy` job is guarded by `github.repository == 'creativesorcery/goodsorcery_web'`,
so forks run the checks but never try to deploy. To deploy your fork from CI:

1. Change that repository name in `.github/workflows/ci.yml` to your fork's
   (`your-user/goodsorcery_web`).
2. Do the one-time setup above in your fork's settings. `KAMAL_IMAGE` defaults
   to your repository's name in lowercase, which is where the workflow's
   `GITHUB_TOKEN` can push; set the `KAMAL_IMAGE` variable only to use another
   name, and export the same value when you run Kamal locally.
3. Keep your fork's `main` in sync with upstream to get fixes; each deploy runs
   the new migrations at boot (see [MIGRATIONS.md](MIGRATIONS.md)).

## Accessories are managed by hand

CI only deploys the app. Postgres, Redis and cloudflared keep running across
deploys, and **merging a change to an accessory in `deploy.yml` (such as a new
image version) does not apply it**. Run the change from your laptop:

| Situation | Command | Needs |
|---|---|---|
| Restart (stuck, or after a server reboot) | `bin/kamal accessory restart tunnel` | `KAMAL_WEB_HOST`, `KAMAL_SSH_PORT`, `GOODSORCERY_HOST` |
| New image version or rotated secret | `bin/kamal accessory reboot tunnel` | the above, every secret in `.kamal/secrets` the accessory uses, and the registry login from "First boot" |

`reboot` recreates the container and re-uploads its env file from your shell.
For the tunnel, export `CLOUDFLARE_TUNNEL_TOKEN` first: an empty value takes
the tunnel, and the site, down. The token deliberately isn't stored in GitHub,
since anyone holding it can run a connector for your hostname.

## Backups

Nothing backs up Postgres yet. At minimum, schedule a nightly
`docker exec goodsorcery_web-db pg_dump -U goodsorcery_web -Fc goodsorcery_web_production`
on the server and copy the dump off it. Dumps hold encrypted error data, which
is useless without the `ACTIVE_RECORD_ENCRYPTION_*` keys, so store the keys
somewhere else.
