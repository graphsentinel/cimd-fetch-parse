#!/usr/bin/env bash
# Lab CA + server certificate for the metadata server (lab/.runtime/tls/, never committed).
# The CA passes Python 3.13+ strict verification: basicConstraints critical, keyUsage, SKI/AKI.
#   MD_HOST=<host> scripts/tls.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
D=lab/.runtime/tls
MD_HOST=${MD_HOST:?MD_HOST required}
if [ -f "$D/chain.pem" ] && [ "${1:-}" != --force ] && openssl x509 -in "$D/server.pem" -noout -checkend 86400 >/dev/null \
   && grep -q "DNS:$MD_HOST" <<<"$(openssl x509 -in "$D/server.pem" -noout -ext subjectAltName)"; then
  echo "tls: existing certificate for $MD_HOST"; exit 0; fi
mkdir -p "$D"; chmod 700 "$D"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/ca.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=v3_ca
prompt=no
[dn]
CN=cimd-fetch-parse lab CA (lab only)
[v3_ca]
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
CNF
cat > "$T/server.cnf" <<CNF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$MD_HOST
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
CNF
openssl req -x509 -new -newkey rsa:2048 -nodes -days 30 -config "$T/ca.cnf" -keyout "$D/ca.key" -out "$D/ca.pem" 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -subj "/CN=$MD_HOST" -keyout "$D/server.key" -out "$T/server.csr" 2>/dev/null
openssl x509 -req -in "$T/server.csr" -CA "$D/ca.pem" -CAkey "$D/ca.key" -CAcreateserial -days 30 \
  -extfile "$T/server.cnf" -out "$D/server.pem" 2>/dev/null
cat "$D/server.pem" "$D/ca.pem" > "$D/chain.pem"
rm -f "$D/ca.srl"; chmod 600 "$D"/*.key; chmod 644 "$D"/*.pem
openssl verify -x509_strict -CAfile "$D/ca.pem" "$D/server.pem" >/dev/null
echo "tls: generated for $MD_HOST"
