# Backlog: deploys copy local, ignored files to the server

created: 2026-11-17
updated: 2026-11-17 (option 1 decided by the owner, ready for implementation)

## Job (decided, do exactly this)

The deploy playbooks rsync the **local working tree** of each project to the
server. Everything that isn't excluded goes along, including files git ignores
(shell history, editor and agent folders, a local database backup) and, for
app and landing page, the whole `.git` folder.

Change the four source-copying playbooks to deploy **what git tracks at
`HEAD`**, using `git archive`:

| Playbook | Copy step | Repo |
|---|---|---|
| `playbooks/api.yml` | "Copy new source", `:66-72` | `{{ local_project_root }}/{{ api_path }}` |
| `playbooks/app.yml` | "Copy new source", `:44-50` | `{{ local_project_root }}/{{ app_path }}` |
| `playbooks/landing-page.yml` | "Copy new source", `:44-50` | `{{ local_project_root }}/{{ landing_page_path }}` |
| `playbooks/docs.yml` | "Copy new source", `:45-51` | `{{ local_project_root }}/{{ docs_path }}` |

For each:
1. **On the control machine** (`delegate_to: localhost`, `run_once`): create a
   temporary directory and extract `git -C <repo> archive --format=tar HEAD`
   into it.
2. **Before that, warn about uncommitted changes:** run `git -C <repo> status
   --porcelain` and, if it prints anything, show it with a `debug` message
   ("not deployed: …"). **Do not fail.** (The api checkout always has a
   modified `.env.testing`; failing would block every deploy.)
3. **Sync the temporary directory** to the server path the playbook uses today
   (same `dest`, same `--chown` options), instead of the working tree.
4. **Keep each playbook's existing excludes** that still apply to tracked
   files, so the server gets the same content as before minus the untracked
   files: api keeps `--exclude=tests` (and the others are now redundant but
   harmless); docs keeps `--exclude=/docs --exclude=AGENTS.md
   --exclude=.manigot`.
5. **Remove the temporary directory** afterwards (also when a later step
   fails: use `block`/`always`).

Everything else in the playbooks stays as it is: the "Remove old source" step,
templates, `docker compose build`, `up -d`, `startup.sh`.

## Why this is enough (verified 2026-11-17)

- All builds run on the server from tracked files: `composer install` (api,
  `templates/api/php/Dockerfile.j2:44`), `npm ci` + `npm run build` (app,
  landing page, docs). Lockfiles are tracked.
- `.env` files come from `templates/*/.env.j2`, not from the working tree.
- `api/public/storage` (the `storage:link` symlink, gitignored) is not needed:
  nginx serves `/storage/` with `alias /var/www/storage/app/public/`
  (`templates/api/nginx/api.conf.template.j2:75-76`).
- `api/bootstrap/cache/*.php` is removed and rebuilt by `startup.sh`.
- `api/.gitattributes` only export-ignores `.github`, `CHANGELOG.md` and
  `.styleci.yml`. No repo has submodules.
- Files left on the server from earlier deploys disappear on the next deploy:
  every playbook removes the old source before copying.

Behaviour change to be aware of: **uncommitted changes are no longer
deployed**. A deploy always matches a commit (see `docs/hotfixes.md`, which
already assumes that).

## Out of scope (do not do)

- Building images from a clean clone or in CI.
- Changes to templates, Dockerfiles, `startup.sh`, `releases/release.sh` or the
  `dockerhub/` repo.
- Failing a deploy because of uncommitted changes.

## Checks

- `ansible-playbook --syntax-check` passes for all four playbooks.
- If possible, run the archive and extract steps locally once and compare the
  file list with `git -C <repo> ls-files` (minus the excluded paths).
- **Manual, by the owner:** the first real deploy of each project afterwards.
  Check that the site works and that the server source directory holds no
  `.git`, `.bash_history`, `.claude`, `.idea` or `*.sqlite.bak`.
