# corgi-bar

Claude Code sessions in the macOS menu bar. A dog that turns amber while a
session works, red with a count when one needs you, blue when the account
hit its usage limit. Click it: one row per session — click to jump to its
window and terminal tab, right-click to dismiss or pin. **New session**
opens a `claude` terminal in the window in front, under that folder's
account. **Talk** (or `ctrl+alt+space` anywhere) dictates into the session
in front of you: press to talk, press again to send.

Below the sessions: one block per Claude account (`~/.claude`, `~/.claude-work`, …): tokens today and this week, and the same two bars `/usage` shows — the 5-hour window and the week, percent used and when each resets — read from what Claude Code last cached. When an account hit its limit, the reset time replaces the tokens. Then the remote sessions corgi supervises per workspace — online or not, Open, Start/Stop — and the phone dashboard.

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
then Enter after 1.5 s to send. All of that is in Settings.

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
and attaches the zip. `Casks/corgi-bar.rb` is the Homebrew cask to copy
into the `andriiklymiuk/homebrew-tools` tap once a release exists.
