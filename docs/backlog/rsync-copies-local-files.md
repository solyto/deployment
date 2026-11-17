# Backlog: deploys copy local, ignored files to the server

created: 2026-11-17

## What

The deploy playbooks rsync the **local working tree** of each project to the
server, excluding only a few paths. Everything else goes along, including
files git ignores: shell history, editor and agent folders, local database
backups and, for app and landing page, the `.git` folder. Deploy only what the
build needs.

## Findings

Excludes per playbook (`rsync_opts`):

| Playbook | Excludes |
|---|---|
| `playbooks/api.yml:72` | `*.sqlite`, `vendor`, `storage`, `.env`, `.git`, `tests`, `docs/node_modules` |
| `playbooks/app.yml:49` | `node_modules`, `.env`, `build` |
| `playbooks/landing-page.yml:49` | `node_modules`, `.env`, `build` |
| `playbooks/docs.yml:50` | `node_modules`, `.astro`, `dist`, `.git`, `/docs`, `.manigot`, `AGENTS.md` |

Ignored local files that are copied today (seen on the dev machine,
2026-11-17):

- **api:** `.bash_history`, `.claude/`, `.composer/`, `.config/`, `.idea/`,
  `.manigot/`, `.phpunit.cache/`, `database/database.sqlite.bak` (only
  `*.sqlite` is excluded, not `.bak`), `docs/package.json` and others under
  `docs/`, plus a modified `.env.testing` (only `.env` is excluded).
- **app:** `.git/` (not excluded), `.claude/`, `.idea/`, `.manigot/`,
  `.opencode/`, `.svelte-kit/`.
- **landing page:** `.git/`, `.idea/`, `.svelte-kit/`.

`.bash_history` and agent or editor folders can contain commands, paths or
tokens, and don't belong on the server. `.git/` ships the full history.
`bootstrap/cache/*.php` is copied too, but `startup.sh` removes it before use.

Found while preparing the passkey hotfix deploy (2026-11-17). Not specific to
that deploy: it happens on every one.

## Options

1. **Deploy what git tracks.** Build the file list from git instead of the
   working tree, e.g. `git ls-files` or `git archive HEAD` into a temp folder
   and rsync that. Ignored and untracked files never leave the machine, and a
   deploy always matches a commit. A side effect to keep in mind: uncommitted
   changes are no longer deployed (usually what we want).
2. **Extend the excludes.** Add `.git`, `.bash_history`, `.claude`,
   `.composer`, `.config`, `.idea`, `.manigot`, `.opencode`, `.svelte-kit`,
   `.phpunit.cache`, `*.bak`, `.env.*` and so on to each playbook, or use one
   shared `--exclude-from` file. Smallest change, but every new tool folder has
   to be added by hand.
3. **Build artifacts elsewhere.** Build the images from a clean checkout (CI,
   or a script that clones the tag) instead of the developer's working tree.
   The most robust, and the largest change.

## Notes

- Check what is already on the server: `{{ target_base_path }}/{{ api_path }}/src`
  (and the app and landing page paths) may still hold these files from
  earlier deploys. `api.yml` removes the old source before copying ("Remove
  old source"); check whether the other playbooks do too.
- For the `.env.testing` case: the deploy also ships local uncommitted
  changes, which is how a modified tracked file ends up on the server.
  Option 1 would prevent that.
