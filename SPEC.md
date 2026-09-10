# corgi-bar — specification

A macOS menu bar app that shows corgi's Claude Code session board and turns
clicks into `corgi agent …` commands. For people without a Stream Deck, and
for the deck's owner when the deck is in a bag. It holds no state of its own,
never starts the daemon, and never talks to Claude Code directly. Everything
it knows comes from one file corgi writes; everything it does is one corgi
command. The Stream Deck plugin (github.com/Andriiklymiuk/agent-deck) is the
same idea on keys; this document borrows its rules where they apply.

## 1. What corgi already provides (do not rebuild)

corgi ≥ 1.21.46, `corgi agent install` + `corgi agent track enable`:

- `corgi agent sessions --json` → the board plus `path` (absolute path of
  `sessions.json`) and `daemonRunning`. The file is rewritten atomically
  (temp + rename) on every change; a directory watch on its parent is the
  signal, a 5 s poll the fallback.
- Board fields: `updatedAt`, `size`, `overflow`, `needsInput`, `working`,
  `slots[]`, `sessions[]`, `windows[]`, `frontWindow`, `frontSession`,
  `lastFocusWindow`, `notice` / `noticeAt`, `accounts[]`.
- Session: `id`, `label`, `display` (unique label), `cwd`, `folder`,
  `profile`, `status`, `statusSince`, `lastActivity`, `detail` (reads like
  "Edit registry.go", "permission: Bash go test"), `tool`, `host.kind`
  (`vscode-terminal` | `vscode-panel` | `iterm` | `terminal` | `unknown`),
  `host.windowId`, `focusError`, `focusAt`, `context{tokens, window,
  percent, model, at}` (context-window fill), `title` (the Claude chat's
  name), `pending{tool, subject, at}` (a permission prompt is waiting; only
  while `needs_input`), `note` (the owner's line, `corgi agent note`),
  `stuck` (working but silent for 12+ min).
- Slot: the same `context` (int %), `pending` (tool), `note`, `stuck`.
- Account: `profile`, `configDir`, `limits{fetchedAt, fiveHour{percent,
  resetsAt}, sevenDay{…}}`, `forecast{fiveHour{percentPerHour, exhaustAt,
  safe, samples}, sevenDay{…}}`, `sessions` (live count). The bar reads
  limits from the board; `corgi agent status --json` is polled every five
  minutes only for the version, the remote sessions and the dashboard URL.
- Samples: `<agentDir>/usage/<profile>.jsonl`, one `{at, fetchedAt,
  fiveHour, sevenDay}` per line, read when the dropdown opens.
- Statuses: `working` (amber), `needs_input` (red: a permission prompt, a
  question, an API failure), `done` (green), `limited` (blue: the account
  hit its usage limit; `detail` = "resets 12:10pm (Europe/Kiev)"), `stale`
  (grey, 30 min quiet), `gone` (grey, pinned key whose process exited),
  `unknown` (found by rescan, no hook yet).
- `frontSession`: the session in the editor window in front — its panel
  while the Claude Code panel is the active tab, else the active terminal
  tab's session, else the panel, else the one that moved last. What Talk
  dictates into. Needs the corgi VS Code extension ≥ 1.16.13 in every window.
- Commands: `corgi agent focus <id|prefix|label|key#>`, `corgi agent new
  [--window ID]` (a terminal running `corgi agent claude` in the window in
  front, so a workspace under another account opens under it),
  `corgi agent dismiss <ref>` (a done / idle / closed / limited session off
  the board until its next event; refused for working or waiting ones),
  `corgi agent pin <key#> [--off]`, `corgi agent page next|prev`,
  `corgi agent rescan`, `corgi agent claude [--profile P] [-- args]`,
  `corgi agent doctor`, `corgi --version`.
- `corgi agent send <id> [--enter] <text…>` focuses and types into the
  session. A `vscode-panel` host takes text only from the keyboard: the
  command fails and the board carries a `focusError` containing "keyboard"
  on that session, which is the bar's cue to focus it and type through
  CGEvent. `corgi agent answer <id> allow|always|deny` answers a pending
  permission the same way (keystroke fallback: Return, "2" then Return,
  Escape); corgi refuses risky commands and says so in `notice`.
  `corgi agent note <id> [text] [--clear]`, `corgi agent carry <id>
  --profile <name>` (continue a limited session under another account; a
  workspace that lists no accounts is refused, in `notice`).
- A failed focus lands on the session as `focusError` + `focusAt`; a failed
  `new`, `dismiss`, `answer` or `carry` lands on the board as `notice` +
  `noticeAt`.

## 2. Menu bar item

- SF Symbol `dog` (macOS 14+) else `pawprint`. Tint by the board: grey when
  the daemon is off or corgi is missing, amber when any session is
  `working`, red when any is `needs_input`, blue when the only news is a
  `limited` session. Red wins over amber wins over blue.
- Text next to the icon: the `needs_input` count when > 0, else nothing.
- One pulse of the red tint when the count rises; no animation otherwise.

## 3. Dropdown (`MenuBarExtra` with `.window` style)

Top to bottom:

1. **Quick prompt** field, with **+** (new session → `corgi agent new`,
   disabled with a tooltip when `windows` is empty: "open a folder in VS
   Code with the corgi extension") beside it. Type and press Return →
   `corgi agent send <session> --enter <text>` into `frontSession` (else
   the Talk pick, section 4) and the dropdown closes; ⌥Return sends without
   Enter. The panel fallback types the text through CGEvent after the focus.
2. One row per session, in board order (`slots` first, then the overflow),
   each: a status dot, `title` when there is one with `display` as a small
   chip (else `display`), a `profile` chip when it is not `default` (first
   two letters, uppercase, like the deck's `SP`), a small ● when it is
   `frontSession`, an amber **slow** badge when `stuck`, the second line in
   monospace (the `note` when set, else "no activity 14m" when stuck, else
   `detail`), elapsed since `statusSince` (kept counting locally between
   publishes, bucketed to 5 s). Colours as in section 1. `gone` rows at
   40 % opacity. A 2 px **context bar** under the row, filled to
   `context.percent`: grey to 60, orange past it, red past 85; hidden when
   unknown.
   - Click → `corgi agent focus <id>`. Show ⚠ on the row once when the next
     board carries a `focusError` with `focusAt` newer than the click.
   - A `needs_input` row with `pending` shows the tool and subject and,
     when **Approve from the menu bar** is on (default off), **Allow** and
     **Deny** buttons → `corgi agent answer <id> allow|deny`. If the board
     answers with a `focusError` containing "keyboard" within 1.5 s, the
     bar focuses the session the Talk way and presses the keys itself.
   - Secondary click → menu: **Dismiss** (not for working / needs_input),
     **Pin / Unpin** (by key number), **Compact context** (`corgi agent send
     <id> --enter /compact`), **Allow always** / **Deny** when pending and
     approving is on, **Mute session** / **Mute workspace**, **Copy session
     id**, **Open folder in Finder** (`cwd`).
   - A `limited` row shows "resets …" in blue where the elapsed time would
     be, and a **Carry to <profile>** button for every other account in
     `accounts[]` with `fiveHour.percent < 90` → `corgi agent carry <id>
     --profile <profile>`. When the board then says the workspace lists no
     accounts, that notice shows under the row: corgi refuses moves the
     workspace did not allow, and the bar does not work around it.
3. **Accounts**: one block per account in `accounts[]` (merged with the
   token totals from `status --json`): profile chip, config dir, live
   session count, tokens today and this week (or "resets …" when limited),
   the 5-hour and week bars, a sparkline of the 5-hour window over the last
   five hours from the samples file, and the forecast sentence: "62%/h ·
   runs out 14:32 (before the 16:10 reset)" in red when
   `forecast.fiveHour.safe` is false, "12.5%/h · lasts until the reset"
   otherwise, "pace flat" when `exhaustAt` is absent.
4. Footer: `corgi 1.21.46 · daemon running` (or "daemon off — `corgi agent
   install`", or "corgi not found — brew install …"), then the **Talk** mic
   button (section 4; red while it records), **Settings**, **Quit**.

The dropdown never blocks: every corgi call runs off the main thread, and
the board redraw comes from the file, not from the command's exit.

## 4. Talk

Same rules as the deck's talk key:

- Pick the session: `frontSession` if live, else the row last clicked, else
  the only `needs_input` session, else the one with the newest
  `lastActivity`. None → shake the button, log why.
- `corgi agent focus <id>`; wait up to 1.5 s for the board to show that
  session's `focusAt` newer than the click without a `focusError`; on
  timeout assume the window is up.
- Press the chord for the session's host: `vscode-panel` → `cmd+d` (Claude
  Code's own dictation shortcut in the panel), everything else → `ctrl+y`
  (bound to `voice:pushToTalk` in `~/.claude/keybindings.json`, with
  `/voice tap`). Both chords configurable in Settings. Use `CGEvent`
  keyboard events (needs Accessibility for corgi-bar; on failure open an
  alert that deep-links to System Settings → Privacy & Security →
  Accessibility). Never a shell string.
- REC state: the button turns red after the first press; a second press
  sends the same chord (tap mode: that sends the prompt) and clears; the
  state also clears when that session becomes `working` with a
  `statusSince` newer than the press, or after two minutes.
- Global hotkey: default `ctrl+alt+space` via Carbon `RegisterEventHotKey`
  (no Accessibility needed for the hotkey itself). A few presets in
  Settings. Two more keys share the handler: **Quick prompt** (default
  `ctrl+alt+p`) opens the dropdown with the field focused; **Next needs
  you** (default `ctrl+alt+n`) focuses the `needs_input` session that has
  waited longest (by `statusSince`), else `frontSession`.

## 5. Notifications

- A macOS notification when a session enters `needs_input` (title
  `display`, body `detail`); clicking it → `corgi agent focus <id>`.
- A calmer one when a session enters `limited`: "acme-api hit the usage
  limit · resets 12:10pm". No notification for `done`.
- Per-session mute from the row's secondary menu (kept in UserDefaults by
  session id; expires when the session leaves the board), and a
  per-workspace mute keyed by `folder` (else `cwd`) that outlives sessions.
- Quiet hours (start and end in Settings, wrapping midnight) suppress all.
- Optional distinct system sounds for `needs_input`, `done` and `limited`
  (`NSSound`: Glass, Pop, Submarine, …; default off). `done` is a sound
  only, never a banner. corgi itself notifies when a limit lifts
  (`limited` → `working`); the bar does not repeat it.
- `UNUserNotificationCenter` needs a real bundle: the code must tolerate
  running unbundled (`swift run`) by logging and moving on.

## 6. Settings window

Three tabs.

- **General**: chords (terminal, panel), the three hotkey presets, "Approve
  from the menu bar" (off by default, one line saying what it shows and
  that corgi refuses risky commands), launch at login (`SMAppService`),
  path to corgi (auto: `/opt/homebrew/bin/corgi`, `/usr/local/bin/corgi`,
  then `PATH`), and a "Run `corgi agent doctor`" button that shows the
  output.
- **Notifications**: on/off, quiet hours, a sound per event.
- **Today**: a GitHub-style heatmap of the last 12 weeks from
  `~/.claude/stats-cache.json` (`dailyActivity[]: {date, messageCount,
  sessionCount, toolCallCount}`), a 24-bar histogram from `hourCounts`
  (keyed "0".."23"), and today's tokens by model from the last
  `dailyModelTokens` entry for today. The file is read when the tab shows.
  Pure SwiftUI.

## 7. Packaging and repo

- SwiftUI, macOS 13+, Swift Package Manager, no `.xcodeproj`.
- `Makefile`: `build` (swift build -c release), `app` (assemble
  `build/corgi-bar.app`: `Contents/MacOS/corgi-bar`, `Info.plist` with
  `CFBundleIdentifier com.andriiklymiuk.corgi-bar`, `LSUIElement true`,
  version from a `VERSION` file; ad-hoc `codesign --force --deep --sign -`),
  `run`, `install` (copy to /Applications), `test`.
- `.github/workflows/release.yml`: on push to `main`, if `v<VERSION>` has no
  tag: build on `macos-latest`, `make app`, zip, tag, GitHub Release with the
  zip. Only `GITHUB_TOKEN`. The corgi VS Code extension's `release.yml` is
  the model.
- `Casks/corgi-bar.rb`: a Homebrew cask pointing at the release zip, with a
  note on filling the sha256 and adding it to `andriiklymiuk/homebrew-tools`.
  `corgi agent install` may later offer `brew install --cask corgi-bar`.
- README: what it shows, the three-line corgi setup, the VS Code extension,
  Accessibility for Talk, the hotkey, `make` targets. Plain.
- Tests: the pure parts (board decoding from the fixture including
  context / title / pending / note / stuck / accounts, session picking for
  Talk and for "next needs you", carry targets, the forecast sentence,
  quiet hours, samples parsing, the stats heatmap, chord → key codes,
  elapsed bucketing, icon tint from a board) as `swift test`.

## 8. Milestones

| # | deliverable | done when |
|---|---|---|
| 1 | Package, board reader, icon tint | icon turns amber/red with the live board; quitting the daemon greys it |
| 2 | Dropdown rows, click to focus, ⚠ on failure | clicking a row brings the right VS Code tab up; a `host: unknown` row shows ⚠ once |
| 3 | New session, dismiss, pin | `+` opens a `corgi agent claude` terminal in the front window; dismiss frees a done row; pin survives the session ending |
| 4 | Talk + hotkey + Accessibility alert | ctrl+alt+space records in the panel or terminal in front, second press sends |
| 5 | Notifications, mute | a permission prompt raises a notification; clicking it focuses |
| 6 | Settings, launch at login, release workflow, cask | `make app` runs from /Applications at login; a VERSION bump publishes a zip |
| 7 | Context bars, titles, notes, Allow / Deny, quick prompt, forecasts, carry, quiet hours, Today | a pending row answers from the bar; ctrl+alt+p types a prompt into the session in front; a limited row moves to the other account |

## 9. Not in scope

Starting or installing corgi; anything Windows or Linux; picking a
specific chat tab inside the Claude Code panel (Claude Code exposes no
command for it; corgi focuses the panel, not the tab).
