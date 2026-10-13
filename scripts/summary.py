#!/usr/bin/env python3
"""Checks a test session and writes lab/.runtime/summary.md.

  summary.py <session>

Fail-closed: a session passes only if
  1. the plan exists and is not empty, and every planned check has expected values in lab/expected.tsv;
  2. every planned (version, check, run) has attempts 1..n on disk, the last one ends in exit 0 with a final PASS line, and every
     earlier one ended "NOT RUN [vendor-fetch]" (exit 77) — any other earlier ending (a FAIL, a final NOT RUN, a PASS)
     makes the cell a problem, so a FAIL can never be retried into a PASS;
  3. every field listed for the check in lab/expected.tsv was recorded exactly once with a matching value (regex);
  4. the authorization and registration requests the check observed (observed.jsonl: realm, client_id, HTTP status,
     in order) are exactly the ones the recording proxy saw for that run — same requests, same order, same statuses,
     none missing and none extra.
Exit 1 otherwise. Earlier attempts that ended NOT RUN [vendor-fetch] stay on disk and are listed, never counted.
"""
import collections
import csv
import glob
import json
import os
import re
import sys
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RT = os.path.join(ROOT, "lab", ".runtime")
AUTH = re.compile(r"^/realms/([^/]+)/protocol/openid-connect/auth$")
REG = re.compile(r"^/realms/([^/]+)/clients-registrations/openid-connect$")


def tsv(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def jsonl(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [json.loads(x) for x in f if x.strip()]


def proxy_requests(rows):
    """The auth / registration requests in the proxy record, in order, as (kind, realm, client_id, status)."""
    out = []
    for o in sorted(rows, key=lambda o: o["utc"]):
        u = urllib.parse.urlparse(o["path"])
        m = AUTH.match(u.path)
        if m and o["method"] == "GET":
            out.append(("auth", m.group(1), urllib.parse.parse_qs(u.query).get("client_id", [""])[0], str(o["status"])))
        m = REG.match(u.path)
        if m and o["method"] == "POST":
            out.append(("register", m.group(1), "-", str(o["status"])))
    return out


def verdicts(d):
    p = os.path.join(d, "stdout.txt")
    return [x for x in open(p).read().splitlines() if re.match(r"(PASS|FAIL|NOT RUN)", x)] if os.path.exists(p) else []


def last_line(d):
    v = verdicts(d)
    return v[-1] if v else ""


def main():
    session = sys.argv[1]
    problems, retried = [], []
    plan_path = os.path.join(RT, f"plan-{session}.tsv")
    plan = tsv(plan_path) if os.path.exists(plan_path) else []
    if not plan:
        problems.append(f"no plan or an empty plan for session {session}")
    expected = collections.defaultdict(list)
    for e in tsv(os.path.join(ROOT, "lab", "expected.tsv")):
        expected[e["check"]].append((e["field"], e["value"]))
    for c in sorted({p["check"] for p in plan}):
        if not expected.get(c):
            problems.append(f"check {c}: no expected values in lab/expected.tsv")
    rows, dups = collections.defaultdict(dict), collections.defaultdict(set)
    mpath = os.path.join(ROOT, "results", "measurements.tsv")
    for r in tsv(mpath) if os.path.exists(mpath) else []:
        if r["field"] in rows[r["run_id"]]:
            dups[r["run_id"]].add(r["field"])
        rows[r["run_id"]][r["field"]] = r["value"]
    cells = collections.defaultdict(lambda: [0, 0])
    for p in plan:
        v, c, n = p["version"], p["check"], p["run"]
        cells[(v, c)][1] += 1
        attempts = sorted(glob.glob(os.path.join(RT, "runs", f"{session}-v{v}-c{c}-r{n}-a*")),
                          key=lambda d: int(d.rsplit("-a", 1)[1]))
        if not attempts:
            problems.append(f"{v} check {c} run {n}: not run at all")
            continue
        nums = [int(d.rsplit("-a", 1)[1]) for d in attempts]
        if nums != list(range(1, len(nums) + 1)):
            problems.append(f"{v} check {c} run {n}: attempts {nums} are not 1..{len(nums)}")
            continue
        bad_history = False
        for d in attempts:  # one verdict per attempt; a FAIL anywhere is never retried or overwritten
            vl = verdicts(d)
            if len(vl) != 1 or any(x.startswith("FAIL") for x in vl):
                problems.append(f"{os.path.basename(d)}: verdict lines {vl[:3]} — exactly one, and no FAIL, is required")
                bad_history = True
        for d in attempts[:-1]:
            m = json.load(open(os.path.join(d, "manifest.json")))
            if m["exit"] != 77 or not last_line(d).startswith("NOT RUN [vendor-fetch]"):
                problems.append(f"{os.path.basename(d)}: an earlier attempt ended exit {m['exit']} '{last_line(d)}' — only NOT RUN [vendor-fetch] may be retried")
                bad_history = True
            retried.append(f"{os.path.basename(d)}: {last_line(d)[:100]}")
        final = attempts[-1]
        mf = os.path.join(final, "manifest.json")
        if not os.path.exists(mf):
            problems.append(f"{os.path.basename(final)}: no manifest")
            continue
        m = json.load(open(mf))
        rid = m["run_id"]
        if rid != os.path.basename(final):
            problems.append(f"{os.path.basename(final)}: manifest run_id {rid}")
            continue
        for d in attempts:
            mm = os.path.join(d, "manifest.json")
            if not os.path.exists(mm) or json.load(open(mm)).get("owned_after") is not True:
                problems.append(f"{os.path.basename(d)}: the lab was not verified as this checkout's own after the attempt")
                bad_history = True
        if bad_history:
            continue
        if m["exit"] != 0 or not last_line(final).startswith("PASS"):
            problems.append(f"{rid}: exit {m['exit']} '{last_line(final)}' — a result needs exit 0 and a final PASS line")
            continue
        got = rows.get(rid, {})
        bad = [f"{f}={got.get(f)!r} (expected /{rx}/)" for f, rx in expected.get(c, []) if not re.fullmatch(rx, got.get(f, "") or "")]
        bad += [f"field {f} recorded more than once" for f in sorted(dups.get(rid, ()))]
        obs = jsonl(os.path.join(final, "observed.jsonl"))
        prx = jsonl(os.path.join(final, "requests.jsonl"))
        if not obs:
            bad.append("no observed requests (observed.jsonl missing or empty)")
        elif prx is None:
            bad.append("no proxy record (requests.jsonl missing)")
        else:
            o = [(x["kind"], x["realm"], x["client_id"], x["status"]) for x in obs]
            r = proxy_requests(prx)
            if o != r:
                extra = [x for x in r if x not in o]
                missing = [x for x in o if x not in r]
                bad.append(f"observed requests != proxy record ({len(o)} vs {len(r)}; "
                           f"not in proxy: {missing[:3]}; not observed: {extra[:3]})")
        if bad or bad_history:
            if bad:
                problems.append(f"{rid}: " + "; ".join(bad))
        else:
            cells[(v, c)][0] += 1
    versions = sorted({p["version"] for p in plan}, key=lambda s: [int(x) for x in s.split(".")])
    checks = sorted({p["check"] for p in plan})
    names = {os.path.basename(f)[:2]: os.path.basename(f)[3:-3] for f in glob.glob(os.path.join(ROOT, "checks", "*.sh"))}
    lines = [f"# Lab summary — session {session}", "",
             "| check | " + " | ".join(f"Keycloak {v}" for v in versions) + " |", "|---|" + "---|" * len(versions)]
    for c in checks:
        lines.append(f"| {c} {names.get(c, '')} | " + " | ".join(
            f"{cells[(v, c)][0]}/{cells[(v, c)][1]} {'PASS' if cells[(v, c)][0] == cells[(v, c)][1] else '**FAIL**'}" for v in versions) + " |")
    lines += ["", f"Attempts that ended NOT RUN [vendor-fetch] and were tried again: {len(retried)}"]
    lines += [f"- {x}" for x in retried]
    lines += ["", f"Problems: {len(problems)}"] + [f"- {x}" for x in problems]
    text = "\n".join(lines) + "\n"
    with open(os.path.join(RT, "summary.md"), "w") as f:
        f.write(text)
    print(text)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
