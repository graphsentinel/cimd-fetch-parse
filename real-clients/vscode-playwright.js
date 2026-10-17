#!/usr/bin/env node
// Drives VS Code (Electron) with Playwright: MCP: List Servers -> <server> -> Start Server -> allow authentication.
//   vscode-playwright.js <server-name>      (env TRIAL_OUT; VS Code profile/extensions under it; screenshots to vscode-screens/)
// VS Code opens the login URL with its own opener (xdg-open from PATH -> open-url.sh). Success is judged elsewhere, from
// the MCP server's log; this script only acts and records what VS Code showed.
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");
const { spawn } = require("child_process");

const NAME = process.argv[2];
const OUT = process.env.TRIAL_OUT;
const SHOTS = path.join(OUT, "vscode-screens");
fs.mkdirSync(SHOTS, { recursive: true });
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
let n = 0;

(async () => {
  // VS Code disables Playwright's Electron launcher (Node inspect fuse); start it with a DevTools port and attach over CDP
  const port = 9300 + Math.floor(Math.random() * 500);
  const proc = spawn("/usr/share/code/code", [path.join(OUT, "workspace"), "--user-data-dir", path.join(OUT, "profile"), "--extensions-dir", path.join(OUT, "extensions"),
    "--disable-workspace-trust", "--skip-welcome", "--skip-release-notes", "--disable-gpu", "--no-sandbox", "--new-window", "--password-store=basic", `--remote-debugging-port=${port}`],
    { env: { ...Object.fromEntries(Object.entries(process.env).filter(([k]) => !/^(ELECTRON_|VSCODE_)/.test(k))), HOME: path.join(OUT, "home") }, stdio: ["ignore", "pipe", "pipe"] }); // own HOME: no access to your accounts // no inherited editor env (ELECTRON_RUN_AS_NODE would start it as plain Node)
  proc.stdout.on("data", (d) => fs.appendFileSync(path.join(OUT, "vscode-stdout.txt"), d)); proc.stderr.on("data", (d) => fs.appendFileSync(path.join(OUT, "vscode-stdout.txt"), d));
  let browser; for (let i = 0; i < 60 && !browser; i++) { await new Promise((r) => setTimeout(r, 1000)); browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`).catch(() => null); }
  if (!browser) throw new Error("could not attach to VS Code over CDP");
  let win; for (let i = 0; i < 60 && !win; i++) { win = browser.contexts().flatMap((c) => c.pages()).find((p) => /workbench/.test(p.url())); if (!win) await new Promise((r) => setTimeout(r, 1000)); }
  if (!win) throw new Error("no VS Code workbench window");
  const app = { close: async () => { await browser.close().catch(() => {}); proc.kill("SIGTERM"); } };
  const shot = async (what) => { const f = `${String(n++).padStart(2, "0")}-${what}.png`; await win.screenshot({ path: path.join(SHOTS, f) }).catch(() => {}); log("screenshot", f); };
  const quick = async () => (await win.locator(".quick-input-widget .monaco-list-row").allInnerTexts().catch(() => [])).map((s) => s.replace(/\s+/g, " ").trim());
  const mcpLog = () => { try { return fs.readFileSync(path.join(OUT, "mcp-requests.jsonl"), "utf8"); } catch { return ""; } };
  await win.waitForLoadState("domcontentloaded"); await win.waitForTimeout(6000); await shot("started");

  const palette = async (text) => { await win.keyboard.press("F1"); await win.waitForTimeout(700); await win.keyboard.type(text, { delay: 15 }); await win.waitForTimeout(900); };
  await palette("MCP: List Servers"); log("palette rows", JSON.stringify(await quick())); await win.keyboard.press("Enter"); await win.waitForTimeout(1500);
  log("servers", JSON.stringify(await quick())); await shot("servers");
  await win.keyboard.type(NAME, { delay: 15 }); await win.waitForTimeout(600); await win.keyboard.press("Enter"); await win.waitForTimeout(1500);
  log("actions", JSON.stringify(await quick())); await shot("actions");
  await win.keyboard.type("Start Server", { delay: 15 }); await win.waitForTimeout(600); await win.keyboard.press("Enter");

  // dialogs VS Code may show: trust this MCP server, allow it to authenticate; answer the positive one each time
  const deadline = Date.now() + 150000; let clicked = []; let triedAccounts = 0;
  while (Date.now() < deadline) {
    await win.waitForTimeout(1500);
    // a pending sign-in request sits in the Accounts menu (bottom left); open it and take the entry for this server
    if (!/"valid": true/.test(mcpLog()) && triedAccounts < 3 && Date.now() > deadline - 140000 + triedAccounts * 20000) {
      triedAccounts++;
      const acc = win.locator('.activitybar [aria-label^="Accounts"], .activitybar .codicon-accounts-view-bar-icon').first();
      if (await acc.count() > 0) {
        await acc.click().catch(() => {}); await win.waitForTimeout(1200);
        const items = (await win.locator(".context-view .action-label, .monaco-menu .action-label").allInnerTexts().catch(() => [])).map((x) => x.trim()).filter(Boolean);
        log("accounts menu", JSON.stringify(items)); await shot(`accounts-${triedAccounts}`);
        // only the entry for THIS server (its name or the realm's host:port); never a generic "sign in" (other accounts)
        const hp = (process.env.AS_HOSTPORT || NAME).replace(/[.]/g, "\\.");
        const item = win.locator(".context-view .action-label, .monaco-menu .action-label").filter({ hasText: new RegExp(`${NAME}|${hp}`, "i") }).first();
        if (await item.count() > 0) { log("click", await item.innerText()); await item.click(); clicked.push("accounts:" + (await item.innerText().catch(() => "?"))); continue; }
        await win.keyboard.press("Escape");
      }
    }
    const btn = win.locator(".monaco-dialog-box .monaco-button, .notification-toast .monaco-button").filter({ hasText: /^(Allow|Trust|Start|Continue|Yes)$/ });
    if (await btn.count() > 0) {
      const dlg = ((await win.locator(".monaco-dialog-box, .notification-toast").first().innerText().catch(() => "")) || "").replace(/\s+/g, " ").slice(0, 300);
      const t = (await btn.first().innerText()).trim(); log("dialog:", dlg, "-> click", t); await shot(`dialog-${t}`); await btn.first().click(); clicked.push(t); continue;
    }
    if (/"valid": true/.test(mcpLog()) && /tools\/list/.test(mcpLog())) { log("MCP server log: tools/list with a valid token"); break; }
    // the server's own action menu may hold the sign-in step (only actions of THIS server are considered)
    if (!/"valid": true/.test(mcpLog()) && !clicked.some((c) => c.startsWith("server-action")) && Date.now() > deadline - 120000) {
      await palette("MCP: List Servers"); await win.keyboard.press("Enter"); await win.waitForTimeout(1200);
      await win.keyboard.type(NAME, { delay: 15 }); await win.waitForTimeout(500); await win.keyboard.press("Enter"); await win.waitForTimeout(1200);
      const acts = await quick(); log("server actions", JSON.stringify(acts)); await shot("server-actions");
      const a = acts.find((x) => /auth|sign in|log in|login/i.test(x));
      if (a) { await win.keyboard.type(a.split(/\s{2,}/)[0].slice(0, 20), { delay: 15 }); await win.waitForTimeout(400); await win.keyboard.press("Enter"); clicked.push("server-action:" + a); }
      else { await win.keyboard.press("Escape"); clicked.push("server-action:none"); }
      continue;
    }
  }
  await win.waitForTimeout(3000); await shot("end");
  await palette("MCP: List Servers"); await win.keyboard.press("Enter"); await win.waitForTimeout(1500);
  log("servers at end", JSON.stringify(await quick())); await shot("servers-end"); await win.keyboard.press("Escape");
  log("dialogs answered", JSON.stringify(clicked));
  await app.close();
})().catch((e) => { log("ERROR", e.message); process.exit(1); });
