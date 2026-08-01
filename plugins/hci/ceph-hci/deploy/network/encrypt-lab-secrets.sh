#!/usr/bin/env bash
# Encrypt gitignored lab-network-secrets.env → lab-network-secrets.env.enc (safe to commit).
#
#   export LAB_NETWORK_SECRETS_PASSPHRASE='…'   # strong passphrase; store in KeePass
#   ./encrypt-lab-secrets.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PLAIN="${LAB_NETWORK_SECRETS_FILE:-$DIR/lab-network-secrets.env}"
ENC="${LAB_NETWORK_SECRETS_ENC:-$DIR/lab-network-secrets.env.enc}"
[[ -f "$PLAIN" ]] || { echo "missing $PLAIN" >&2; exit 1; }
[[ -n "${LAB_NETWORK_SECRETS_PASSPHRASE:-}" ]] || {
  echo "Set LAB_NETWORK_SECRETS_PASSPHRASE (store only in KeePass / out-of-band)" >&2
  exit 1
}
umask 077
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
  -in "$PLAIN" -out "$ENC" -pass env:LAB_NETWORK_SECRETS_PASSPHRASE
chmod 644 "$ENC"
echo "Wrote $ENC (commit this encrypted file; keep passphrase out of git)"
