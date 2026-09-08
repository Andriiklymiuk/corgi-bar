# corgi-bar

Claude Code sessions in the macOS menu bar. A dog that turns amber while a
session works, red with a count when one needs you, blue when the account
hit its usage limit. Click it: one row per session — click to jump to its
window and terminal tab, right-click to dismiss or pin. **New session**
opens a `claude` terminal in the window in front, under that folder's
account. **Talk** (or `ctrl+alt+space` anywhere) dictates into the session
in front of you: press to talk, press again to send. The field at the top
types a prompt into that same session (`ctrl+alt+p` opens it from
anywhere); `ctrl+alt+n` jumps to the session that has waited longest.

Each row carries what corgi knows: the chat's title, a 2 px context bar
(orange past 60 %, red past 85 %), your note (`corgi agent note`), a
**slow** badge when a working session has gone quiet, and — when a
permission prompt is waiting and you turned **Approve from the menu bar** on
— **Allow** / **Deny** buttons (corgi refuses risky commands; go look at
those). Right-click for Dismiss, Pin, Compact context, mute (session or
workspace), Copy id, Open in Finder.

Below the sessions: one block per Claude account (`~/.claude`, `~/.claude-work`, …): live sessions, tokens today and this week, the same two bars `/usage` shows — the 5-hour window and the week, percent used and when each resets — a sparkline of the last five hours, and where the pace lands: "62%/h · runs out 14:32 (before the 16:10 reset)" in red, or "lasts until the reset". When an account hit its limit, the reset time replaces the tokens, and the limited row offers **Carry to <account>** for every other account with budget (`corgi agent carry`). Then the remote sessions corgi supervises per workspace — online or not, Open, Start/Stop — and the phone dashboard.

<p align="center"><img src="docs/media/hero.png" width="560" alt="corgi-bar open in the menu bar: sessions with their state, accounts with token usage and the /usage windows, remote sessions, Talk"></p>

<p align="center"><img src="docs/media/menubar.gif" width="560" alt="The menu bar item: grey, amber while working, red with a count when sessions need you, green, blue at the usage limit"> <img src="docs/media/notification.png" width="600" alt="A notification when a session needs you"></p>

corgi-bar draws the board that [corgi](https://github.com/Andriiklymiuk/corgi)
keeps and turns clicks into `corgi agent …` commands. It holds no state of
its own and never starts the daemon. The same board on Stream Deck keys is
[agent-deck](https://github.com/Andriiklymiuk/agent-deck); `SPEC.md` has the
full rules.

## Setup

```bash
brew install andriiklymiuk/homebrew-tools/corgi
corgi agent install          # the daemon, at login
corgi agent track enable     # hooks into your Claude Code settings
```

Install the [corgi VS Code extension](https://marketplace.visualstudio.com/items?itemName=corgi.corgi)
and reload each VS Code window once, so a click lands on the exact tab and
Talk knows which window is in front.

Then the app: download `corgi-bar.zip` from [Releases](../../releases),
unzip into `/Applications`, open it. Or from source: `make install`.

Talk presses Claude Code's dictation chord in the window in front, which
needs **Accessibility** for corgi-bar (System Settings → Privacy & Security →
Accessibility; the app asks the first time). For terminal sessions run
`/voice tap` once in Claude Code and bind `voice:pushToTalk` to `ctrl+y` in
`~/.claude/keybindings.json`; the Claude Code panel takes its own `cmd+d`,
then Enter after 1.5 s to send. All of that is in Settings, with quiet
hours, a sound per event, and a **Today** tab: twelve weeks of days, the
hours you work, today's tokens by model, from `~/.claude/stats-cache.json`.

## Development

```bash
make build      # swift build -c release
make test       # swift test
make app        # build/corgi-bar.app, ad-hoc signed
make run        # open it
make install    # copy to /Applications
make showcase   # redraw docs/media from scripts/showcase.mjs with Chrome
```

Release: bump `VERSION`, push `main`; CI builds the app, tags `v<VERSION>`
and attaches the zip. With the Apple secrets set (corgi's
`docs/release-signing.md`: `MACOS_SIGN_P12`, `MACOS_SIGN_PASSWORD`,
`APPLE_TEAM_ID`, `MACOS_NOTARY_*`) the app is Developer-ID signed, notarized
and stapled, so macOS keeps the Accessibility grant across updates. `Casks/corgi-bar.rb` is the Homebrew cask to copy
into the `andriiklymiuk/homebrew-tools` tap once a release exists.
