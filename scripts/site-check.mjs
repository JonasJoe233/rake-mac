// 官网验收：起一个无头 Chrome（独立临时 profile，不碰日常浏览器），按 1440 和 390 两种宽度、中英两种语言截图，
// 检查横向越界和 console 报错。用法：node scripts/site-check.mjs <站点 URL> <截图目录>
// 只用 Node 22 自带的 WebSocket 和 fetch，不装依赖。
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, out] = process.argv.slice(2);
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const profile = mkdtempSync(join(tmpdir(), "rake-chrome-"));
const port = 9300 + Math.floor(Math.random() * 500);
const proc = spawn(chrome, ["--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check", "--hide-scrollbars", "about:blank"], { stdio: "ignore" });
const sleep = ms => new Promise(r => setTimeout(r, ms));

let ws;
for (let i = 0; i < 50; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const page = list.find(t => t.type === "page");
    if (page) { ws = new WebSocket(page.webSocketDebuggerUrl); break; }
  } catch {}
  await sleep(200);
}
await new Promise(r => ws.addEventListener("open", r));
let id = 0; const pending = new Map(), logs = [];
ws.addEventListener("message", e => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  if (m.method === "Runtime.consoleAPICalled" && ["error", "warning"].includes(m.params.type))
    logs.push(`${m.params.type}: ${m.params.args.map(a => a.value ?? a.description).join(" ")}`);
  if (m.method === "Runtime.exceptionThrown") logs.push("exception: " + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text));
  if (m.method === "Log.entryAdded" && m.params.entry.level === "error") logs.push("log: " + m.params.entry.text + " " + (m.params.entry.url || ""));
});
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send("Runtime.enable"); await send("Log.enable"); await send("Page.enable");

const results = [];
for (const lang of ["en", "zh-Hans"]) {
  for (const [w, h, mobile] of [[1440, 900, false], [390, 844, true]]) {
    logs.length = 0;
    await send("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: 2, mobile });
    await send("Emulation.setUserAgentOverride", { userAgent: "Mozilla/5.0", acceptLanguage: lang === "en" ? "en-US" : "zh-CN", platform: "MacIntel" });
    await send("Page.navigate", { url: url + (url.includes("?") ? "&" : "?") + "lang=" + lang });
    await sleep(1500);
    // 卵石图在 See it. 段，滚到才开始画（3.2 秒）；入场动画也要滚到才触发。逐屏滚一遍再回顶部
    await send("Runtime.evaluate", { awaitPromise: true, expression: `(async () => { const s = ms => new Promise(r => setTimeout(r, ms));
      for (let y = 0; y < document.documentElement.scrollHeight; y += innerHeight / 2) { scrollTo(0, y); await s(120); }
      document.querySelector("#art").scrollIntoView({ block: "center" }); await s(4000); scrollTo(0, 0); await s(600); })()` });
    const m = await send("Runtime.evaluate", { returnByValue: true, expression: `(() => {
      const de = document.documentElement, vw = de.clientWidth, bad = [];
      document.querySelectorAll("body *").forEach(e => { const r = e.getBoundingClientRect();
        if (r.width && (r.right > vw + 1 || r.left < -1) && !e.closest("svg") && getComputedStyle(e).position !== "fixed") bad.push(e.tagName + (e.id ? "#" + e.id : "") + (e.className && typeof e.className === "string" ? "." + e.className : "") + " " + Math.round(r.left) + ".." + Math.round(r.right)); });
      const art = document.querySelector("#svg").getBoundingClientRect();
      return { scrollW: de.scrollWidth, vw, bad: bad.slice(0, 8), stones: document.querySelectorAll("#svg .it").length,
               sel: document.querySelectorAll("#svg .it.sel").length, art: [Math.round(art.left), Math.round(art.right)],
               lang: de.lang, h1: document.querySelector("h1").textContent, fold: document.querySelector("#dl").getBoundingClientRect().bottom <= innerHeight };
    })()` });
    const v = m.result.result.value;
    const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
    const name = `site-${w}-${lang}.png`;
    writeFileSync(join(out, name), Buffer.from(shot.result.data, "base64"));
    const full = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true,
      clip: { x: 0, y: 0, width: w, height: (await send("Runtime.evaluate", { expression: "document.documentElement.scrollHeight", returnByValue: true })).result.result.value, scale: 1 } });
    writeFileSync(join(out, `site-${w}-${lang}-full.png`), Buffer.from(full.result.data, "base64"));
    results.push({ name, ...v, overflow: v.scrollW > v.vw, console: [...logs] });
  }
}
console.log(JSON.stringify(results, null, 1));
ws.close(); proc.kill(); await sleep(300); rmSync(profile, { recursive: true, force: true });
const fail = results.some(r => r.overflow || r.bad.length || r.console.length || !r.stones);
process.exit(fail ? 1 : 0);
