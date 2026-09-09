# corgi-bar

Every Claude Code session on your Mac, in the menu bar. The dog is amber
while a session works, red with a count when one needs you, blue when the
account hit its usage limit.

<p align="center"><img src="docs/media/hero.png" width="560" alt="corgi-bar open in the menu bar: sessions grouped by workspace, Allow and Deny on the one that asks, accounts with their usage windows, Talk"></p>

<p align="center"><img src="docs/media/menubar.gif" width="300" alt="The menu bar item: grey when quiet, amber while working, red with a count when sessions need you, green when done, blue at the usage limit"></p>

## What you see

One row per session, grouped by workspace. The name is the chat's title
once it has one. The line under it is what the session is doing right now,
or your note. The 2 px bar is the context window: orange past 60 %, red past
85 %. A **slow** badge means a working session has gone quiet. The blue
edge marks the session in the window in front: that is where Talk and the
prompt field go.

<p align="center"><img src="docs/media/story.gif" width="400" alt="A session asks for permission, the row turns red and offers Allow and Deny, Allow is pressed from the menu bar, the session works on and finishes"></p>

Click a row to jump to its window and terminal tab. Right-click for
Dismiss, Pin, Compact context, mute (session or workspace), Copy id, Open in
Finder.

**Allow / Deny** appear on a row waiting for a permission prompt, once you
turn **Approve from the menu bar** on in Settings. corgi refuses to allow
risky commands (`rm -rf`, `sudo`, `--force`, `drop`…): go look at those.

## Accounts

One block per Claude account (`~/.claude`, `~/.claude-work`, …): live
sessions, tokens today and this week, the two bars `/usage` shows with their
reset times, a sparkline of the last five hours, and where the pace lands:
"runs out 12:41 (before the 1:10pm reset)" in red, or "lasts until the
reset".

<p align="center"><img src="docs/media/accounts.png" width="400" alt="Two accounts: one at 55 percent of its 5-hour window lasting until the reset, one at 100 percent, limited until 1:10pm"></p>

When an account hits its limit the reset time replaces the tokens, and its
limited sessions offer **Carry to <account>** for every other account the
workspace lists with budget left: the conversation continues there
(`corgi agent carry`). When the limit lifts, corgi says so and the sessions
go back to work.

## Talk and type

**Talk** (or `ctrl+alt+space` anywhere) dictates into the session in front
of you: press to talk, press again to send. The field at the top types a
prompt into that same session (`ctrl+alt+p` opens it from anywhere; Return
sends, ⌥Return types without Enter). `ctrl+alt+n` jumps to the session that
has waited longest.

<p align="center"><img src="docs/media/talk.gif" width="400" alt="Talk pressed: the row turns to REC, press again to send; a prompt typed into the field goes to the front session"></p>

A notification arrives when a session starts waiting, with a sound per
event and quiet hours in Settings. **New session** (the + button) opens a
`claude` terminal in the window in front, under that folder's account.
The **Today** tab in Settings shows twelve weeks of days, the hours you
work and today's tokens by model.

<p align="center"><img src="docs/media/notification.png" width="600" alt="A notification: acme-api needs you, Bash go test"></p>

corgi-bar draws the board that [corgi](https://github.com/Andriiklymiuk/corgi)
keeps and turns clicks into `corgi agent …` commands. It holds no state of
its own. The same board on Stream Deck keys is
[Corgi Agent Deck](https://github.com/Andriiklymiuk/corgi-agent-deck), and
inside VS Code the
[corgi extension](https://marketplace.visualstudio.com/items?itemName=Corgi.corgi).

## Install

```bash
brew install --cask andriiklymiuk/tools/corgi-bar
```

That pulls corgi too. Then, once:

```bash
corgi agent install        # the daemon, at login
corgi agent track enable   # the hooks that feed the board
```

Open corgi-bar from Applications. Grant **Accessibility** (Talk and typed
prompts press keys) and **Notifications** when macOS asks. Launch at login
is in Settings.

The app is Developer-ID signed and notarized. `brew upgrade --cask
corgi-bar` gets the next version, and the footer says "x.y.z available"
when there is one. Without Homebrew: `corgi-bar.zip` from the
[releases](https://github.com/Andriiklymiuk/corgi-bar/releases), unzipped
into Applications.

Install the [corgi VS Code extension](https://marketplace.visualstudio.com/items?itemName=Corgi.corgi)
and reload each window once, so a click lands on the exact tab and Talk
knows which window is in front. For terminal sessions run `/voice tap` once
in Claude Code and bind `voice:pushToTalk` to `ctrl+y` in
`~/.claude/keybindings.json`; the Claude Code panel takes its own `cmd+d`.

## Development

```bash
make build      # swift build -c release
make test       # swift test
make app        # build/corgi-bar.app, ad-hoc signed
make run        # open it
make install    # copy to /Applications
make showcase   # redraw docs/media from scripts/showcase.mjs with Chrome
```

Release: bump `VERSION`, push `main`; CI builds, signs, notarizes and
staples the app, tags `v<VERSION>` and attaches the zip (secrets per corgi's
`docs/release-signing.md`). The Homebrew cask lives in the
`andriiklymiuk/homebrew-tools` tap and rewrites itself from the latest
release every few hours.
