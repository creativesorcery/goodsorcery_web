# Deploying to production

Every push to `main` (a direct push or a merged pull request) runs CI. Once
every check passes, the `deploy` job in `.github/workflows/ci.yml` builds the
image, pushes it to GHCR and runs `bin/kamal deploy` over SSH.

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
  open inbound ports: 22 (SSH, key only). No HTTP ports are published.
```

## Keeping the server private in a public repo

- `config/deploy.yml` holds no hosts or secrets. Kamal reads the host and
  domain from `KAMAL_WEB_HOST` and `GOODSORCERY_HOST`, and every secret from
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
# Add your own public key and the CI deploy key (step 3) to:
#   /home/deploy/.ssh/authorized_keys   (owner deploy, mode 600)

# SSH: keys only, no root login.
printf 'PasswordAuthentication no\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/90-hardening.conf
systemctl reload ssh

# Firewall: SSH only. Nothing else needs to be reachable; the tunnel connects out.
ufw default deny incoming && ufw allow OpenSSH && ufw --force enable
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

### 3. Secrets

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

ssh-keyscan -t ed25519 SERVER_IP     # becomes SSH_KNOWN_HOSTS
```

Compare the `ssh-keyscan` output with `/etc/ssh/ssh_host_ed25519_key.pub` on
the server before you trust it.

In GitHub: **Settings → Environments → New environment** named `production`.
Under *Deployment branches and tags*, choose *Selected branches* and allow
only `main`. Then add:

| Kind | Name | Value |
|---|---|---|
| secret | `KAMAL_WEB_HOST` | the server's IP address |
| secret | `SSH_PRIVATE_KEY` | the private deploy key |
| secret | `SSH_KNOWN_HOSTS` | the `ssh-keyscan` line |
| secret | `SECRET_KEY_BASE` | from `bin/rails secret` |
| secret | `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | from `db:encryption:init` |
| secret | `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | from `db:encryption:init` |
| secret | `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | from `db:encryption:init` |
| secret | `GOODSORCERY_WEB_DATABASE_PASSWORD` | the database password |
| variable | `GOODSORCERY_HOST` | the public hostname, e.g. `errors.example.com` |

The registry login uses the workflow's own `GITHUB_TOKEN`, so there's no
registry secret. `CLOUDFLARE_TUNNEL_TOKEN` stays out of GitHub: only the
one-time accessory boot below needs it.

### 4. Repository settings

- **Branch protection (or a ruleset) on `main`:** require pull requests and
  the CI checks, and block force pushes. Allow direct pushes only for yourself.
- **Settings → Actions → General:** require approval for workflows from
  outside contributors' forks.

### 5. First boot

From your laptop, with the values from step 3 exported in your shell (plus a
GitHub personal access token with `read:packages` as `KAMAL_REGISTRY_PASSWORD`
and your GitHub username as `KAMAL_REGISTRY_USERNAME`):

```sh
bin/kamal accessory boot all     # Postgres, Redis and the tunnel
```

Then push to `main` (or re-run the latest CI run). The deploy job starts
kamal-proxy, boots the web and job containers and runs migrations
(`bin/docker-entrypoint` runs `db:prepare`). Open `https://GOODSORCERY_HOST`
and sign up; sign-up closes after the first account.

## Day to day

- **Deploy:** merge to `main`. Deploys queue rather than overlap.
- **Roll back:** `bin/kamal rollback VERSION` (a git SHA from `bin/kamal app images`), or revert the commit on `main`.
- **Console, logs:** `bin/kamal console`, `bin/kamal logs`, `bin/kamal logs -r job`, `bin/kamal dbc`.
- **Scheduled jobs:** sidekiq-cron runs `config/schedule.yml` inside the job
  container: the retention sweep daily and the stale-event requeue every 10
  minutes. The rake tasks still work by hand: `bin/kamal app exec "bin/rails goodsorcery:prune"`.
- **Accessories:** `bin/kamal accessory logs tunnel`, `bin/kamal accessory reboot redis`.
  Upgrading Postgres to a new major version needs a dump and restore.

## Backups

Nothing backs up Postgres yet. At minimum, schedule a nightly
`docker exec goodsorcery_web-db pg_dump -U goodsorcery_web -Fc goodsorcery_web_production`
on the server and copy the dump off it. Dumps hold encrypted error data, which
is useless without the `ACTIVE_RECORD_ENCRYPTION_*` keys, so store the keys
somewhere else.
