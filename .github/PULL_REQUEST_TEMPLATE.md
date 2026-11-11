## What and why

<!-- What does this change, and why? Link the issue it addresses (e.g. "Closes #123"). -->

## How it was tested

<!-- The tests you added or changed, and anything you checked by hand. -->

## Checklist

- [ ] Tests cover every behaviour change, including authorization tests (another account gets 404) for new controller actions.
- [ ] `bin/ci` passes (RuboCop, Brakeman, the audits, tests, seed check), and `bin/rails test:system` if the UI changed.
- [ ] Captured error data, API keys, tokens and monitor URLs never reach job arguments, Redis, the cache, logs, broadcasts or exception messages.
- [ ] Docs are updated where behaviour, commands or environment variables changed (README, `docs/`, `CLAUDE.md`).
- [ ] **Migrations:** none, or they follow [docs/MIGRATIONS.md](https://github.com/creativesorcery/goodsorcery_web/blob/main/docs/MIGRATIONS.md) (never edit a merged migration, no app code, expand then contract, fast on big tables), and `db/schema.rb` is included.
- [ ] Screenshots attached for visible UI changes (desktop and phone width).
