# Notes for AI coding agents

`CLAUDE.md` is this project's agent guide, whichever agent you are: read it
first. It covers the stack, conventions, commands and the gotchas that have
bitten before. `CONTRIBUTING.md` applies to you as well: work on a branch and
open a pull request against `main`; never push to `main`. Private,
machine-specific notes belong in `CLAUDE.local.md`, which is git-ignored and
must never be committed.

## Database migrations

Self-hosted installs run migrations by themselves at boot, often jumping many
releases at once. A bad migration leaves someone's instance unable to start.
Before writing or reviewing a migration, read
[docs/MIGRATIONS.md](docs/MIGRATIONS.md); its rules are binding. Never:

- edit, rename, renumber or delete a migration that is already on `main`;
- use app models, constants, config files or `ENV` inside a migration;
- write a migration that only makes sense for the hosted service;
- break the previous release's code (expand, then contract);
- bulk-update a table that grows with traffic inside a migration;
- wrap an operation in `safety_assured` just to silence `strong_migrations`.
