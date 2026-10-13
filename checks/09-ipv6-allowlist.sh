#!/usr/bin/env bash
# 09 · Why is goose still refused with lenient-cimd and an IPv4-only allowlist?
#
# goose lists an IPv4 and an IPv6 loopback redirect; the request uses the IPv4 one (premises checked on the live
# document). Three realms that differ only in the allowlist: IPv4/name hosts; + "::1"; + "[::1]". Each allowlist is
# read back before the request; each realm has a positive control (VS Code).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 77
. scripts/common.sh
KC=$KC_EXT
refresh
GURL=https://goose-docs.ai/oauth/client-metadata.json; KURL=https://vscode.dev/oauth/client-metadata.json
sub GJ fetch_or_skip $GURL; sub KJ fetch_or_skip $KURL
GRU=$(jq -r '.redirect_uris[0]' <<<"$GJ"); KRU=$(jq -r '.redirect_uris[0]' <<<"$KJ")
echo "goose redirect_uris: $(jq -c .redirect_uris <<<"$GJ")   request uses: $GRU"
[[ $GRU =~ ^https?://127\.0\.0\.1[:/] ]] || not_run "the request redirect is not the IPv4 loopback ($GRU)"
[ "$(jq -r '[.redirect_uris[]|select(test("^https?://\\[::1\\]"))]|length' <<<"$GJ")" -ge 1 ] || not_run "goose no longer lists an IPv6 loopback redirect"
IPV4=$(printf '%s\n%s\n' "$GJ" "$KJ" | uri_hosts)
[[ " $(printf '%s ' $IPV4)" == *" 127.0.0.1 "* ]] || not_run "127.0.0.1 is not in the IPv4 allowlist"
round(){ # round <label> <want> <hosts...>: sets RH, RC
  local r=lab-ipv6-$1 want=$2; shift 2
  realm_setup $r "$(json_array "$@")" lenient-cimd
  auth $r $KURL "$KRU" $C_EXT; expect "$r positive-control" accepted
  auth $r $GURL "$GRU" $C_EXT; expect "$r goose" "$want"; RH=$H; RC=$CAUSE; }
round ipv4 'cause:DOMAIN:[::1]' $IPV4;               H1=$RH; C1=$RC
round bare 'cause:DOMAIN:[::1]' $IPV4 '::1';         H2=$RH; C2=$RC
round bracketed accepted $IPV4 '[::1]';              H3=$RH; C3=$RC
echo "  IPv4/name hosts only: HTTP $H1  $C1"
echo "  + ::1                 HTTP $H2  $C2"
echo "  + [::1]               HTTP $H3  $C3"
record ipv4_status "$H1" ipv4_cause "$C1" bare_status "$H2" bare_cause "$C2" bracketed_status "$H3" bracketed_cause "$C3"
settle
echo "PASS: IPv4-only $H1 ($C1), '::1' $H2 ($C2), '[::1]' $H3 — the executor checks a redirect host the request does not use."
