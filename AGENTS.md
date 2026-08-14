# xiaoyu-workdesk

## Communication style

Write in plain, natural, clear language. Avoid obscure words and long convoluted sentences when simpler ones will do.

## Mandatory wrap-up: build and restart

After completing every feature or bug fix, you must run `./build.sh` to confirm it compiles, then restart the app. Running only the tests does not count as done.

Restarting takes three steps — `open` alone is NOT a restart:

1. Kill any running instance first: `pkill -f 'build/案头.app/Contents/MacOS/Workdesk'`. Deleting the bundle during rebuild does **not** reliably kill a running instance — it keeps executing stale code from memory, and `open` will merely bring that old instance to the front instead of launching the new binary.
2. `open build/案头.app`.
3. Verify delivery: the process start time (`ps -o lstart`) must be newer than the binary mtime (`stat build/案头.app/Contents/MacOS/Workdesk`). If it isn't, the user is still looking at the old build.

## Code review before merging to main

Before every merge to `main`, run `/code-review` on the change, auto-fix the findings, and re-run the tests. Only commit and merge after the review findings are fixed and the tests pass.

## Merge and push once verified

As soon as the user confirms a change works, merge it to `main` and push immediately. Do not let verified work sit unmerged on a branch or unpushed locally.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `Rainiehu/xiaoyu-workdesk`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, using their default label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.
