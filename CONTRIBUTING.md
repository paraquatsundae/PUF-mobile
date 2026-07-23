# Contributing (PUF-mobile)

Public default branch: **`main`**. Direct pushes to `main` are blocked; use a pull request.

## Workflow

1. Sync local `main`:
   ```powershell
   git checkout main
   git pull origin main
   git submodule update --init --recursive
   ```
2. Create a branch for the change:
   ```powershell
   git checkout -b feature/short-name
   ```
3. Commit focused changes (no farm/TASKDATA, no secrets, no local APKs).
4. Push the branch and open a PR into `main`:
   ```powershell
   git push -u origin HEAD
   gh pr create --base main --title "…" --body "…"
   ```
5. Merge the PR on GitHub when ready (`gh pr merge` or the UI).

## Notes

- Prefer small PRs with a clear why in the title/body.
- After clone or branch switch: `git submodule update --init --recursive` (KDAB `android_openssl`).
- Legacy `master` may still exist; **target `main`** for all new PRs.
- Workshop emergency: repo admins can bypass the ruleset if GitHub allows; prefer a PR anyway so history stays clean.
