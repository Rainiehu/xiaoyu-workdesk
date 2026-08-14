# xiaoyu-workdesk

## Mandatory wrap-up: build and restart

After completing every feature or bug fix, you must run `./build.sh` to confirm it compiles, then `open build/案头.app` to restart the app. Rebuilding kills the running instance, so after a build the app is stopped — skipping the re-open means the change was never delivered. Running only the tests does not count as done.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `Rainiehu/xiaoyu-workdesk`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, using their default label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.
