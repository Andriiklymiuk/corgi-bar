// Draws the README pictures: the corgi-bar dropdown as HTML for Chrome to
// screenshot, on a macOS desktop for the hero and on a flat ground for the
// close-ups and the animated stories. The rows mirror App.swift (grouped by
// workspace, accent bar on the front session, opaque window background), so
// keep the two in step when the layout changes. scripts/capture.sh runs it.
import { mkdirSync, writeFileSync, rmSync, readFileSync } from "node:fs";

// macOS dark system colours: what Palette in App.swift resolves to.
const amber = "#FF9F0A", red = "#FF453A", green = "#30D158", blue = "#0A84FF";
const label = "#F2F2F7", secondary = "rgba(235,235,245,.62)", tertiary = "rgba(235,235,245,.32)";
const ground = "#141416", window = "#2A2A2D";

const ctxColor = (p) => (p > 85 ? red : p > 60 ? amber : "rgba(235,235,245,.28)");

// The menu bar item is the SF Symbol "dog", rendered by scripts/dog-symbol.swift.
const dogPng = Object.fromEntries(["quiet", "working", "needs", "done", "limited"].map((m) => [m, readFileSync(`docs/media/dog/${m}.png`).toString("base64")]));
const moodOf = { "#e8e8ea": "quiet", [amber]: "working", [red]: "needs", [green]: "done", [blue]: "limited" };
const dog = (color, size = 16) => `<img width="${size}" height="${size}" style="vertical-align:middle" src="data:image/png;base64,${dogPng[moodOf[color] ?? "quiet"]}">`;
const mic = (color) => `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 17v5M8 22h8"/></svg>`;
const rec = `<svg width="13" height="13" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="none" stroke="${red}" stroke-width="2"/><circle cx="12" cy="12" r="5" fill="${red}"/></svg>`;

const chip = (t) => `<span class="chip">${t}</span>`;

const row = (s) => `
<div class="row${s.front ? " front" : ""}${s.gone ? " gone" : ""}">
  <div class="line">
    <span class="dot" style="background:${s.color}"></span>
    <div class="txt">
      <div class="name">${s.title ?? s.name}${s.title ? chip(s.name) : ""}${s.chip ? chip(s.chip) : ""}${s.slow ? `<span class="slow">slow</span>` : ""}</div>
      ${s.detail ? `<div class="detail${s.note ? " note" : ""}">${s.detail}</div>` : ""}
    </div>
    <div class="right"><div class="status" style="color:${s.color}">${s.status}</div>${s.elapsed ? `<div class="elapsed">${s.elapsed}</div>` : ""}</div>
    ${s.pending ? `<div class="answer"><span class="ok${s.pressed === "allow" ? " pressed" : ""}">Allow</span><span class="${s.pressed === "deny" ? "pressed" : ""}">Deny</span></div>` : ""}
  </div>
  ${s.ctx ? `<div class="ctx"><i style="width:${s.ctx}%;background:${ctxColor(s.ctx)}"></i></div>` : ""}
  ${s.carry ? `<div class="carry"><span>Carry to ${s.carry}</span></div>` : ""}
</div>`;

const group = (g) => `
<div class="group"><span>${g.label}</span>${g.chip ? chip(g.chip) : ""}<b>${g.sessions.length > 1 ? g.sessions.length : ""}</b></div>
${g.sessions.map(row).join("")}`;

const spark = (from, to, color, dip = 0) => {
	const pts = Array.from({ length: 12 }, (_, i) => {
		const v = from + ((to - from) * i) / 11 + (i === 6 ? dip : 0);
		return `${i * 5.4},${12 - v * 0.1}`;
	}).join(" ");
	return `<svg class="spark" width="60" height="12" viewBox="0 0 60 12"><polyline fill="none" stroke="${color}" stroke-width="1.2" points="${pts}"/></svg>`;
};

const bar = (lbl, pct, color, at) => `<span class="lbl">${lbl}</span><span class="bar"><i style="width:${pct}%;background:${color}"></i></span><span class="pct" style="color:${color}">${pct}%</span><span class="at">${at}</span>`;

const accounts = ({ workLimited = true, workPct = 100 } = {}) => `
  <hr>
  <div class="acct"><span class="path">~/.claude</span><span class="live">3 live</span><span class="use">178.0M today · 1.6B week</span></div>
  <div class="bars">${bar("5h", 55, green, "5:10pm")}${bar("week", 10, green, "mon 9am")}</div>
  <div class="fc">${spark(20, 55, secondary)}12.5%/h · lasts until the reset</div>
  <div class="acct">${chip("WK")}<span class="path">~/.claude-work</span><span class="live">2 live</span>${workLimited ? `<span class="limit">resets 1:10pm</span>` : `<span class="use">92.4M today · 1.1B week</span>`}</div>
  <div class="bars">${bar("5h", workPct, workPct > 85 ? red : workPct > 60 ? amber : green, "1:10pm")}${bar("week", 64, amber, "thu 6am")}</div>
  <div class="fc" style="color:${workPct > 85 ? red : secondary}">${spark(40, workPct, workPct > 85 ? red : secondary, -6)}${workPct > 85 ? "62%/h · runs out 12:41 (before the 1:10pm reset)" : "31%/h · lasts until the reset"}</div>`;

const popover = ({ groups, prompt = "", placeholder = "Prompt for corgi", talk = "idle", limited = true, workPct = 100, update = true, part = "all" }) => part === "accounts" ? `<div class="popover">${accounts({ workLimited: limited, workPct }).replace("<hr>", "")}</div>` : part === "talk" ? `
<div class="popover">
  <div class="prompt"><span class="field${prompt ? " typed" : ""}">${prompt || placeholder}${prompt ? `<i class="caret"></i>` : ""}</span><span class="plus">+</span></div>
  <div class="hint">Return sends · ⌥Return types without Enter · ctrl+alt+p</div>
  <hr>
  ${group(groups[0])}
  <hr>
  <div class="talk${talk === "rec" ? " rec" : ""}">${talk === "rec" ? rec : mic(label)} ${talk === "rec" ? "REC · press to send" : "Talk"} <span class="hot">ctrl+alt+space</span></div>
</div>` : `
<div class="popover">
  <div class="prompt"><span class="field${prompt ? " typed" : ""}">${prompt || placeholder}${prompt ? `<i class="caret"></i>` : ""}</span><span class="plus">+</span></div>
  <div class="hint">Return sends · ⌥Return types without Enter · ctrl+alt+p</div>
  <hr>
  ${groups.map(group).join("")}
  ${accounts({ workLimited: limited, workPct })}
  <hr>
  <div class="remote">▸ Remote · 5 of 5 online</div>
  <hr>
  <div class="talk${talk === "rec" ? " rec" : ""}">${talk === "rec" ? rec : mic(label)} ${talk === "rec" ? "REC · press to send" : "Talk"} <span class="hot">ctrl+alt+space</span></div>
  <hr>
  <div class="foot"><span>corgi 1.21.51 · daemon on</span>${update ? `<a>0.6.4 available</a>` : ""}<span class="sp"></span><span>Settings…</span><span>Quit</span></div>
</div>`;

const css = `
  *{box-sizing:border-box}
  html,body{margin:0;font-family:-apple-system,"SF Pro Text",Inter,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;color:${label}}
  .popover{width:340px;background:${window};border:1px solid rgba(255,255,255,.12);border-radius:12px;box-shadow:0 20px 60px rgba(0,0,0,.55),0 0 0 .5px rgba(0,0,0,.6);padding:10px;font-size:13px}
  .popover hr{border:0;border-top:1px solid rgba(255,255,255,.1);margin:6px 0}
  .prompt{display:flex;align-items:center;gap:6px}
  .field{flex:1;padding:4px 8px;border-radius:6px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.16);color:${tertiary};font-size:12px;line-height:16px}
  .field.typed{color:${label};border-color:${blue};box-shadow:0 0 0 3px rgba(10,132,255,.3)}
  .caret{display:inline-block;width:1px;height:12px;background:${label};vertical-align:-2px;margin-left:1px}
  .plus{font-weight:600;padding:2px 9px;border-radius:6px;background:rgba(255,255,255,.1);font-size:14px;line-height:18px}
  .hint{font-size:9px;color:${tertiary};margin:3px 0 0 2px}
  .group{display:flex;align-items:center;gap:6px;padding:6px 4px 0;font-size:11px;font-weight:700;color:${secondary}}
  .group b{margin-left:auto;font-size:10px;font-weight:400;color:${tertiary}}
  .row{position:relative;padding:3px 0 3px 6px;border-radius:5px}
  .row.front::before{content:"";position:absolute;left:0;top:4px;bottom:4px;width:2px;border-radius:1px;background:${blue}}
  .row.hover{background:rgba(255,255,255,.08)}
  .row.gone{opacity:.4}
  .line{display:flex;align-items:center;gap:8px;padding:1px 4px}
  .ctx{height:2px;margin:2px 4px 0;background:rgba(255,255,255,.08)}.ctx i{display:block;height:100%}
  .answer{display:flex;gap:4px;font-size:10px;padding-right:4px}
  .answer span{padding:1px 7px;border-radius:5px;background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.1)}
  .answer .ok{color:${green};border-color:rgba(48,209,88,.4)}
  .answer .pressed{background:${green};color:#04250f;border-color:${green};box-shadow:0 0 0 3px rgba(48,209,88,.28)}
  .carry{padding:3px 4px 0}.carry span{font-size:10px;padding:1px 7px;border-radius:5px;background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.1)}
  .slow{font-size:9px;font-weight:700;padding:1px 3px;border-radius:3px;background:rgba(255,159,10,.25);margin-left:5px;vertical-align:1px}
  .dot{width:8px;height:8px;border-radius:50%;flex:none}
  .txt{flex:1;min-width:0}.name{font-weight:600;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .chip{display:inline-block;font-size:9px;font-weight:700;border:1px solid ${secondary};border-radius:3px;padding:0 3px;margin-left:5px;vertical-align:1px;line-height:12px}
  .group .chip{margin-left:0}
  .detail{font-family:ui-monospace,Menlo,monospace;font-size:10px;color:${secondary};white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .detail.note{color:${label}}
  .right{text-align:right}.status{font-size:9px;font-weight:700;letter-spacing:.3px}.elapsed{font-size:10px;color:${secondary}}
  .acct{display:flex;align-items:center;gap:6px;padding:2px 4px;font-size:11px}.acct .path{color:${secondary};flex:1}.acct .use{font-size:10px;color:${secondary}}.acct .limit{font-size:10px;font-weight:600;color:${blue}}
  .acct .chip{margin:0}.live{font-size:9px;font-weight:600;color:${tertiary};margin-left:2px}
  .bars{display:flex;align-items:center;gap:5px;padding:0 4px 3px;font-size:9px}
  .bars .lbl{width:24px;font-weight:600;color:${secondary}}.bars .bar{flex:1;height:4px;border-radius:2px;background:rgba(255,255,255,.12);overflow:hidden}.bars .bar i{display:block;height:100%;border-radius:2px}
  .bars .pct{width:30px;text-align:right;font-weight:600}.bars .at{color:${tertiary};width:44px}
  .fc{display:flex;align-items:center;gap:6px;font-size:9px;color:${secondary};padding:0 4px 4px}
  .remote{font-size:11px;font-weight:600;padding:2px 4px}
  .talk{display:flex;align-items:center;gap:6px;padding:4px}.talk.rec{color:${red}}.hot{margin-left:auto;font-size:11px;color:${secondary}}
  .foot{display:flex;gap:10px;font-size:11px;color:${secondary};padding:2px 4px;white-space:nowrap}.foot a{color:${blue}}.foot .sp{flex:1}
  .banner{width:360px;background:rgba(40,40,46,.92);backdrop-filter:blur(30px);border:1px solid rgba(255,255,255,.12);border-radius:14px;box-shadow:0 12px 40px rgba(0,0,0,.45);padding:12px 14px;display:flex;gap:12px;align-items:center}
  .banner .ico{width:38px;height:38px;border-radius:9px;background:#10142A;display:flex;align-items:center;justify-content:center;flex:none}
  .banner b{display:block;font-size:13px}.banner span{font-size:12px;color:${secondary}}.banner small{margin-left:auto;font-size:11px;color:${tertiary};align-self:flex-start}
`;

// ---- the board at a few moments -------------------------------------------

/** t is the moment in the story; the same rows, their state moving. */
const groupsAt = (t) => {
	const corgi = t < 5
		? { name: "corgi", title: "Fix the login redirect", front: true, detail: t < 1 ? "Read auth.go" : "Edit registry.go", status: "WORKING", color: amber, elapsed: ["9s", "15s", "22s", "30s", "41s"][t] ?? "41s", ctx: 41 + t * 2 }
		: { name: "corgi", title: "Fix the login redirect", front: true, detail: "2 files changed", status: "DONE", color: green, elapsed: "3s", ctx: 52 };
	const corgi2 = { name: "corgi 2", detail: "waiting on PR review", note: true, status: "DONE", color: green, elapsed: "11m", ctx: 23 };
	const acme = [
		{ name: "acme-api", detail: "Bash go test", status: "WORKING", color: amber, elapsed: "8m", ctx: 72 },
		{ name: "acme-api", detail: "permission: Bash go test", status: "NEEDS YOU", color: red, elapsed: "2s", ctx: 72, pending: true },
		{ name: "acme-api", detail: "permission: Bash go test", status: "NEEDS YOU", color: red, elapsed: "6s", ctx: 72, pending: true, pressed: "allow" },
		{ name: "acme-api", detail: "Bash go test", status: "WORKING", color: amber, elapsed: "1s", ctx: 73 },
		{ name: "acme-api", detail: "Bash go test", status: "DONE", color: green, elapsed: "2s", ctx: 74 },
		{ name: "acme-api", detail: "Bash go test", status: "DONE", color: green, elapsed: "12s", ctx: 74 },
	][Math.min(t, 5)];
	const web = { name: "web", detail: "no activity 13m", status: "WORKING", color: amber, elapsed: "13m", ctx: 58, slow: true };
	return [
		{ label: "corgi", sessions: [corgi, corgi2] },
		{ label: "acme-api", chip: "WK", sessions: [acme] },
		{ label: "web", sessions: [web] },
		{ label: "mobile", chip: "WK", sessions: [{ name: "mobile", detail: "resets 1:10pm", status: "LIMIT", color: blue, carry: "default" }] },
		{ label: "billing", sessions: [{ name: "billing", status: "IDLE", color: secondary, elapsed: "31m" }] },
	];
};

const needsAt = (t) => (t === 1 || t === 2 ? 1 : 0);
const moodAt = (t) => (needsAt(t) ? red : t >= 5 ? green : amber);

// ---- pages -----------------------------------------------------------------

const desktop = ({ t = 1, open = true, banner = false, needs = needsAt(t), mood = moodAt(t), width = 1920, height = 1080 }) => `<!doctype html><meta charset="utf-8"><title>corgi-bar</title>
<style>${css}
  html,body{width:${width}px;height:${height}px;overflow:hidden}
  .desk{position:relative;width:${width}px;height:${height}px;background:
    radial-gradient(900px 600px at 20% 30%,#5b6cff 0%,transparent 60%),
    radial-gradient(900px 700px at 80% 70%,#ff7a59 0%,transparent 60%),
    radial-gradient(700px 500px at 60% 20%,#2ad3c6 0%,transparent 55%),
    linear-gradient(160deg,#0f1226,#1a1b3a 60%,#3b2a4f)}
  .bar{position:absolute;top:0;left:0;right:0;height:38px;background:rgba(28,28,34,.72);backdrop-filter:blur(30px);display:flex;align-items:center;justify-content:space-between;padding:0 18px;color:#f2f2f5;font-size:15px}
  .bar .left b{font-weight:700;margin-right:18px}.bar .left span{margin-right:18px;opacity:.95}
  .bar .right{display:flex;align-items:center;gap:16px}
  .item{display:flex;align-items:center;gap:5px;padding:3px 8px;border-radius:6px}
  .item.active{background:rgba(255,255,255,.18)}
  .badge{font-weight:700;font-size:13px}
  .icons svg,.icons img{vertical-align:middle;opacity:.95}
  .popover{position:absolute;top:44px;right:280px}
  .banner{position:absolute;top:52px;right:20px}
  .copy{position:absolute;left:120px;bottom:120px;color:#fff;max-width:640px;text-shadow:0 2px 20px rgba(0,0,0,.4)}
  .copy h1{font-size:56px;margin:0 0 10px;letter-spacing:-.02em}.copy p{font-size:22px;line-height:1.45;margin:0;opacity:.9}
</style>
<div class="desk">
  <div class="bar">
    <div class="left"><b></b><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span></div>
    <div class="right icons">
      <div class="item ${open ? "active" : ""}">${dog(mood)}${needs > 0 ? `<span class="badge">${needs}</span>` : ""}</div>
      <svg width="18" height="14" viewBox="0 0 18 14" fill="#fff"><path d="M9 11.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zM5.8 8.3l1.4 1.4a2.5 2.5 0 0 1 3.6 0l1.4-1.4a4.5 4.5 0 0 0-6.4 0zM3 5.5l1.4 1.4a6.5 6.5 0 0 1 9.2 0L15 5.5a8.5 8.5 0 0 0-12 0zM0 2.6l1.4 1.4a10.5 10.5 0 0 1 15.2 0L18 2.6a12.5 12.5 0 0 0-18 0z"/></svg>
      <svg width="26" height="12" viewBox="0 0 26 12" fill="none" stroke="#fff"><rect x=".5" y=".5" width="22" height="11" rx="3"/><rect x="2" y="2" width="17" height="8" rx="1.5" fill="#fff" stroke="none"/><path d="M24 4v4" stroke-width="1.5"/></svg>
      <span>Tue 9 Sep&nbsp;&nbsp;13:04</span>
    </div>
  </div>
  ${open ? popover({ groups: groupsAt(t) }) : ""}
  ${banner ? `<div class="banner"><div class="ico">${dog(amber, 24)}</div><div><b>acme-api needs you</b><span>Bash go test</span></div><small>now</small></div>` : ""}
  <div class="copy"><h1>corgi-bar</h1><p>Every Claude Code session in your menu bar. Amber while it works, red when it needs you, blue when the account hit its limit. Click a row to jump to it. Allow from the bar. Talk to dictate.</p></div>
</div>`;

/** A close-up on a flat ground: the popover alone, for crops and stories. */
const closeup = (opts) => `<!doctype html><meta charset="utf-8"><title>corgi-bar</title>
<style>${css}
  html,body{width:420px;height:900px;overflow:hidden;background:${ground}}
  .popover{position:absolute;top:24px;left:40px}
</style>
${popover(opts)}`;

/** The menu bar item alone, big, for the state strip. */
const item = ({ mood, needs }) => `<!doctype html><meta charset="utf-8"><title>corgi-bar</title>
<style>${css}
  html,body{width:600px;height:300px;overflow:hidden;background:${ground}}
  .strip{position:absolute;left:0;top:0;width:600px;height:300px;display:flex;align-items:center;justify-content:center;color:#f2f2f5}
  .item{display:flex;align-items:center;gap:16px;padding:14px 28px;border-radius:20px;background:rgba(255,255,255,.06)}
  .item img{width:72px;height:72px}.badge{font-weight:700;font-size:56px}
</style>
<div class="strip"><div class="item">${dog(mood, 40)}${needs ? `<span class="badge">${needs}</span>` : ""}</div></div>`;

// ---- write -------------------------------------------------------------------

const out = "docs/media";
rmSync(`${out}/frames`, { recursive: true, force: true });
mkdirSync(`${out}/frames`, { recursive: true });
const write = (name, html) => writeFileSync(`${out}/${name}`, html);

write("hero.html", desktop({ t: 1 }));
write("notification.html", desktop({ t: 1, open: false, banner: true }));
write("frames/accounts.html", closeup({ groups: [], part: "accounts" }));

// The story: a session asks, you allow from the bar, it finishes, yours finishes.
for (let t = 0; t <= 5; t++) write(`frames/story-${t}.html`, closeup({ groups: groupsAt(t) }));

// Talk: press, it records, press again and the words land in the front session.
write("frames/talk-0.html", closeup({ groups: groupsAt(3), part: "talk" }));
write("frames/talk-1.html", closeup({ groups: groupsAt(3), part: "talk", talk: "rec" }));
write("frames/talk-2.html", closeup({ groups: groupsAt(3), part: "talk", prompt: "run the tests and fix what fails" }));
write("frames/talk-3.html", closeup({ groups: groupsAt(3), part: "talk", placeholder: "Sent to Fix the login redirect" }));

// The item through its moods.
[
	{ mood: "#e8e8ea", needs: 0 }, { mood: amber, needs: 0 }, { mood: red, needs: 1 }, { mood: red, needs: 2 },
	{ mood: amber, needs: 0 }, { mood: green, needs: 0 }, { mood: blue, needs: 0 },
].forEach((m, i) => write(`frames/bar-${i}.html`, item(m)));

console.log("wrote docs/media/hero.html notification.html + frames/");
