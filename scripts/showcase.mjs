// Draws the README pictures: a macOS desktop with the corgi-bar item open,
// as HTML for Chrome to screenshot. The rows mirror App.swift, so keep the
// two in step when the layout changes.
import { mkdirSync, writeFileSync } from "node:fs";

const amber = "#F5A623", red = "#E5484D", green = "#30A46C", blue = "#5B8DEF", grey = "#8E8E93";

const sessions = [
	{ name: "corgi", chip: "", front: true, detail: "Bash", status: "WORKING", color: amber, elapsed: "15s" },
	{ name: "acme-api", chip: "WK", front: false, detail: "permission: Bash", status: "NEEDS YOU", color: red, elapsed: "9m" },
	{ name: "web", chip: "WK", front: false, detail: "question", status: "NEEDS YOU", color: red, elapsed: "2m" },
	{ name: "agent-deck", chip: "", front: false, detail: "", status: "DONE", color: green, elapsed: "11m" },
	{ name: "mobile", chip: "WK", front: false, detail: "resets 1:10pm", status: "LIMIT", color: blue, elapsed: "" },
	{ name: "billing", chip: "", front: false, detail: "", status: "IDLE", color: grey, elapsed: "31m" },
];

const dog = (color, size = 16) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 5.2 8.5 3H5l-1 5 3 2.5V14a5 5 0 0 0 5 5h2a5 5 0 0 0 5-5v-3.5L22 8l-1-5h-3.5L16 5.2"/><path d="M9 12h.01M15 12h.01M12 15v1"/></svg>`;

const row = (s) => `
<div class="row">
  <span class="dot" style="background:${s.color}"></span>
  <div class="txt">
    <div class="name">${s.name}${s.chip ? `<span class="chip">${s.chip}</span>` : ""}${s.front ? `<span class="front">●</span>` : ""}</div>
    ${s.detail ? `<div class="detail">${s.detail}</div>` : ""}
  </div>
  <div class="right"><div class="status" style="color:${s.color}">${s.status}</div><div class="elapsed">${s.elapsed}</div></div>
</div>`;

const popover = () => `
<div class="popover">
  <div class="btn"><span class="plus">＋</span> New session</div>
  <hr>
  ${sessions.map(row).join("")}
  <hr>
  <div class="acct"><span class="path">~/.claude</span><span class="use">178.0M today · 1.6B week</span></div>
  <div class="bars"><span class="lbl">5h</span><span class="bar"><i style="width:55%;background:${green}"></i></span><span class="pct" style="color:${green}">55%</span><span class="at">5:10pm</span>
    <span class="lbl">week</span><span class="bar"><i style="width:10%;background:${green}"></i></span><span class="pct" style="color:${green}">10%</span><span class="at">mon 9am</span></div>
  <div class="acct"><span class="chip">WK</span><span class="path">~/.claude-work</span><span class="limit">resets 1:10pm</span></div>
  <div class="bars"><span class="lbl">5h</span><span class="bar"><i style="width:100%;background:${red}"></i></span><span class="pct" style="color:${red}">100%</span><span class="at">1:10pm</span>
    <span class="lbl">week</span><span class="bar"><i style="width:64%;background:${amber}"></i></span><span class="pct" style="color:${amber}">64%</span><span class="at">thu 6am</span></div>
  <hr>
  <div class="remote">▸ Remote · 5 of 5 online</div>
  <hr>
  <div class="talk"><span class="mic">🎙</span> Talk <span class="hot">ctrl+alt+space</span></div>
  <hr>
  <div class="foot"><span>corgi 1.21.40 · daemon running</span><span>Settings…&nbsp;&nbsp;Quit</span></div>
</div>`;

const page = ({ needs = 2, mood = red, open = true, banner = true, width = 1920, height = 1080 }) => `<!doctype html><meta charset="utf-8"><title>corgi-bar</title>
<style>
  html,body{margin:0;width:${width}px;height:${height}px;overflow:hidden;font-family:-apple-system,"SF Pro Text",Inter,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;color:#111}
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
  .icons svg{vertical-align:middle;opacity:.9}
  .popover{position:absolute;top:44px;right:280px;width:340px;background:rgba(36,36,40,.86);backdrop-filter:blur(40px);border:1px solid rgba(255,255,255,.12);border-radius:12px;box-shadow:0 20px 60px rgba(0,0,0,.55);padding:10px;color:#f2f2f5;font-size:13px}
  .popover hr{border:0;border-top:1px solid rgba(255,255,255,.1);margin:6px 0}
  .btn{padding:6px 8px;border-radius:6px;background:rgba(255,255,255,.08)}.plus{font-weight:600;margin-right:4px}
  .row{display:flex;align-items:center;gap:8px;padding:4px 4px;border-radius:5px}
  .row:nth-child(4){background:rgba(255,255,255,.08)}
  .dot{width:8px;height:8px;border-radius:50%;flex:none}
  .txt{flex:1;min-width:0}.name{font-weight:600;font-size:13px}
  .chip{display:inline-block;font-size:9px;font-weight:700;border:1px solid rgba(255,255,255,.45);border-radius:3px;padding:0 3px;margin-left:5px;vertical-align:1px}
  .front{font-size:8px;opacity:.6;margin-left:5px;vertical-align:2px}
  .detail{font-family:ui-monospace,Menlo,monospace;font-size:10px;opacity:.65;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .right{text-align:right}.status{font-size:9px;font-weight:700;letter-spacing:.3px}.elapsed{font-size:10px;opacity:.6}
  .acct{display:flex;align-items:center;gap:6px;padding:2px 4px;font-size:11px}.acct .path{opacity:.65;flex:1}.acct .use{font-size:10px;opacity:.6}.acct .limit{font-size:10px;font-weight:600;color:${blue}}
  .acct .chip{margin:0}
  .bars{display:flex;align-items:center;gap:5px;padding:0 4px 4px 4px;font-size:9px}
  .bars .lbl{width:24px;font-weight:600;opacity:.6}.bars .bar{flex:1;height:4px;border-radius:2px;background:rgba(255,255,255,.12);overflow:hidden}.bars .bar i{display:block;height:100%;border-radius:2px}
  .bars .pct{width:30px;text-align:right;font-weight:600}.bars .at{opacity:.45;width:44px}
  .remote{font-size:11px;font-weight:600;padding:2px 4px}
  .talk{display:flex;align-items:center;gap:6px;padding:4px}.hot{margin-left:auto;font-size:11px;opacity:.6}
  .foot{display:flex;justify-content:space-between;font-size:11px;opacity:.7;padding:2px 4px}
  .banner{position:absolute;top:52px;right:20px;width:360px;background:rgba(40,40,46,.9);backdrop-filter:blur(30px);border:1px solid rgba(255,255,255,.12);border-radius:14px;box-shadow:0 12px 40px rgba(0,0,0,.45);padding:12px 14px;color:#f2f2f5;display:flex;gap:12px;align-items:center}
  .banner .ico{width:38px;height:38px;border-radius:9px;background:#10142A;display:flex;align-items:center;justify-content:center}
  .banner b{display:block;font-size:13px}.banner span{font-size:12px;opacity:.75}.banner small{margin-left:auto;font-size:11px;opacity:.5;align-self:flex-start}
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
      <span>Mon 8 Sep&nbsp;&nbsp;13:04</span>
    </div>
  </div>
  ${open ? popover() : ""}
  ${banner ? `<div class="banner"><div class="ico">${dog("#F5A623", 24)}</div><div><b>acme-api needs you</b><span>permission: Bash</span></div><small>now</small></div>` : ""}
  <div class="copy"><h1>corgi-bar</h1><p>Every Claude Code session in your menu bar. Amber while it works, red when it needs you, blue when the account hit its limit. Click a row to jump to it. Talk to dictate.</p></div>
</div>`;

mkdirSync("docs/media/frames", { recursive: true });
writeFileSync("docs/media/hero.html", page({ banner: false }));
writeFileSync("docs/media/notification.html", page({ open: false, banner: true }));
writeFileSync("docs/media/quiet.html", page({ needs: 0, mood: amber, open: false, banner: false }));
const moods = [
	{ needs: 0, mood: "#e8e8ea", banner: false },
	{ needs: 0, mood: amber, banner: false },
	{ needs: 1, mood: red, banner: true },
	{ needs: 2, mood: red, banner: true },
	{ needs: 0, mood: green, banner: false },
	{ needs: 0, mood: blue, banner: false },
];
moods.forEach((m, i) => writeFileSync(`docs/media/frames/bar-${i}.html`, page({ ...m, open: false })));
console.log("wrote docs/media/hero.html quiet.html + 6 frames");
