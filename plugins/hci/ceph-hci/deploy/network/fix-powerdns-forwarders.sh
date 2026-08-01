#!/usr/bin/env bash
# Fix powerdns01/02 external recursion (www.google.com hangs).
#
# Root cause (2026-07-31): hosts used default GW 10.0.10.1 which does not answer
# ARP from the prov segment, so dnsmasq forwarders 192.168.68.1 / 1.1.1.1 were
# unreachable. Authoritative vmalpha.com still worked via local pdns :5353.
#
# Fix: default GW → vyos01 10.0.10.3; keep dnsmasq split-horizon + upstreams.
#
# Usage:
#   source deploy/network/load-lab-secrets.sh   # or export PDNS_SSH_PASS
#   bash deploy/network/fix-powerdns-forwarders.sh
#   bash deploy/network/fix-powerdns-forwarders.sh --verify
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "${SCRIPT_DIR}/lab-network-target.env" ]] && . "${SCRIPT_DIR}/lab-network-target.env"
if [[ -z "${PDNS_SSH_PASS:-${SSH_PASS:-}}" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/load-lab-secrets.sh" 2>/dev/null || true
fi

PDNS01="${PDNS01_HOST:-10.0.10.21}"
PDNS02="${PDNS02_HOST:-10.0.10.22}"
GW="${PDNS_DEFAULT_GW:-10.0.10.3}"   # vyos01
SSH_USER="${PDNS_SSH_USER:-admin}"
SSH_PASS="${PDNS_SSH_PASS:-${SSH_PASS:-}}"
MODE="${1:---apply}"
[[ -n "$SSH_PASS" ]] || { echo "ERROR: PDNS_SSH_PASS not set (source load-lab-secrets.sh)" >&2; exit 1; }

remote() {
  local host="$1"
  shift
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o ConnectTimeout=10 "${SSH_USER}@${host}" "$@"
}

apply_one() {
  local host="$1"
  echo "=== apply $host (GW=$GW) ==="
  remote "$host" "bash -s" <<REMOTE
set -euo pipefail
PASS='${SSH_PASS}'
sudo_run() { echo "\$PASS" | sudo -S bash -c "\$*"; }
CONN=\$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '\$2=="ens192"{print \$1; exit}')
[[ -n "\$CONN" ]] || { echo "no active ens192 connection" >&2; exit 1; }
sudo_run "nmcli connection modify \"\$CONN\" ipv4.gateway ${GW} ipv4.method manual"
sudo_run "nmcli connection up \"\$CONN\""
sleep 1
ip -4 route | head -5
ping -c1 -W2 1.1.1.1 >/dev/null
CONF=/etc/dnsmasq.d/vmalpha-split.conf
if [[ -f "\$CONF" ]]; then
  sudo_run "sed -i -E '/^server=(192\\\\.168\\\\.68\\\\.1|1\\\\.1\\\\.1\\\\.1|8\\\\.8\\\\.8\\\\.8)\$/d' \$CONF"
  sudo_run "printf '%s\\\\n' 'server=1.1.1.1' 'server=8.8.8.8' 'server=192.168.68.1' >> \$CONF"
  sudo_run "systemctl restart dnsmasq"
fi
systemctl is-active dnsmasq pdns
dig +time=3 +tries=1 @127.0.0.1 www.google.com A +short | head -3
dig +time=3 +tries=1 @${host} ac01.vmalpha.com A +short | head -1
REMOTE
}

verify_one() {
  local host="$1"
  echo "=== verify @$host ==="
  dig +time=3 +tries=1 @"$host" www.google.com A +short | head -3
  dig +time=3 +tries=1 @"$host" ac01.vmalpha.com A +short | head -1
}

command -v sshpass >/dev/null || { echo "sshpass required" >&2; exit 1; }
command -v dig >/dev/null || { echo "dig required" >&2; exit 1; }

case "$MODE" in
  --apply)
    apply_one "$PDNS01"
    apply_one "$PDNS02"
    verify_one "$PDNS01"
    verify_one "$PDNS02"
    ;;
  --verify)
    verify_one "$PDNS01"
    verify_one "$PDNS02"
    ;;
  -h|--help)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 2
    ;;
esac
echo "DONE"
