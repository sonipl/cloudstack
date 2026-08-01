#!/usr/bin/env bash
# Load lab network credentials into the environment (does not print secrets).
#
# Order:
#   1) already-exported env vars (kept)
#   2) plaintext lab-network-secrets.env (gitignored) if present
#   3) decrypt lab-network-secrets.env.enc with LAB_NETWORK_SECRETS_PASSPHRASE
#
# Usage:
#   source deploy/network/load-lab-secrets.sh
#   # or
#   . ./load-lab-secrets.sh
set -euo pipefail

_LAB_NET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PLAIN="${LAB_NETWORK_SECRETS_FILE:-${_LAB_NET_DIR}/lab-network-secrets.env}"
_ENC="${LAB_NETWORK_SECRETS_ENC:-${_LAB_NET_DIR}/lab-network-secrets.env.enc}"

_load_file() {
  local f="$1"
  set -a
  # shellcheck source=/dev/null
  source "$f"
  set +a
}

if [[ -f "$_PLAIN" ]]; then
  _load_file "$_PLAIN"
elif [[ -f "$_ENC" ]]; then
  if [[ -z "${LAB_NETWORK_SECRETS_PASSPHRASE:-}" ]]; then
    echo "ERROR: set LAB_NETWORK_SECRETS_PASSPHRASE to decrypt $_ENC" >&2
    echo "  (or create gitignored $_PLAIN from lab-network-secrets.env.example)" >&2
    return 1 2>/dev/null || exit 1
  fi
  local _tmp
  _tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap 'rm -f "$_tmp"' RETURN
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
    -in "$_ENC" -out "$_tmp" -pass env:LAB_NETWORK_SECRETS_PASSPHRASE
  chmod 600 "$_tmp"
  _load_file "$_tmp"
  rm -f "$_tmp"
  trap - RETURN
else
  echo "ERROR: no secrets file. Create $_PLAIN or provide $_ENC + LAB_NETWORK_SECRETS_PASSPHRASE" >&2
  return 1 2>/dev/null || exit 1
fi

# Loaded into environment; callers validate the vars they need (do not echo values).
