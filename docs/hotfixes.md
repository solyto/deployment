# Hotfixes: getting a single fix live without a full release

A fix doesn't have to wait for the next release. The deploy playbooks copy the
**local working tree** of one project to the server and build it there
(`make deploy-api` → `playbooks/api.yml`, `make deploy-app` →
`playbooks/app.yml`). So whatever is checked out locally is what goes live,
and each project deploys on its own.

The trick: check out the **released** state plus only the fix, deploy that,
then go back to `main`.

First used for the passkey fix on 2026-11-17 (`api`, branch `hotfix/1.1.3.1`
= tag `1.1.3` + `e7cd24b`).

## When this fits

- The fix lives in **one project** (API only, or web app only), and the other
  side already works with it. Example: the passkey fix only changed the API,
  because the app had always sent the right data.
- The fix needs **no migration**. Without one, `migrate --force` in
  `startup.sh` does nothing, and there's no window where new code runs against
  the old schema.
- The fix is small and self-contained, ideally a single commit.

If a fix needs changes in both API and app, or a migration, it is still
possible, but plan it like a small release (see "Harder cases").

## Procedure (API example)

1. **Fix it on `main` first,** as its own commit with tests. That keeps the fix
   in the next regular release and gives you one commit to cherry-pick.
2. **Branch from the live tag** in `api`. Put local changes aside first
   (`git stash`), because the deploy copies the working tree as it is:

   ```sh
   git stash
   git switch -c hotfix/<version-or-name> <live-tag>   # e.g. 1.1.3
   git cherry-pick <fix-commit>
   ```

3. **Check before deploying:**
   - `git status`: clean (uncommitted and untracked files would be deployed
     too; see `backlog/rsync-copies-local-files.md`)
   - `git log --oneline -3`: the fix on top of the live tag, nothing else
   - `git diff --stat <live-tag> HEAD`: only the files of the fix, nothing
     under `database/migrations`, no `composer.json` / `composer.lock`
     (`package.json` / `package-lock.json` for the app)
   - run the tests on the branch (`php artisan test`, or `npm run check` and
     `npm test` for the app)
4. **Deploy only that project:**

   ```sh
   cd ../deployment
   make deploy-api        # or: make deploy-app
   ```

5. **Verify in production:** reproduce what was broken and check that it works
   now.
6. **Go back:**

   ```sh
   cd ../api
   git switch main
   git stash pop
   ```

7. **Tag the hotfix commit** (e.g. `git tag 1.1.3.1` on the hotfix branch) and
   push the tag, so the deployed state is traceable.

## Version number

- The `VERSION` file (API) only feeds `/health` and the app's "server is
  older than the app" notice. Nothing else depends on it.
- Leaving it at the live version is fine. Bumping it (e.g. `1.1.3.1`) only
  makes `/health` show that the hotfix is live. Four-part versions work: the
  app compares any number of parts (`VersionHelper.ts`), and the API uses
  `version_compare`.
- Don't use the next release's number for a hotfix.

## Rollback

Deploy the live tag again:

```sh
cd api
git switch --detach <live-tag>
cd ../deployment && make deploy-api
```

## Not covered by a server hotfix

- **Desktop and mobile apps** ship their own copy of the frontend
  (`desktop/frontend`, `mobile/frontend`). A web app hotfix doesn't reach them.
  They need their own store or GitHub release.
- **Self-hosters** run the Docker Hub images. They only get the fix through a
  new image. `dockerhub/Makefile` clones the source by tag from GitHub
  (`fetch-api-src`, `fetch-app-src`), so the hotfix tag must be pushed first,
  then build and push only the affected image. `releases/release.sh` releases
  everything at once (all repos, deployment vars) and doesn't fit a hotfix.

## Harder cases

- **Migration needed:** the migration must work with the code that is live
  (only add columns or tables, nothing the old code would trip over). Note
  that the deploy starts the new code before `migrate` runs
  (`docker compose up -d`, then `startup.sh`), so there is a short window.
  Deploy at a quiet time.
- **API and app both change:** deploy the API first, as long as it still
  accepts what the live app sends, then the app. Otherwise the app breaks
  between the two deploys.
