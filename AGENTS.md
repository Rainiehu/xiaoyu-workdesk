# xiaoyu-workdesk

案头 (Workdesk) — a native SwiftUI personal desk app for macOS with a full-peer iOS version: todos organized along two orthogonal axes (category × planned day), plus a favorites stream synced over CloudKit.

## Communication style

Write in plain, natural, clear language. Avoid obscure words and long convoluted sentences when simpler ones will do.

Code comments and commit messages are written in Chinese, in the voice already used throughout the repo: they state the constraint or the reasoning, not what the next line does. When naming a domain concept anywhere, use the vocabulary defined in `CONTEXT.md` and avoid the synonyms it rejects.

## Common commands

```bash
./build.sh                        # release build + assemble + sign build/案头.app (macOS)
swift test                        # full test suite (swift-testing, runs on macOS)
swift test --filter TodoTests     # one suite — filter by TYPE name; the Chinese
                                  # @Suite("…") display names match nothing and
                                  # silently run 0 tests
# iOS compile check without opening Xcode (simulator, unsigned):
xcodebuild -project ios/Workdesk.xcodeproj -scheme Workdesk \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

To run the app against seeded/throwaway data instead of the real store, point `WORKDESK_DATA_DIR` at another directory when launching (`open build/案头.app --env WORKDESK_DATA_DIR=…` does not pass it through; launch the binary directly).

## Architecture

One SwiftPM package, four targets; the iOS Xcode project (`ios/`) is only a `@main` shell plus signing config — adding or removing UI files never touches the pbxproj.

- **`Sources/WorkdeskCore`** — platform-neutral core both UIs run verbatim (ADR-0006): models, `Store`, `TodayClock`, the whole CloudKit sync stack. All domain rules and invariants live in `Store`, never in view code — e.g. a category with live todos refuses deletion; a live todo's category must be alive (sync conflicts resolve as "todo wins, category revives"); soft delete is a marker with an undo window (ADR-0007).
- **`Sources/Workdesk`** — macOS UI. `Sources/WorkdeskiOS` — iOS UI, wrapped in `#if os(iOS)` so it compiles to an empty module on macOS and `swift test` always runs. `Sources/WorkdeskUI` — the few pieces both UIs share **verbatim** (pure geometry, pure algorithms); presentation stays per-platform.
- Tests cover `WorkdeskCore` and write only to temp directories, never the real data dir.

Big-picture reading order for any todo-related work: `CONTEXT.md` (domain language + the rules of the app, the single source of truth for both) → the `docs/adr/` entries touching your area. The README covers build/signing tiers, data files, and the module map in detail.

Session state that must survive SwiftUI view rebuilds (cursor handoff in the sub-todo tree, the single drop indicator) lives in small `@Observable` objects injected once from `WorkdeskApp` — follow that pattern rather than per-row `@State` when state outlives or spans rows.

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
