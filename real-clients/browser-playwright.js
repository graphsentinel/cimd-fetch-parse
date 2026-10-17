#!/usr/bin/env node
// A real (headless) Chromium, driven by Playwright, in place of the person at the browser.
//   browser-playwright.js <url>     (results to $TRIAL_OUT/browser.jsonl, screenshots to $TRIAL_OUT/screens/)
// Records what the client put in the authorization URL and every response on the way; then, like a person: Keycloak's
// login form -> the lab user -> consent (if shown) -> the client's own loopback callback. Same record format as
// browser-driver.py. Codes and tokens are never written (the callback URL is recorded without its query).
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const URL_ = process.argv[2];
const OUT = process.env.TRIAL_OUT || ".";
const SHOTS = path.join(OUT, "screens");
const USER = "alice", PASS = "alice-lab-only"; // lab-only test user
fs.mkdirSync(SHOTS, { recursive: true });

(async () => {
  const u = new URL(URL_), q = u.searchParams, kcHost = u.host;
  const rec = {
    utc: new Date().toISOString(), browser: "playwright-chromium", auth_url_host: u.host, auth_url_path: u.pathname,
    client_id: q.get("client_id"), redirect_uri: q.get("redirect_uri"), scope: q.get("scope"), resource: q.get("resource"),
    code_challenge_method: q.get("code_challenge_method"), response_type: q.get("response_type"), steps: [], result: "refused_at_authorize",
  };
  const b = await chromium.launch();
  const page = await (await b.newContext()).newPage();
  const shot = async (n) => { const f = `${String(rec.steps.length).padStart(2, "0")}-${n}.png`; await page.screenshot({ path: path.join(SHOTS, f) }).catch(() => {}); return f; };
  const message = async () => (await page.locator("#kc-error-message, .instruction, #input-error, .kc-feedback-text").first().textContent({ timeout: 1500 }).catch(() => null))?.trim() || null;
  let callback = null;
  page.on("request", (r) => { const x = new URL(r.url()); if (x.host !== kcHost && r.isNavigationRequest()) callback = x; });

  const resp = await page.goto(URL_, { waitUntil: "domcontentloaded", timeout: 60000 }).catch((e) => ({ status: () => 0, err: e.message }));
  const first = resp.request ? resp.request().redirectedFrom() : null;
  const loginForm = await page.locator("#kc-form-login").count() > 0;
  rec.steps.push({ step: "authorize", status: first ? (await first.response())?.status() ?? resp.status() : resp.status(), login_form: loginForm, message: loginForm ? null : await message(), screenshot: await shot("authorize") });

  if (callback && !loginForm) { // Keycloak redirected straight back to the client: an OAuth error (or a code)
    rec.callback_error = callback.searchParams.get("error"); rec.callback_error_description = callback.searchParams.get("error_description");
    rec.steps.push({ step: "client_callback", status: resp.status(), target: `${callback.protocol}//${callback.host}${callback.pathname}` });
    rec.result = rec.callback_error ? `error_redirect:${rec.callback_error}` : "code_without_login";
  }
  if (loginForm) {
    rec.result = "login_page";
    await page.fill("#username", USER); await page.fill("#password", PASS);
    await Promise.all([page.waitForLoadState("domcontentloaded").catch(() => {}), page.click("#kc-login")]);
    rec.steps.push({ step: "login", url_host: new URL(page.url()).host, screenshot: await shot("after-login") });
    for (let i = 0; i < 4 && new URL(page.url()).host === kcHost; i++) {
      if (await page.locator('input[name="accept"], button[name="accept"]').count() > 0) {
        await Promise.all([page.waitForLoadState("domcontentloaded").catch(() => {}), page.click('[name="accept"]')]);
        rec.steps.push({ step: "consent", url_host: new URL(page.url()).host, screenshot: await shot("after-consent") });
      } else { rec.steps.push({ step: "stuck", message: await message(), screenshot: await shot("stuck") }); rec.result = "stuck_in_keycloak"; break; }
    }
    await page.waitForURL((x) => x.host !== kcHost, { timeout: 30000 }).catch(() => {});
    const x = new URL(page.url());
    if (x.host !== kcHost) {
      rec.callback_has_code = x.searchParams.has("code"); rec.callback_error = x.searchParams.get("error");
      rec.steps.push({ step: "client_callback", target: `${x.protocol}//${x.host}${x.pathname}`, page_text: ((await page.textContent("body").catch(() => "")) || "").trim().slice(0, 120), screenshot: await shot("client-callback") });
      rec.result = rec.callback_has_code ? "code_delivered_to_client" : "callback_failed";
    }
  }
  fs.appendFileSync(path.join(OUT, "browser.jsonl"), JSON.stringify(rec) + "\n");
  await b.close();
})().catch((e) => { fs.appendFileSync(path.join(OUT, "browser.jsonl"), JSON.stringify({ utc: new Date().toISOString(), browser: "playwright-chromium", error: e.message, steps: [], result: "driver_error" }) + "\n"); process.exit(1); });
