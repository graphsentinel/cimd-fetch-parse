#!/usr/bin/env bash
# upstream-pr.sh: run a Keycloak release with one upstream pull request applied, next to the lab.
#   PR=51235 VERSION=26.8.0 scripts/upstream-pr.sh up     build + start  (container cimdlab-pr<PR>-<VERSION>, 127.0.0.2:18103)
#   PR=51235 VERSION=26.8.0 scripts/upstream-pr.sh down   stop and remove it (scripts/lab.sh uninstall also removes it)
# Only the PR's changes under services/src/main/java are applied, to the release tag (not the PR's base branch), and only
# keycloak-services is rebuilt, with the JDK the release was built with (17). The rebuilt jar is compared with the one in
# the pinned release image: every file must be identical except the classes of the files the PR changes, or nothing
# starts. The image is the pinned release image with that one jar replaced. Then: checks/compare-upstream-pr.sh, and
# real-clients/{realm,run}.sh with the server "pr".
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD; RT=$ROOT/lab/.runtime; . scripts/versions.env
PR=${PR:-51235}; VERSION=${VERSION:-26.8.0}; PORT=${PR_PORT:-18103}; ENGINE=${ENGINE:-podman}
NAME=cimdlab-pr$PR-$VERSION; IMG=localhost/cimdlab-keycloak-pr$PR:$VERSION; W=$RT/upstream-pr$PR-$VERSION
k="KEYCLOAK_DIGEST_${VERSION//./_}"; BASE="$KEYCLOAK_IMAGE@${!k:?no pinned digest for $VERSION}"
die(){ echo "upstream-pr: $*" >&2; exit 1; }
labeled(){ [ "$("$ENGINE" inspect --format '{{index .Config.Labels "cimdlab.root"}}' "$1" 2>/dev/null)" = "$ROOT" ]; }

down(){
  if "$ENGINE" inspect "$NAME" >/dev/null 2>&1; then labeled "$NAME" || die "$NAME was not created by this checkout — not touched"
    "$ENGINE" rm -f "$NAME" >/dev/null; fi
  f=$RT/proxy-$PORT.pid
  [ -f "$f" ] && grep -qxF "$ROOT/scripts/recording-proxy.py" <<<"$(tr '\0' '\n' < "/proc/$(cat "$f")/cmdline" 2>/dev/null)" && kill "$(cat "$f")"
  rm -f "$f"; echo "removed $NAME"; }

up(){
  [ -f "$RT/admin.env" ] || die "lab not installed: VERSIONS=$VERSION scripts/lab.sh install"
  [ -z "$(ss -ltnH "( sport = :$PORT )")" ] || "$ENGINE" inspect "$NAME" >/dev/null 2>&1 || die "port $PORT in use"
  rm -rf "$W"; mkdir -p "$W/src" "$W/m2" "$W/cmp/rel" "$W/cmp/pr"
  ( cd "$W/src" && git init -q && git remote add origin https://github.com/keycloak/keycloak.git \
      && git fetch -q --depth 1 origin tag "$VERSION" && git checkout -q "$VERSION" )
  curl -fsSL "https://patch-diff.githubusercontent.com/raw/keycloak/keycloak/pull/$PR.diff" > "$W/pr.diff"
  python3 - "$W/pr.diff" "$W/pr-main.diff" <<'EOF'
import re, sys
parts = re.split(r'(?=^diff --git )', open(sys.argv[1]).read(), flags=re.M)
open(sys.argv[2], "w").write("".join(p for p in parts if "services/src/main/java/" in p.split("\n")[0]))
EOF
  [ -s "$W/pr-main.diff" ] || die "PR #$PR changes nothing under services/src/main/java"
  ( cd "$W/src" && git apply "$W/pr-main.diff" && git diff --stat )
  "$ENGINE" run --rm -v "$W/src:/src:Z" -v "$W/m2:/root/.m2:Z" -w /src -e DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 "$MAVEN_IMAGE" \
    ./mvnw -B -q install -DskipTests -DskipExamples -DskipProtoLock=true -pl services -am > "$W/build.log" 2>&1 \
    || die "build failed (see $W/build.log)"
  local jar=org.keycloak.keycloak-services-$VERSION.jar built=$W/src/services/target/keycloak-services-$VERSION.jar
  "$ENGINE" run --rm --entrypoint /bin/cat "$BASE" "/opt/keycloak/lib/lib/main/$jar" > "$W/cmp/release.jar"
  ( cd "$W/cmp/rel" && unzip -qo ../release.jar ); ( cd "$W/cmp/pr" && unzip -qo "$built" )
  # allowed to differ: the classes compiled from the files the PR changes (their inner classes included)
  local allow; allow=$(grep -oE '^\+\+\+ b/services/src/main/java/.*\.java' "$W/pr-main.diff" | sed -E 's#^\+\+\+ b/services/src/main/java/##; s#\.java$##')
  local bad=0 f; diff -q <(cd "$W/cmp/rel" && find . -type f | sort) <(cd "$W/cmp/pr" && find . -type f | sort) >/dev/null || bad=1
  while read -r f; do cmp -s "$W/cmp/rel/$f" "$W/cmp/pr/$f" && continue
    printf '%s\n' "$allow" | grep -qxF "$(printf '%s' "$f" | sed -E 's#^\./##; s#(\$[^/]*)?\.class$##')" || { echo "unexpected difference: $f" >&2; bad=1; }
  done < <(cd "$W/cmp/rel" && find . -type f | sort)
  [ $bad = 0 ] || die "the rebuilt jar differs from the release beyond PR #$PR — not started"
  echo "rebuilt $jar: identical to the release image's except $(printf '%s\n' "$allow" | wc -l) changed source file(s)"
  cp "$built" "$W/$jar"; printf 'FROM %s\nCOPY %s /opt/keycloak/lib/lib/main/%s\n' "$BASE" "$jar" "$jar" > "$W/Containerfile"
  "$ENGINE" build -q -t "$IMG" "$W" >/dev/null
  "$ENGINE" inspect "$NAME" >/dev/null 2>&1 && down
  "$ENGINE" run -d --name "$NAME" --label cimdlab=1 --label "cimdlab.root=$ROOT" --label "cimdlab.pr=$PR" --network host \
    -e KC_HTTP_PORT="$PORT" -e KC_HTTP_HOST=127.0.0.1 --env-file "$RT/admin.env" \
    -v "$RT/tls/ca.pem:/opt/keycloak/conf/truststores/md.pem:ro,Z" "$IMG" start-dev --features=cimd >/dev/null
  RUN_LABEL_FILE=$RT/run-label setsid nohup python3 "$ROOT/scripts/recording-proxy.py" 127.0.0.2 "$PORT" 127.0.0.1 \
    "$RT/proxy/$PORT.jsonl" > "$RT/proxy-$PORT.log" 2>&1 < /dev/null & echo $! > "$RT/proxy-$PORT.pid"
  local t i; for i in $(seq 1 60); do
    t=$(curl -s --max-time 5 -X POST "http://127.0.0.2:$PORT/realms/master/protocol/openid-connect/token" --data-urlencode grant_type=password \
        --data-urlencode client_id=admin-cli --data-urlencode username=lab-admin --data-urlencode "password@$RT/admin-password" 2>/dev/null | jq -r '.access_token // empty' 2>/dev/null) || t=
    [ -n "$t" ] && break; sleep 5; done
  [ -n "$t" ] || die "$NAME not ready"
  # record the pid that actually listens (setsid may fork), so "down" and "lab.sh uninstall" find it
  local lp; lp=$(ss -ltnpH "( sport = :$PORT )" | awk -v a="127.0.0.2:$PORT" '$4==a' | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
  [ -n "$lp" ] && echo "$lp" > "$RT/proxy-$PORT.pid"
  echo "$NAME  127.0.0.2:$PORT  ready ($(curl -s "http://127.0.0.2:$PORT/admin/serverinfo" -H "@"<(printf 'Authorization: Bearer %s\n' "$t") | jq -r .systemInfo.version) + keycloak PR #$PR; jar $(sha256sum "$W/$jar" | cut -c1-12))"
}

case "${1:-}" in up) up;; down) down;; *) echo "usage: PR=<n> VERSION=<v> $0 up|down" >&2; exit 2;; esac
