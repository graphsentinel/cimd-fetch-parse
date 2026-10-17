#!/usr/bin/env python3
"""Stands in for the browser an MCP client opens for OAuth login.
  browser-driver.py <url>     (called by the fake xdg-open / $BROWSER; results go to $TRIAL_OUT/browser.jsonl)
Records what the CLIENT put in the authorization URL, then plays the user: Keycloak login form -> credentials ->
consent (if shown) -> the redirect back to the client's own loopback callback, which is requested so the client can
finish the token exchange. Records every step's status; never records codes or tokens.
"""
import datetime, html, http.cookiejar, json, os, re, sys, urllib.error, urllib.parse, urllib.request

URL = sys.argv[1]
OUT = os.path.join(os.environ.get("TRIAL_OUT", "."), "browser.jsonl")
USER, PASS = "alice", "alice-lab-only"   # lab-only test user


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


class LoopbackSecure(http.cookiejar.DefaultCookiePolicy):
    """Like a browser: loopback (127.0.0.0/8, localhost) is a potentially trustworthy origin, so Secure cookies are
    sent over http there (Keycloak marks its session cookies Secure)."""
    def return_ok_secure(self, cookie, request):
        h = urllib.parse.urlparse(request.get_full_url()).hostname or ""
        return h == "localhost" or h.startswith("127.") or super().return_ok_secure(cookie, request)


jar = http.cookiejar.CookieJar(policy=LoopbackSecure())
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), NoRedirect)


def req(url, data=None):
    try:
        r = op.open(urllib.request.Request(url, data=data), timeout=60)
        return r.status, r.headers.get("Location"), r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Location"), e.read().decode("utf-8", "replace")
    except Exception as e:
        return 0, None, f"{type(e).__name__}: {e}"


def form(page, form_id=None):
    m = re.search(r'<form[^>]*id="%s"[^>]*action="([^"]+)"' % form_id if form_id else r'<form[^>]*action="([^"]+)"', page)
    return html.unescape(m.group(1)) if m else None


def message(page):
    m = re.search(r'class="(?:instruction|kc-feedback-text|pf-v5-c-alert__title[^"]*)"[^>]*>\s*([^<]+)', page)
    return m.group(1).strip() if m else None


q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(URL).query))
rec = {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
       "auth_url_host": urllib.parse.urlparse(URL).netloc, "auth_url_path": urllib.parse.urlparse(URL).path,
       "client_id": q.get("client_id"), "redirect_uri": q.get("redirect_uri"), "scope": q.get("scope"),
       "resource": q.get("resource"), "code_challenge_method": q.get("code_challenge_method"),
       "response_type": q.get("response_type"), "steps": []}
st, loc, page = req(URL)
rec["steps"].append({"step": "authorize", "status": st, "login_form": 'id="kc-form-login"' in page, "message": message(page)})
rec["result"] = "refused_at_authorize"
if st in (302, 303) and loc:  # Keycloak answered with a redirect to the client: an OAuth error (or a code)
    p = urllib.parse.urlparse(loc); cb = dict(urllib.parse.parse_qsl(p.query))
    rec["callback_error"] = cb.get("error"); rec["callback_error_description"] = cb.get("error_description")
    s2, _, _ = req(loc)
    rec["steps"].append({"step": "client_callback", "status": s2, "target": f"{p.scheme}://{p.netloc}{p.path}"})
    rec["result"] = f"error_redirect:{cb.get('error')}" if cb.get("error") else "code_without_login"
KC = urllib.parse.urlparse(URL)


def hidden(page, action):
    seg = page[page.find(action):]
    seg = seg[:seg.find("</form>")]
    return {html.unescape(n): html.unescape(v) for n, v in re.findall(r'<input[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*value="([^"]*)"', seg)}


if st == 200 and 'id="kc-form-login"' in page:
    rec["result"] = "login_page"
    act = form(page, "kc-form-login")
    st, loc, page = req(urllib.parse.urljoin(URL, act), urllib.parse.urlencode({"username": USER, "password": PASS}).encode())
    rec["steps"].append({"step": "login", "status": st})
    for _ in range(6):  # follow Keycloak's own pages (required actions, consent) until it redirects to the client
        if st in (302, 303) and loc:
            nxt = urllib.parse.urljoin(URL, loc); p = urllib.parse.urlparse(nxt)
            if p.netloc == KC.netloc:
                st, loc, page = req(nxt); rec["steps"].append({"step": "keycloak_page", "status": st, "path": p.path}); continue
            cb = dict(urllib.parse.parse_qsl(p.query))
            rec["callback_has_code"] = "code" in cb; rec["callback_error"] = cb.get("error")
            s2, _, _ = req(nxt)
            rec["steps"].append({"step": "client_callback", "status": s2, "target": f"{p.scheme}://{p.netloc}{p.path}"})
            rec["result"] = "code_delivered_to_client" if "code" in cb and s2 and s2 < 400 else "callback_failed"
            break
        if st == 200 and "login-actions/consent" in page:
            act = html.unescape(re.search(r'action="([^"]*login-actions/consent[^"]*)"', page).group(1))
            data = hidden(page, 'login-actions/consent'); data["accept"] = "Yes"
            st, loc, page = req(urllib.parse.urljoin(URL, act), urllib.parse.urlencode(data).encode())
            rec["steps"].append({"step": "consent", "status": st}); continue
        rec["result"] = "stuck_in_keycloak"; rec["steps"].append({"step": "stuck", "status": st, "message": message(page)})
        break
with open(OUT, "a") as f:
    f.write(json.dumps(rec) + "\n")
