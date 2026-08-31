# solyto deployment

<!--
This is your project context, loaded by the agent at the start of every session.
manigot is vendor-agnostic: it runs Claude Code or OpenCode against the same
project (`mg --profile claude-pro` vs `mg --profile zai`/`--profile
opencode-go`/`--profile opencode-zen`), and this one file serves both — manigot mounts it read-only
wherever the selected tool looks for it
(/workspace/AGENTS.md for OpenCode, /workspace/.claude/CLAUDE.md for Claude
Code). Those mount paths are read-only: to change this context, edit this
file (docs/AGENTS.md), never the mount paths.
The same global agents are available under @name either way, and custom
project agents in docs/agents/ work under both tools — write them in the
built-in format (name:, description:, tools: Read, Grep, ...), no per-tool
format needed. To make a custom agent read-only under OpenCode, add a
`permission:` frontmatter block (the built-in format manigot's conversion
passes through to OpenCode's schema — see the manigot README's agent section);
the read-only built-in agents' blocks deny the destructive git commands
(worktree management, branch -d/-D, reset, checkout, push, ...).
Custom agents that must commit (like the built-in developer/reviewer/quality)
declare `commit: true` in their frontmatter; agents that never commit declare
`commit: false` and get a read-only git mount. The default — no agent named,
file missing, or marker absent/unknown — is a writable git mount, so a
committing agent is never broken by a missing marker.
Agent sessions also restrict git to reading history and making commits (the
session git shim): worktree management, branch deletes, resets, checkouts,
pushes, and the other destructive subcommands are refused.
The manigot TUI's job detail view also offers a `t` key that opens the job's
branch diff in tig (`mg diff <job> --tig`) in a tmux split pane / new
terminal, gated on tig being installed on the host.
Copying text from inside a session uses OSC 52: your terminal emulator must
support it, and tmux needs `set-clipboard on` when the session runs inside
tmux (mg forwards your terminal environment into the container and warns at
session start when it detects tmux would swallow the clipboard writes — see
the manigot README's "Clipboard / copying from agent sessions" section).
The `shot` tool (`/usr/local/bin/shot`, see the manigot README's PLAYWRIGHT
doc) renders a URL to a PNG + model-free render report. The developer agent
uses it to verify rendered work; read-only agents consume the artifacts and
never run it.
Keep this file tool-neutral — write it for "the agent", not for one vendor.
-->

Ansible deployment repo for Solyto, a multi-service web platform (a Laravel API, two Node.js frontends, and a database stack). It contains the playbooks, per-environment inventories, and Jinja2 templates that deploy each service as a Docker Compose stack onto a single server (host group `solyto`). No application code lives here: the playbooks rsync the service source trees (`api/`, `app/`, `landing-page/`) from adjacent directories to the target host at deploy time.

## Stack
- Backend: Laravel API on PHP 8.4 php-fpm, deployed as five containers — nginx (alpine) reverse proxy, `php` (composer install + artisan), `dav` (WebDAV via `dav.php`), `queue` (`artisan queue:work --tries=3 --timeout=300`), and imgproxy for image resizing. Secrets are injected as Docker secrets from `secrets/` files.
- Frontend: two Node.js 22 (Alpine) services, multi-stage Docker builds (`npm ci` + `npm run build`, then `node build --port …`) — `app` (my.solyto.app, port 3000) and `landing-page` (solyto.app, port 3001). Both join the external `api` Docker network.
- Database: the `db` stack runs MariaDB 12, PostgreSQL 17, and Redis 7.4.1, plus a `cli` helper container with mariadb/postgresql clients. Optional read replicas are gated on `enable_read_replicas`.
- Key packages: Ansible (playbooks, `template`, `synchronize`/rsync, `shell`), Docker Compose on the remote host, and Make as the deploy wrapper. `roles_path = roles` is configured in `ansible.cfg` but no `roles/` directory exists yet.

## Architecture
- `playbooks/` — one playbook per service (`api.yml`, `app.yml`, `landing-page.yml`, `db.yml`). Each targets the `solyto` group and follows the same flow: create the external Docker networks (`api`, `db`) → scaffold `{{ target_base_path }}/<service>/` → template `.env` (mode 0600) and the Docker setup → rsync `<service>/` source from `local_project_root` into `src/` (excluding `node_modules`/`vendor`/`.env`/`build`/`*.sqlite`) → `docker compose build` → `docker compose up -d --remove-orphans`. `api.yml` additionally runs `php/startup.sh` inside the php container (`migrate --force`, `cache:clear`, `config:cache`, `route:cache`).
- `inventory/{production,development}/` — per-environment hosts and group vars. Production `hosts.ini` is gitignored; copy `hosts.ini.example` and set `ansible_user` / `ansible_ssh_private_key_file`. `group_vars/all.yml` defines shared paths (`local_project_root` = repo root, `target_base_path` = `/home`, `deploy_user`, `secrets_path`, `src_path`); service vars hold versions and domains (e.g. `api_version` tracks the release tags). Note: playbooks hardcode `vars_files: ../inventory/production/group_vars/<service>.yml`, so the development group_vars are not actually wired in yet — `-i` only changes which hosts are targeted.
- `templates/<service>/` — Jinja2 templates (compose.yml, Dockerfiles, nginx config, php.ini, startup.sh, `.env`) rendered onto the host during deploy. The `.env.j2` files are currently empty.
- Secrets: the host's `<service>/secrets/` directory (0700) holds plaintext secret files (db credentials, Laravel `APP_KEY`, third-party API keys) mounted as Docker secrets (`/run/secrets/*`) by compose. Never print or commit them.
- Deployments go straight to a running host: each playbook `rm -rf`s the remote `src/`, rebuilds images, and recreates containers — there is no rollback step.

## Commands
- `cp inventory/production/hosts.ini.example inventory/production/hosts.ini` — first-time setup; fill in `ansible_user` and `ansible_ssh_private_key_file`.
- `make deploy-api` | `make deploy-app` | `make deploy-landing-page` | `make deploy-db` — deploy one service. `make deploy` — api + app.
- `ansible-playbook playbooks/<service>.yml` — deploy directly; `ansible.cfg` defaults to the **production** inventory. Use `-i inventory/development/hosts.ini` for the dev host.
- `ansible-playbook --syntax-check playbooks/<service>.yml` and `ansible-playbook --list-hosts playbooks/<service>.yml` — validate without deploying. There is no test/build/dev workflow in this repo; service builds happen remotely via `docker compose build`.

## Hard rules
- NEVER modify files outside /workspace.
- The default inventory is **production**: never run a playbook against it without explicit confirmation — use `--check`/`--list-hosts` or the development inventory when unsure.
- Deploys `rm -rf` the remote `src/` and recreate containers; the api deploy also runs `php artisan migrate --force` on the host. Flag any change touching `startup.sh.j2` or adding manual migration/db steps before running anything.
- NEVER edit `inventory/production/hosts.ini` (gitignored, real servers) or touch `secrets/` content without flagging it; never print or commit secrets.
- NEVER install packages without asking (e.g. Ansible collections, Python deps).
- When scope is unclear: ask, don't guess.
- Do not refactor things unrelated to the current task.
- Do not add abstractions not already present in the codebase.
