#!/usr/bin/env bash
# Configure TP-Link TL-SG108E lab switches (SW01/SW02) for 802.1Q VLAN layout (target design).
#
# Run from Foreman (or any host on mgmt LAN) with HTTP access to switch IPs:
#   bash deploy/network/setup-tplink-lab-vlans.sh --dry-run
#   bash deploy/network/setup-tplink-lab-vlans.sh --apply
#   bash deploy/network/setup-tplink-lab-vlans.sh --verify
#   bash deploy/network/setup-tplink-lab-vlans.sh --apply-ports-678  # 6->7->8 per switch
#   bash deploy/network/setup-tplink-lab-vlans.sh --apply-safe  # trunk 2-5 only; no VLAN1 strip
#   bash deploy/network/setup-tplink-lab-vlans.sh --apply-pve01-pve02  # port1 VLAN9 + trunk 2-5
#   bash deploy/network/setup-tplink-lab-vlans.sh --apply-trunk-2-5  # trunk V1+V10-30 on 2-5; preserve 1,6-8
#   bash deploy/network/setup-tplink-lab-vlans.sh --apply-table1  # Desktop/SW01-SW02-Ports.xlsx Table 1
#   bash deploy/network/setup-tplink-lab-vlans.sh --dump-ports  # full port table (both switches)
#
# Defaults: deploy/network/lab-network-target.env (SW01/SW02 on 192.168.71.11/12)
#
# Table 1 (SW01-SW02-Ports.xlsx) — VLAN layout identical on both switches:
# | Port | Mode                                   | SW01                      | SW02                      |
# |------|----------------------------------------|---------------------------|---------------------------|
# |  1   | Hybrid U1 + T10–30, PVID 1             | Oelbm01-nic2              | Foreman-nic2              |
# |  2   | Hybrid U1 + T10–30, PVID 1             | Pve03-nic1-pub-trunk      | Pve03-nic2-pub-trunk      |
# |  3   | Hybrid U1 + T10–30, PVID 1             | Pve04-nic1-pub-trunk      | Pve04-nic2-pub-trunk      |
# |  4   | Hybrid U1 + T10–30, PVID 1             | Pve05-nic1-pub-trunk      | Pve05-nic2-pub-trunk      |
# |  5   | Access VLAN 1500, PVID 1500            | Pve03-nic3-ptv-access     | Pve03-nic4-ptv-access     |
# |  6   | Access VLAN 1500, PVID 1500            | Pve04-nic3-ptv-access     | Pve04-nic4-ptv-access     |
# |  7   | Access VLAN 1500, PVID 1500            | Pve05-nic3-ptv-access     | Pve05-nic4-ptv-access     |
# |  8   | Access VLAN 1, PVID 1 (uplink / home) | Uplink / home             | Uplink / home             |
#
# NOTE: TL-SG108E has 8 ports. Keep port 8 on VLAN1 or switch mgmt is stranded.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "${SCRIPT_DIR}/lab-network-target.env" ]] && . "${SCRIPT_DIR}/lab-network-target.env"

SW01="${SW01:-${SW01_MGMT_IP:-192.168.71.11}}"
SW02="${SW02:-${SW02_MGMT_IP:-192.168.71.12}}"
SW_USER="${SW_USER:-admin}"
SW_PASS="${SW_PASS:-Jatin76monu}"
MODE="${1:---dry-run}"


usage() {
  sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Usage: $0 [--dry-run|--apply|--apply-safe|--apply-pve01-pve02|--apply-trunk-2-5|--apply-table1|--apply-ports-678|--apply-port8-only|--verify|--dump-ports]"
}

require_python3() {
  command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }
}

run_python() {
  SW01="$SW01" SW02="$SW02" SW_USER="$SW_USER" SW_PASS="$SW_PASS" MODE="$MODE" \
    python3 <<'PY'
import http.client, os, re, sys, time, urllib.parse

_sw_list = os.environ.get("SWITCHES_LIST", "").strip()
SWITCHES = [x for x in _sw_list.split() if x] if _sw_list else [os.environ["SW01"], os.environ["SW02"]]
USER = os.environ["SW_USER"]
PASS = os.environ["SW_PASS"]
MODE = os.environ["MODE"]

ACCESS, TAG, NOTMBR = 0, 1, 2
PORT_BITS = {1: 1, 2: 2, 3: 4, 4: 8, 5: 16, 6: 32, 7: 64, 8: 128}
HOST_TRUNK_PORTS = {2, 3, 4, 5}  # trunk tag V1+V10–30, PVID 10
PORT_ACCESS_V9 = {1, 6, 7, 8}    # port 1 = pve01 home internet
PRESERVE_PORTS = {6, 7, 8}       # unchanged during trunk apply
TRUNK_PVID_PBM = 30              # ports 2+3+4+5

VLAN1 = {p: NOTMBR for p in range(1, 9)}
VLAN_TRUNK = {p: (TAG if p in HOST_TRUNK_PORTS else NOTMBR) for p in range(1, 9)}
VLAN9 = {p: NOTMBR for p in range(1, 9)}
for _p in PORT_ACCESS_V9:
    VLAN9[_p] = ACCESS
VLAN1_TRUNK = {p: NOTMBR for p in range(1, 9)}
for _p in HOST_TRUNK_PORTS:
    VLAN1_TRUNK[_p] = TAG
VLAN10_ACCESS = {p: NOTMBR for p in range(1, 9)}
for _p in HOST_TRUNK_PORTS:
    VLAN10_ACCESS[_p] = TAG
VLAN25_CLEANUP = {p: NOTMBR for p in range(1, 9)}
VLAN_QUERIES = []
VLAN_QUERIES.append((10, "VLAN10", VLAN10_ACCESS))
for v in range(11, 31):
    VLAN_QUERIES.append((v, "VLAN%d" % v, VLAN_TRUNK))


PORT_LABELS = {
    1: "pub-trunk (oelbm01/foreman)",
    2: "pve03-pub-trunk",
    3: "pve04-pub-trunk",
    4: "pve05-pub-trunk",
    5: "pve03-ptv-access",
    6: "pve04-ptv-access",
    7: "pve05-ptv-access",
    8: "uplink-home",
}


def seltypes(port_map):
    return "&".join("selType_%d=%d" % (p, port_map.get(p, NOTMBR)) for p in range(1, 9))


def build_query(vid, vname, port_map):
    return "vid=%d&vname=%s&%s&qvlan_add=Add%%2FModify" % (
        vid, urllib.parse.quote(vname), seltypes(port_map))


def login_conn(ip, timeout=45):
    ua = "Mozilla/5.0"
    c = http.client.HTTPConnection(ip, timeout=timeout)
    c.request("GET", "/", headers={"User-Agent": ua})
    c.getresponse().read()
    body = urllib.parse.urlencode({"username": USER, "password": PASS, "logon": "Login"})
    c.request("POST", "/logon.cgi", body=body, headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "Referer": "http://%s/" % ip, "User-Agent": ua})
    c.getresponse().read()
    return c, ua


def qvlan_enabled(html):
    m = re.search(r"state:(\d+)", html)
    return m and int(m.group(1)) == 1


def enable_8021q_vlan(ip):
    c, ua = login_conn(ip)
    c.request("GET", "/qvlanSet.cgi?qvlan_en=1&qvlan_mode=Apply",
              headers={"Referer": "http://%s/Vlan8021QRpm.htm" % ip, "User-Agent": ua})
    c.getresponse().read()
    c.close()
    time.sleep(3)


def read_vlan_state(ip):
    c, ua = login_conn(ip)
    c.request("GET", "/Vlan8021QRpm.htm",
              headers={"Referer": "http://%s/" % ip, "User-Agent": ua})
    q = c.getresponse().read().decode("utf-8", "replace")
    c.request("GET", "/Vlan8021QPvidRpm.htm",
              headers={"Referer": "http://%s/" % ip, "User-Agent": ua})
    p = c.getresponse().read().decode("utf-8", "replace")
    c.close()
    block = re.search(r"var qvlan_ds = (\{[\s\S]*?\n\});", q).group(1)

    def grab(key):
        m = re.search(r"%s:\[\s*([\s\S]*?)\s*\]" % key, block)
        raw = m.group(1).replace("\n", "").strip()
        if not raw:
            return []
        return [int(x.strip(), 0) for x in raw.split(",") if x.strip()]

    vids, u, t = grab("vids"), grab("untagMbrs"), grab("tagMbrs")
    pvids = [int(x) for x in re.search(r"pvids:\[\s*([\d,\s]+)\]", p).group(1).split(",")]
    return vids, u, t, pvids


def read_link_state(ip):
    c, ua = login_conn(ip)
    c.request("GET", "/PortSettingRpm.htm",
              headers={"Referer": "http://%s/" % ip, "User-Agent": ua})
    html = c.getresponse().read().decode("utf-8", "replace")
    c.close()
    m = re.search(r"state:\[([\d,\s]+)\]", html)
    if not m:
        return {}
    states = [int(x.strip()) for x in m.group(1).split(",")[:8]]
    return {p + 1: ("up" if states[p] else "down") for p in range(len(states))}


def port_membership(mask):
    return [p for p, b in PORT_BITS.items() if mask & b]


def vlan_index(vids, vid):
    try:
        return vids.index(vid)
    except ValueError:
        return None


def summarize(vids, u, t, pvids):
    i1 = vlan_index(vids, 1)
    i9 = vlan_index(vids, 9)
    i10 = vlan_index(vids, 10)
    i25 = vlan_index(vids, 25)
    tag10_30 = set()
    for vid in range(10, 31):
        idx = vlan_index(vids, vid)
        if idx is not None:
            tag10_30 |= set(port_membership(t[idx]))
    i9t = vlan_index(vids, 9)
    return {
        "pvid": {p + 1: pvids[p] for p in range(8)},
        "v1_untag": port_membership(u[i1]) if i1 is not None else [],
        "v1_tag": port_membership(t[i1]) if i1 is not None else [],
        "v9_untag": port_membership(u[i9]) if i9 is not None else [],
        "v9_tag": port_membership(t[i9]) if i9 is not None else [],
        "v10_tag": port_membership(t[i10]) if i10 is not None else [],
        "v10_untag": port_membership(u[i10]) if i10 is not None else [],
        "v25_untag": port_membership(u[i25]) if i25 is not None else [],
        "tag10_30": sorted(tag10_30),
        "tag10_20": sorted(tag10_30),
        "vids": list(vids),
    }


def port_mode(state, port):
    pvid = state["pvid"].get(port)
    if port in HOST_TRUNK_PORTS:
        v1 = port in state.get("v1_tag", [])
        v10 = port in state.get("tag10_30", [])
        if v1 and v10 and pvid == 10:
            return "trunk tag V1+V10-30 PVID10"
        if v10 and pvid == 10:
            return "trunk tag V10-30 PVID10"
        return "trunk (check membership/PVID)"
    if port in PORT_ACCESS_V9:
        if port in state.get("v9_untag", []) and pvid == 9:
            return "access VLAN9 PVID9"
        if port in state.get("v1_untag", []) and pvid == 1:
            return "access VLAN1 PVID1"
        return "access (check)"
    return "?"


def print_port_table(state, links, title):
    print(title)
    print("%-4s %-14s %-22s %s" % ("Port", "Link", "Role", "Mode"))
    print("-" * 60)
    for p in range(1, 9):
        link = links.get(p, "?")
        print("%-4d %-14s %-22s %s" % (p, link, PORT_LABELS[p], port_mode(state, p)))


def port_vlan_membership(vids, u, t, port):
    bit = PORT_BITS[port]
    tagged, untagged = [], []
    for i, vid in enumerate(vids):
        if u[i] & bit:
            untagged.append(vid)
        elif t[i] & bit:
            tagged.append(vid)
    return sorted(tagged), sorted(untagged)


def infer_port_mode_detailed(pvid, tagged, untagged):
    if untagged:
        return "access"
    if tagged:
        return "trunk"
    return "none"


def print_detailed_port_table(vids, u, t, pvids, links, title):
    print(title)
    hdr = "%-4s %-6s %-8s %-6s %-28s %s" % (
        "Port", "Link", "Mode", "PVID", "Tagged VLANs", "Untagged VLANs")
    print(hdr)
    print("-" * len(hdr))
    for p in range(1, 9):
        tagged, untagged = port_vlan_membership(vids, u, t, p)
        pvid = pvids[p - 1] if p - 1 < len(pvids) else "?"
        link = links.get(p, "?")
        mode = infer_port_mode_detailed(pvid, tagged, untagged)
        print("%-4d %-6s %-8s %-6s %-28s %s" % (
            p, link, mode, pvid,
            ",".join(str(v) for v in tagged) or "-",
            ",".join(str(v) for v in untagged) or "-",
        ))


def verify_trunk_host(state):
    ok = True
    reasons = []
    for p in HOST_TRUNK_PORTS:
        if state["pvid"].get(p) != 10:
            ok = False
            reasons.append("PVID port %d want 10 got %s" % (p, state["pvid"].get(p)))
    if set(state.get("v1_tag", [])) != set(HOST_TRUNK_PORTS):
        ok = False
        reasons.append("VLAN1 tag want %s got %s" % (sorted(HOST_TRUNK_PORTS), state.get("v1_tag", [])))
    if set(state["tag10_30"]) != set(HOST_TRUNK_PORTS):
        ok = False
        reasons.append("V10-30 tag want %s got %s" % (sorted(HOST_TRUNK_PORTS), state["tag10_30"]))
    if set(state.get("v9_tag", [])) & set(HOST_TRUNK_PORTS):
        ok = False
        reasons.append("VLAN9 must not tag trunk ports; got tag on %s" % sorted(set(state.get("v9_tag", [])) & set(HOST_TRUNK_PORTS)))
    if set(state.get("v10_untag", [])) & set(HOST_TRUNK_PORTS):
        ok = False
        reasons.append("VLAN10 untag on trunk ports: %s" % state.get("v10_untag"))
    if set(state.get("v1_untag", [])) & set(HOST_TRUNK_PORTS):
        ok = False
        reasons.append("VLAN1 untag on trunk ports: %s" % state.get("v1_untag"))
    for vid in range(10, 31):
        if vlan_index(state["vids"], vid) is None:
            ok = False
            reasons.append("VLAN %d missing" % vid)
            break
    return ok, reasons


def verify_target(state):
    ok = True
    reasons = []
    if state["pvid"].get(1) != 9:
        ok = False
        reasons.append("PVID port 1 want 9 got %s" % state["pvid"].get(1))
    if 1 not in state.get("v9_untag", []):
        ok = False
        reasons.append("VLAN9 untag want port 1; got %s" % state.get("v9_untag"))
    if 1 in state.get("v1_tag", []) or 1 in state.get("tag10_30", []):
        ok = False
        reasons.append("port 1 must not be trunk; v1_tag=%s tag10_30=%s" % (
            1 in state.get("v1_tag", []), 1 in state.get("tag10_30", [])))
    for p in HOST_TRUNK_PORTS:
        if state["pvid"].get(p) != 10:
            ok = False
            reasons.append("PVID port %d want 10 got %s" % (p, state["pvid"].get(p)))
    if state["pvid"].get(7) != 9:
        ok = False
        reasons.append("PVID port 7 want 9 got %s" % state["pvid"].get(7))
    if state["pvid"].get(8) != 9:
        ok = False
        reasons.append("PVID port 8 want 9 got %s" % state["pvid"].get(8))
    if set(state["tag10_30"]) != set(HOST_TRUNK_PORTS):
        ok = False
        reasons.append("V10-30 tag want %s got %s" % (sorted(HOST_TRUNK_PORTS), state["tag10_30"]))
    if set(state.get("v9_tag", [])) & set(HOST_TRUNK_PORTS):
        ok = False
        reasons.append("VLAN9 must not tag trunk ports; tagged on %s" % sorted(set(state.get("v9_tag", [])) & set(HOST_TRUNK_PORTS)))
    if set(state.get("v9_untag", [])) != PORT_ACCESS_V9:
        ok = False
        reasons.append("VLAN9 untag want %s got %s" % (sorted(PORT_ACCESS_V9), state.get("v9_untag")))
    if set(state.get("v10_untag", [])):
        ok = False
        reasons.append("VLAN10 untag want [] got %s" % state.get("v10_untag"))
    if set(state.get("v1_tag", [])) != set(HOST_TRUNK_PORTS):
        ok = False
        reasons.append("VLAN1 tag want %s got %s" % (sorted(HOST_TRUNK_PORTS), state.get("v1_tag", [])))
    if set(state.get("v1_untag", [])):
        ok = False
        reasons.append("VLAN1 untag want [] got %s" % state.get("v1_untag"))
    if state["pvid"].get(6) != 9:
        ok = False
        reasons.append("PVID port 6 want 9 got %s" % state["pvid"].get(6))
    if state.get("v25_untag"):
        ok = False
        reasons.append("VLAN25 should be removed; still untagged on %s" % state.get("v25_untag"))
    if vlan_index(state["vids"], 9) is None:
        ok = False
        reasons.append("VLAN 9 missing from switch VLAN table")
    for vid in range(10, 31):
        if vlan_index(state["vids"], vid) is None:
            ok = False
            reasons.append("VLAN %d missing" % vid)
            break
    return ok, reasons


def apply_qvlan(ip, vid, vname, port_map):
    for attempt in range(3):
        try:
            c, ua = login_conn(ip)
            q = build_query(vid, vname, port_map)
            c.request("GET", "/qvlanSet.cgi?" + q,
                      headers={"Referer": "http://%s/Vlan8021QRpm.htm" % ip, "User-Agent": ua})
            resp = c.getresponse()
            body = resp.read()
            if resp.status != 200:
                raise OSError("qvlanSet vid %s HTTP %s" % (vid, resp.status))
            c.close()
            time.sleep(0.75)
            return
        except (TimeoutError, OSError) as exc:
            if attempt == 2:
                raise
            time.sleep(3)


def apply_pvid(ip, pbm, pvid):
    for attempt in range(3):
        try:
            c, ua = login_conn(ip)
            c.request("GET", "/vlanPvidSet.cgi?pbm=%d&pvid=%d" % (pbm, pvid),
                      headers={"Referer": "http://%s/Vlan8021QPvidRpm.htm" % ip, "User-Agent": ua})
            c.getresponse().read()
            c.close()
            time.sleep(0.5)
            return
        except (TimeoutError, OSError) as exc:
            if attempt == 2:
                raise
            time.sleep(2)


def port_map_preserve_non_host(desired, vids, untag, tag, vid):
    """Keep ports 6-8 VLAN membership unchanged (apply-safe); port 1 follows desired."""
    idx = vlan_index(vids, vid)
    port_map = {}
    for p in range(1, 9):
        if p in HOST_TRUNK_PORTS:
            port_map[p] = desired.get(p, NOTMBR)
            continue
        if p not in PRESERVE_PORTS:
            port_map[p] = desired.get(p, NOTMBR)
            continue
        if idx is None:
            port_map[p] = desired.get(p, NOTMBR)
            continue
        bit = PORT_BITS[p]
        if untag[idx] & bit:
            port_map[p] = ACCESS
        elif tag[idx] & bit:
            port_map[p] = TAG
        else:
            port_map[p] = NOTMBR
    return port_map


def vlan1_strip_host_ports():
    """Remove VLAN1 untagged membership from all ports (6–8 use VLAN9 access)."""
    return {p: NOTMBR for p in range(1, 9)}


def switch_reachable(ip):
    try:
        c, ua = login_conn(ip)
        c.close()
        return True
    except Exception:
        return False



PORT_PBM = {1: 1, 2: 2, 3: 4, 4: 8, 5: 16, 6: 32, 7: 64, 8: 128}


def vlan_map_from_state(vids, untag, tag, vid):
    idx = vlan_index(vids, vid)
    port_map = {p: NOTMBR for p in range(1, 9)}
    if idx is None:
        return port_map
    for p in range(1, 9):
        bit = PORT_BITS[p]
        if untag[idx] & bit:
            port_map[p] = ACCESS
        elif tag[idx] & bit:
            port_map[p] = TAG
    return port_map


def qvlan_set_on_conn(c, ua, ip, vid, vname, port_map):
    q = build_query(vid, vname, port_map)
    c.request("GET", "/qvlanSet.cgi?" + q,
              headers={"Referer": "http://%s/Vlan8021QRpm.htm" % ip, "User-Agent": ua})
    resp = c.getresponse()
    resp.read()
    if resp.status != 200:
        raise OSError("qvlanSet vid %s HTTP %s" % (vid, resp.status))


def pvid_set_on_conn(c, ua, ip, pbm, pvid):
    c.request("GET", "/vlanPvidSet.cgi?pbm=%d&pvid=%d" % (pbm, pvid),
              headers={"Referer": "http://%s/Vlan8021QPvidRpm.htm" % ip, "User-Agent": ua})
    c.getresponse().read()


def apply_port1_home_trunk(ip, port=1):
    """Port 1: untagged VLAN9 (home/internet) + tagged V1+V10-30 (all lab VLANs), PVID 9."""
    print("  Step: port %d -> untagged VLAN9 + trunk tag V1+V10-30 PVID9" % port)
    for attempt in range(3):
        try:
            vids, u, t, pvids = read_vlan_state(ip)
            vnames = {1: "Default", 9: "VLAN9"}
            c, ua = login_conn(ip, timeout=60)
            # VLAN9 untagged on port 1
            v9 = vlan_map_from_state(vids, u, t, 9)
            v9[port] = ACCESS
            qvlan_set_on_conn(c, ua, ip, 9, "VLAN9", v9)
            time.sleep(0.4)
            # VLAN1 tagged on port 1
            v1 = vlan_map_from_state(vids, u, t, 1)
            v1[port] = TAG
            qvlan_set_on_conn(c, ua, ip, 1, "Default", v1)
            time.sleep(0.4)
            # VLAN10-30 tagged on port 1
            for vid in range(10, 31):
                idx = vlan_index(vids, vid)
                if idx is None:
                    continue
                pm = vlan_map_from_state(vids, u, t, vid)
                pm[port] = TAG
                qvlan_set_on_conn(c, ua, ip, vid, vnames.get(vid, "VLAN%d" % vid), pm)
                time.sleep(0.25)
            pvid_set_on_conn(c, ua, ip, PORT_PBM[port], 9)
            c.close()
            time.sleep(0.75)
            break
        except (TimeoutError, OSError):
            try:
                c.close()
            except Exception:
                pass
            if attempt == 2:
                raise
            time.sleep(5)
    vids, u, t, pvids = read_vlan_state(ip)
    tagged, untagged = port_vlan_membership(vids, u, t, port)
    print("    port %d now: PVID=%s untag=%s tag=%s" % (
        port, pvids[port - 1], untagged, tagged))


PORTS_345 = {3, 4, 5}
PORT345_PVID_PBM = 28  # ports 3+4+5


def apply_port_trunk_v9_30(ip, port):
    """Trunk port: untagged VLAN9 (home/internet) + tagged VLAN10-30, PVID 9; no VLAN1."""
    print("  Step: port %d -> untagged V9 + trunk tag V10-30 PVID9" % port)
    for attempt in range(3):
        try:
            vids, u, t, pvids = read_vlan_state(ip)
            vnames = {1: "Default", 9: "VLAN9"}
            c, ua = login_conn(ip, timeout=90)
            # VLAN1 off this port
            v1 = vlan_map_from_state(vids, u, t, 1)
            if v1.get(port) != NOTMBR:
                v1[port] = NOTMBR
                qvlan_set_on_conn(c, ua, ip, 1, "Default", v1)
                time.sleep(0.35)
            # VLAN9 untagged
            v9 = vlan_map_from_state(vids, u, t, 9)
            v9[port] = ACCESS
            qvlan_set_on_conn(c, ua, ip, 9, "VLAN9", v9)
            time.sleep(0.35)
            # VLAN10-30 tagged
            for vid in range(10, 31):
                idx = vlan_index(vids, vid)
                if idx is None:
                    continue
                pm = vlan_map_from_state(vids, u, t, vid)
                pm[port] = TAG
                qvlan_set_on_conn(c, ua, ip, vid, vnames.get(vid, "VLAN%d" % vid), pm)
                time.sleep(0.2)
            pvid_set_on_conn(c, ua, ip, PORT_PBM[port], 9)
            c.close()
            time.sleep(0.75)
            break
        except (TimeoutError, OSError):
            try:
                c.close()
            except Exception:
                pass
            if attempt == 2:
                raise
            time.sleep(5)
    vids, u, t, pvids = read_vlan_state(ip)
    tagged, untagged = port_vlan_membership(vids, u, t, port)
    print("    port %d now: PVID=%s untag=%s tag=%s" % (
        port, pvids[port - 1], untagged or "-", tagged))


def apply_ports_345_trunk_v9_30(ip):
    for port in sorted(PORTS_345):
        apply_port_trunk_v9_30(ip, port)


def verify_ports_345_v9_30(vids, u, t, pvids):
    ok = True
    reasons = []
    for port in PORTS_345:
        tagged, untagged = port_vlan_membership(vids, u, t, port)
        pvid = pvids[port - 1] if port - 1 < len(pvids) else None
        if pvid != 9:
            ok = False
            reasons.append("port %d PVID want 9 got %s" % (port, pvid))
        if untagged != [9]:
            ok = False
            reasons.append("port %d untag want [9] got %s" % (port, untagged))
        if 1 in tagged:
            ok = False
            reasons.append("port %d must not tag VLAN1" % port)
        for vid in range(10, 31):
            if vid not in tagged:
                ok = False
                reasons.append("port %d missing tagged VLAN %d" % (port, vid))
                break
    return ok, reasons


PRIVATE_VLAN_ID = 1500
PORTS_678 = {6, 7, 8}
PORTS_678_PBM = 224  # 32+64+128
TABLE1_TRUNK_PORTS = {1, 2, 3, 4}
TABLE1_PRIV_PORTS = {5, 6, 7}
TABLE1_UPLINK_PORT = 8
TABLE1_TRUNK_PBM = 15  # ports 1+2+3+4
TABLE1_PRIV_PBM = 112  # ports 5+6+7


def apply_table1_layout(ip):
    """Table 1: ports 1-4 hybrid U1+T10-30 PVID1; 5-7 access V1500; 8 access V1."""
    print("Applying Table 1 layout (trunk 1-4 U1+T10-30; access 5-7 V%d; port8 U1)..." % PRIVATE_VLAN_ID)
    c0, ua0 = login_conn(ip)
    c0.request("GET", "/Vlan8021QRpm.htm",
               headers={"Referer": "http://%s/" % ip, "User-Agent": ua0})
    qhtml = c0.getresponse().read().decode("utf-8", "replace")
    c0.close()
    if not qvlan_enabled(qhtml):
        print("Enabling 802.1Q VLAN mode (was disabled)...")
        enable_8021q_vlan(ip)

    for attempt in range(3):
        try:
            vids, u, t, pvids = read_vlan_state(ip)
            vnames = {1: "Default", 9: "VLAN9", PRIVATE_VLAN_ID: "VLAN1500"}
            for vid in range(10, 31):
                vnames[vid] = "VLAN%d" % vid
            c, ua = login_conn(ip, timeout=90)

            # Ensure VLAN10-30 exist (create missing with empty members first)
            for vid in range(10, 31):
                if vlan_index(vids, vid) is None:
                    empty = {p: NOTMBR for p in range(1, 9)}
                    qvlan_set_on_conn(c, ua, ip, vid, vnames[vid], empty)
                    time.sleep(0.25)
            if vlan_index(vids, PRIVATE_VLAN_ID) is None:
                empty = {p: NOTMBR for p in range(1, 9)}
                qvlan_set_on_conn(c, ua, ip, PRIVATE_VLAN_ID, "VLAN1500", empty)
                time.sleep(0.3)

            # Refresh after creates
            c.close()
            vids, u, t, pvids = read_vlan_state(ip)
            c, ua = login_conn(ip, timeout=90)

            # VLAN1: untagged on trunk 1-4 + uplink 8; not member on private 5-7
            v1 = {p: NOTMBR for p in range(1, 9)}
            for p in TABLE1_TRUNK_PORTS:
                v1[p] = ACCESS
            v1[TABLE1_UPLINK_PORT] = ACCESS
            qvlan_set_on_conn(c, ua, ip, 1, "Default", v1)
            time.sleep(0.5)

            # Clear VLAN9 membership everywhere (unused in Table 1)
            if vlan_index(vids, 9) is not None:
                v9 = {p: NOTMBR for p in range(1, 9)}
                qvlan_set_on_conn(c, ua, ip, 9, "VLAN9", v9)
                time.sleep(0.3)

            # VLAN10-30: tagged only on ports 1-4
            for vid in range(10, 31):
                pm = {p: (TAG if p in TABLE1_TRUNK_PORTS else NOTMBR) for p in range(1, 9)}
                qvlan_set_on_conn(c, ua, ip, vid, vnames[vid], pm)
                time.sleep(0.25)

            # Strip any other VLANs from private/uplink ports, then set VLAN1500 access 5-7
            bit_priv = sum(PORT_BITS[p] for p in TABLE1_PRIV_PORTS)
            bit_up = PORT_BITS[TABLE1_UPLINK_PORT]
            for i, vid in enumerate(vids):
                if vid in (1, PRIVATE_VLAN_ID) or 10 <= vid <= 30:
                    continue
                if not ((u[i] | t[i]) & (bit_priv | bit_up)):
                    continue
                pm = vlan_map_from_state(vids, u, t, vid)
                for p in TABLE1_PRIV_PORTS | {TABLE1_UPLINK_PORT}:
                    pm[p] = NOTMBR
                qvlan_set_on_conn(c, ua, ip, vid, vnames.get(vid, "VLAN%d" % vid), pm)
                time.sleep(0.25)

            v1500 = {p: (ACCESS if p in TABLE1_PRIV_PORTS else NOTMBR) for p in range(1, 9)}
            qvlan_set_on_conn(c, ua, ip, PRIVATE_VLAN_ID, "VLAN1500", v1500)
            time.sleep(0.4)

            # Re-assert VLAN1 after 1500 (TL-SG108E sometimes re-adds Default)
            v1 = {p: NOTMBR for p in range(1, 9)}
            for p in TABLE1_TRUNK_PORTS:
                v1[p] = ACCESS
            v1[TABLE1_UPLINK_PORT] = ACCESS
            qvlan_set_on_conn(c, ua, ip, 1, "Default", v1)
            time.sleep(0.4)
            v1500 = {p: (ACCESS if p in TABLE1_PRIV_PORTS else NOTMBR) for p in range(1, 9)}
            qvlan_set_on_conn(c, ua, ip, PRIVATE_VLAN_ID, "VLAN1500", v1500)
            time.sleep(0.4)

            # PVIDs: 1 on 1-4+8, 1500 on 5-7
            pvid_set_on_conn(c, ua, ip, TABLE1_TRUNK_PBM, 1)
            time.sleep(0.3)
            pvid_set_on_conn(c, ua, ip, PORT_PBM[TABLE1_UPLINK_PORT], 1)
            time.sleep(0.3)
            for p in sorted(TABLE1_PRIV_PORTS):
                pvid_set_on_conn(c, ua, ip, PORT_PBM[p], PRIVATE_VLAN_ID)
                time.sleep(0.25)
            c.close()
            time.sleep(0.75)
            break
        except (TimeoutError, OSError):
            try:
                c.close()
            except Exception:
                pass
            if attempt == 2:
                raise
            time.sleep(5)

    print("  Post-apply reachability:", "OK" if switch_reachable(ip) else "LOST at %s" % ip)


def verify_table1_layout(vids, u, t, pvids):
    ok = True
    reasons = []
    if vlan_index(vids, PRIVATE_VLAN_ID) is None:
        ok = False
        reasons.append("VLAN %d missing" % PRIVATE_VLAN_ID)
    for port in sorted(TABLE1_TRUNK_PORTS):
        tagged, untagged = port_vlan_membership(vids, u, t, port)
        pvid = pvids[port - 1] if port - 1 < len(pvids) else None
        if pvid != 1:
            ok = False
            reasons.append("port %d PVID want 1 got %s" % (port, pvid))
        if untagged != [1]:
            ok = False
            reasons.append("port %d untag want [1] got %s" % (port, untagged))
        for vid in range(10, 31):
            if vid not in tagged:
                ok = False
                reasons.append("port %d missing tagged VLAN %d" % (port, vid))
                break
        if PRIVATE_VLAN_ID in tagged or PRIVATE_VLAN_ID in untagged:
            ok = False
            reasons.append("port %d must not be in VLAN %d" % (port, PRIVATE_VLAN_ID))
    for port in sorted(TABLE1_PRIV_PORTS):
        tagged, untagged = port_vlan_membership(vids, u, t, port)
        pvid = pvids[port - 1] if port - 1 < len(pvids) else None
        if pvid != PRIVATE_VLAN_ID:
            ok = False
            reasons.append("port %d PVID want %d got %s" % (port, PRIVATE_VLAN_ID, pvid))
        if untagged != [PRIVATE_VLAN_ID]:
            ok = False
            reasons.append("port %d untag want [%d] got %s" % (port, PRIVATE_VLAN_ID, untagged))
        if tagged:
            ok = False
            reasons.append("port %d has tagged VLANs: %s" % (port, tagged))
    port = TABLE1_UPLINK_PORT
    tagged, untagged = port_vlan_membership(vids, u, t, port)
    pvid = pvids[port - 1] if port - 1 < len(pvids) else None
    if pvid != 1:
        ok = False
        reasons.append("port %d PVID want 1 got %s" % (port, pvid))
    if untagged != [1]:
        ok = False
        reasons.append("port %d untag want [1] got %s" % (port, untagged))
    if tagged:
        ok = False
        reasons.append("port %d has tagged VLANs: %s" % (port, tagged))
    return ok, reasons


def apply_ports_678_vlan1500(ip):
    """Strip VLANs from ports 6-8; access untagged VLAN1500 only, PVID 1500."""
    print("Applying ports 6-8 -> private VLAN %d (strip all other VLANs)..." % PRIVATE_VLAN_ID)
    for attempt in range(3):
        try:
            vids, u, t, pvids = read_vlan_state(ip)
            vnames = {1: "Default", 9: "VLAN9", PRIVATE_VLAN_ID: "VLAN1500"}
            c, ua = login_conn(ip, timeout=90)
            bit678 = sum(PORT_BITS[p] for p in PORTS_678)
            for i, vid in enumerate(vids):
                if not ((u[i] & bit678) or (t[i] & bit678)):
                    continue
                pm = vlan_map_from_state(vids, u, t, vid)
                for p in PORTS_678:
                    pm[p] = NOTMBR
                qvlan_set_on_conn(c, ua, ip, vid, vnames.get(vid, "VLAN%d" % vid), pm)
                time.sleep(0.3)
            v1500 = {p: NOTMBR for p in range(1, 9)}
            for p in PORTS_678:
                v1500[p] = ACCESS
            qvlan_set_on_conn(c, ua, ip, PRIVATE_VLAN_ID, "VLAN1500", v1500)
            time.sleep(0.5)
            # Strip VLAN1 (Default) — TL-SG108E keeps port 6-8 untagged on VLAN1 unless cleared
            v1 = vlan_map_from_state(vids, u, t, 1)
            for p in PORTS_678:
                v1[p] = NOTMBR
            qvlan_set_on_conn(c, ua, ip, 1, "Default", v1)
            time.sleep(0.5)
            # Re-assert VLAN1500 access after VLAN1 strip
            vids, u, t, pvids = read_vlan_state(ip)
            v1500 = vlan_map_from_state(vids, u, t, PRIVATE_VLAN_ID)
            for p in PORTS_678:
                v1500[p] = ACCESS
            qvlan_set_on_conn(c, ua, ip, PRIVATE_VLAN_ID, "VLAN1500", v1500)
            time.sleep(0.4)
            for p in sorted(PORTS_678):
                pvid_set_on_conn(c, ua, ip, PORT_PBM[p], PRIVATE_VLAN_ID)
                time.sleep(0.3)
            c.close()
            time.sleep(0.75)
            break
        except (TimeoutError, OSError):
            try:
                c.close()
            except Exception:
                pass
            if attempt == 2:
                raise
            time.sleep(5)
    vids, u, t, pvids = read_vlan_state(ip)
    for p in sorted(PORTS_678):
        tagged, untagged = port_vlan_membership(vids, u, t, p)
        print("    port %d: PVID=%s untag=%s tag=%s" % (
            p, pvids[p - 1], untagged or "-", tagged or "-"))


def verify_ports_678_vlan1500(vids, u, t, pvids):
    ok = True
    reasons = []
    if vlan_index(vids, PRIVATE_VLAN_ID) is None:
        ok = False
        reasons.append("VLAN %d missing from switch" % PRIVATE_VLAN_ID)
    for port in PORTS_678:
        tagged, untagged = port_vlan_membership(vids, u, t, port)
        pvid = pvids[port - 1] if port - 1 < len(pvids) else None
        if pvid != PRIVATE_VLAN_ID:
            ok = False
            reasons.append("port %d PVID want %d got %s" % (port, PRIVATE_VLAN_ID, pvid))
        if untagged != [PRIVATE_VLAN_ID]:
            ok = False
            reasons.append("port %d untag want [%d] got %s" % (port, PRIVATE_VLAN_ID, untagged))
        if tagged:
            ok = False
            reasons.append("port %d has tagged VLANs: %s" % (port, tagged))
        for i, vid in enumerate(vids):
            if vid == PRIVATE_VLAN_ID:
                continue
            bit = PORT_BITS[port]
            if (u[i] & bit) or (t[i] & bit):
                ok = False
                reasons.append("port %d still member of VLAN %d" % (port, vid))
                break
    return ok, reasons


def apply_port_trunk_host(ip, port):
    """Single port trunk: tag VLAN1 + VLAN10-30, PVID 10; strip VLAN9 on that port."""
    print("  Step: port %d -> trunk tag V1+V10-30 PVID10" % port)
    for attempt in range(3):
        try:
            vids, u, t, pvids = read_vlan_state(ip)
            vnames = {1: "Default", 9: "VLAN9"}
            c, ua = login_conn(ip, timeout=60)
            # Remove port from VLAN9
            v9 = vlan_map_from_state(vids, u, t, 9)
            if v9.get(port) != NOTMBR:
                v9[port] = NOTMBR
                qvlan_set_on_conn(c, ua, ip, 9, "VLAN9", v9)
                time.sleep(0.4)
            # VLAN1 tagged
            v1 = vlan_map_from_state(vids, u, t, 1)
            v1[port] = TAG
            qvlan_set_on_conn(c, ua, ip, 1, "Default", v1)
            time.sleep(0.4)
            # VLAN10-30 tagged
            for vid in range(10, 31):
                idx = vlan_index(vids, vid)
                if idx is None:
                    continue
                pm = vlan_map_from_state(vids, u, t, vid)
                pm[port] = TAG
                qvlan_set_on_conn(c, ua, ip, vid, vnames.get(vid, "VLAN%d" % vid), pm)
                time.sleep(0.25)
            pvid_set_on_conn(c, ua, ip, PORT_PBM[port], 10)
            c.close()
            time.sleep(0.75)
            break
        except (TimeoutError, OSError):
            try:
                c.close()
            except Exception:
                pass
            if attempt == 2:
                raise
            time.sleep(5)
    vids, u, t, pvids = read_vlan_state(ip)
    tagged, untagged = port_vlan_membership(vids, u, t, port)
    print("    port %d now: PVID=%s untag=%s tag=%s" % (
        port, pvids[port - 1], untagged or "-", tagged))


def apply_port_vlan9_ordered(ip, port):
    """Port untagged VLAN9 access + PVID 9; strip all other VLAN membership."""
    print("  Step: port %d -> untagged VLAN9 access" % port)
    tout = 90 if port == 8 else 60
    for attempt in range(3):
        try:
            vids, u, t, pvids = read_vlan_state(ip)
            bit = PORT_BITS[port]
            vnames = {1: "Default", 9: "VLAN9"}
            c, ua = login_conn(ip, timeout=tout)
            for i, vid in enumerate(vids):
                if vid == 9:
                    pm = vlan_map_from_state(vids, u, t, 9)
                    pm[port] = ACCESS
                else:
                    if not ((u[i] & bit) or (t[i] & bit)):
                        continue
                    pm = vlan_map_from_state(vids, u, t, vid)
                    pm[port] = NOTMBR
                qvlan_set_on_conn(c, ua, ip, vid, vnames.get(vid, "VLAN%d" % vid), pm)
                time.sleep(0.4)
            pvid_set_on_conn(c, ua, ip, PORT_PBM[port], 9)
            c.close()
            time.sleep(0.75)
            break
        except (TimeoutError, OSError) as exc:
            try:
                c.close()
            except Exception:
                pass
            if attempt == 2:
                raise
            time.sleep(5)
    vids, u, t, pvids = read_vlan_state(ip)
    st = summarize(vids, u, t, pvids)
    mode = port_mode(st, port)
    print("    port %d now: %s (PVID=%s, v9_untag=%s)" % (
        port, mode, st["pvid"].get(port), st.get("v9_untag")))


def apply_ports_678_ordered(ip):
    for port in (6, 7, 8):
        apply_port_vlan9_ordered(ip, port)
    print("  Post port-8 reachability:", "OK" if switch_reachable(ip) else "LOST at %s" % ip)


def apply_trunk_ports_host(ip):
    """Trunk ports 2-5: tag VLAN1 + VLAN10-30, PVID 10; leave ports 1,6-8 unchanged."""
    c, ua = login_conn(ip)
    c.request("GET", "/Vlan8021QRpm.htm",
              headers={"Referer": "http://%s/" % ip, "User-Agent": ua})
    qhtml = c.getresponse().read().decode("utf-8", "replace")
    c.close()
    if not qvlan_enabled(qhtml):
        print("Enabling 802.1Q VLAN mode (was disabled)...")
        enable_8021q_vlan(ip)
    vids, u, t, _ = read_vlan_state(ip)

    v9_clear = {p: NOTMBR for p in range(1, 9)}
    merged9 = port_map_preserve_non_host(v9_clear, vids, u, t, 9)
    apply_qvlan(ip, 9, "VLAN9", merged9)
    time.sleep(0.75)

    merged1 = port_map_preserve_non_host(VLAN1_TRUNK, vids, u, t, 1)
    apply_qvlan(ip, 1, "Default", merged1)
    time.sleep(0.75)

    for vid, vname, port_map in VLAN_QUERIES:
        merged = port_map_preserve_non_host(port_map, vids, u, t, vid)
        apply_qvlan(ip, vid, vname, merged)
        time.sleep(0.75)

    apply_pvid(ip, TRUNK_PVID_PBM, 10)  # ports 2-5
    time.sleep(0.75)


def apply_pve01_pve02_layout(ip):
    """Port 1 VLAN9 access (pve01 home); ports 2-5 trunk V1+V10-30 (pve02+)."""
    print("Applying trunk V1+V10-30 on ports 2-5...")
    apply_trunk_ports_host(ip)
    print("Applying port 1 VLAN9 access (pve01 home internet)...")
    apply_port_vlan9_ordered(ip, 1)


def apply_switch(ip, safe=False):
    # Fresh HTTP login per change — long-lived sessions drop qvlan/PVID writes on TL-SG108E.
    c, ua = login_conn(ip)
    c.request("GET", "/Vlan8021QRpm.htm",
              headers={"Referer": "http://%s/" % ip, "User-Agent": ua})
    qhtml = c.getresponse().read().decode("utf-8", "replace")
    c.close()
    if not qvlan_enabled(qhtml):
        print("Enabling 802.1Q VLAN mode (was disabled)...")
        enable_8021q_vlan(ip)
    vids, u, t, _ = read_vlan_state(ip)

    if safe:
        v9_clear = {p: NOTMBR for p in range(1, 9)}
        merged9 = port_map_preserve_non_host(v9_clear, vids, u, t, 9)
        apply_qvlan(ip, 9, "VLAN9", merged9)
        time.sleep(0.75)
        merged1 = port_map_preserve_non_host(VLAN1_TRUNK, vids, u, t, 1)
        apply_qvlan(ip, 1, "Default", merged1)
        time.sleep(0.75)
        for vid, vname, port_map in VLAN_QUERIES:
            merged = port_map_preserve_non_host(port_map, vids, u, t, vid)
            apply_qvlan(ip, vid, vname, merged)
            time.sleep(0.75)
        apply_pvid(ip, TRUNK_PVID_PBM, 10)  # ports 2-5 after VLAN10 exists
        time.sleep(0.75)
        apply_port_vlan9_ordered(ip, 1)
        return

    if 25 in vids:
        apply_qvlan(ip, 25, "VLAN25", VLAN25_CLEANUP)
        time.sleep(1.5)
    apply_qvlan(ip, 9, "VLAN9", VLAN9)
    time.sleep(0.75)
    for vid, vname, port_map in VLAN_QUERIES:
        apply_qvlan(ip, vid, vname, port_map)
        time.sleep(0.75)
    apply_pvid(ip, TRUNK_PVID_PBM, 10)   # ports 2-5
    time.sleep(0.75)
    apply_pvid(ip, 1, 9)     # port 1
    time.sleep(0.75)
    apply_pvid(ip, 32, 9)    # port 6
    time.sleep(0.75)
    apply_pvid(ip, 64, 9)    # port 7
    time.sleep(0.75)
    apply_pvid(ip, 128, 9)   # port 8
    time.sleep(0.75)
    apply_qvlan(ip, 1, "Default", VLAN1_TRUNK)
    time.sleep(0.75)


all_ok = True
for ip in SWITCHES:
    name = "SW01" if ip == os.environ.get("SW01") else ("SW02" if ip == os.environ.get("SW02") else "SW")
    print("\n=== %s (%s) ===" % (name, ip))
    vids, u, t, pvids = read_vlan_state(ip)
    before = summarize(vids, u, t, pvids)
    links = read_link_state(ip)
    print_port_table(before, links, "BEFORE:")
    print("PVIDs:", before["pvid"])
    print("VLAN 10 tag ports:", before["v10_tag"], "| V10-30 tag union:", before.get("tag10_30", before["tag10_20"]))
    print("VLAN 9 tag ports:", before.get("v9_tag", []), "| VLAN 9 untag:", before.get("v9_untag", []), "| VLAN25 untag (legacy):", before["v25_untag"])


    if MODE == "--dump-ports":
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        c2, ua2 = login_conn(ip)
        c2.request("GET", "/Vlan8021QRpm.htm",
                  headers={"Referer": "http://%s/" % ip, "User-Agent": ua2})
        qhtml2 = c2.getresponse().read().decode("utf-8", "replace")
        c2.close()
        print("802.1Q VLAN enabled:", "yes" if qvlan_enabled(qhtml2) else "no")
        continue

    if MODE in ("--apply-trunk-2-5", "--apply-trunk-1-5"):
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        print("Applying trunk V1+V10-30 on ports 2-5 (preserve 1,6-8)...")
        apply_trunk_ports_host(ip)
        time.sleep(0.5)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        ok, reasons = verify_trunk_host(after)
        print("VERIFY trunk-2-5:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        continue

    if MODE == "--apply-pve01-pve02":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        apply_pve01_pve02_layout(ip)
        time.sleep(0.5)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        ok, reasons = verify_target(after)
        print("VERIFY:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        continue

    if MODE == "--dry-run":
        print("DRY-RUN: port1 VLAN9 access; PVID10 on 2-5; trunk 2-5 tag VLAN1+V10-30; VLAN9 access 6-8 on full --apply")
        print("DRY-RUN --apply-pve01-pve02: port1 home + trunk 2-5")
        print("DRY-RUN --apply-safe: trunk 2-5 only (no VLAN1 strip)")
        continue

    if MODE == "--apply-port1-home-trunk":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        print("Applying port 1 home trunk (untagged VLAN9 + tag V1+V10-30)...")
        apply_port1_home_trunk(ip, 1)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        tagged, untagged = port_vlan_membership(vids, u, t, 1)
        ok = after["pvid"].get(1) == 9 and 9 in untagged and 1 in tagged and 10 in tagged
        print("VERIFY port1-home-trunk:", "PASS" if ok else "FAIL")
        if not ok:
            all_ok = False
        continue

    if MODE == "--apply-ports-345-trunk-v9-30":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        print("Applying ports 3-5 trunk (untagged V9 + tag V10-30, PVID 9)...")
        apply_ports_345_trunk_v9_30(ip)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        ok, reasons = verify_ports_345_v9_30(vids, u, t, pvids)
        print("VERIFY ports-345-v9-30:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        continue

    if MODE == "--apply-port2-trunk":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        print("Applying port 2 trunk (tag V1+V10-30, PVID 10)...")
        apply_port_trunk_host(ip, 2)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        tagged, untagged = port_vlan_membership(vids, u, t, 2)
        ok = (after["pvid"].get(2) == 10 and not untagged
              and 1 in tagged and 10 in tagged)
        print("VERIFY port2-trunk:", "PASS" if ok else "FAIL")
        if not ok:
            all_ok = False
        continue

    if MODE == "--apply-port2-only":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        print("Applying port 2 only (VLAN9 access, internet)...")
        apply_port_vlan9_ordered(ip, 2)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        if after["pvid"].get(2) != 9 or 2 not in after.get("v9_untag", []):
            all_ok = False
            print("VERIFY port2: FAIL")
        else:
            print("VERIFY port2: PASS")
        continue

    if MODE == "--apply-port1-only":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        print("Applying port 1 only (VLAN9 access, pve01 home)...")
        apply_port_vlan9_ordered(ip, 1)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        if after["pvid"].get(1) != 9 or 1 not in after.get("v9_untag", []):
            all_ok = False
            print("VERIFY port1: FAIL")
        else:
            print("VERIFY port1: PASS")
        continue

    if MODE == "--apply-port8-only":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        print("Applying port 8 only (VLAN9 access, last)...")
        apply_port_vlan9_ordered(ip, 8)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        ok, reasons = verify_target(after)
        print("VERIFY:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        continue

    if MODE == "--apply-table1":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        apply_table1_layout(ip)
        time.sleep(0.5)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        ok, reasons = verify_table1_layout(vids, u, t, pvids)
        print("VERIFY table1:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        if not switch_reachable(ip):
            print("NOTE: mgmt IP %s unreachable after Table 1 apply" % ip)
        continue

    if MODE == "--apply-ports-678-vlan1500":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        apply_ports_678_vlan1500(ip)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        print_detailed_port_table(vids, u, t, pvids, links, "PORT DETAILS:")
        ok, reasons = verify_ports_678_vlan1500(vids, u, t, pvids)
        print("VERIFY ports-678-vlan1500:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        if not switch_reachable(ip):
            print("NOTE: mgmt IP %s may be unreachable; port 8 is now on VLAN %d" % (
                ip, PRIVATE_VLAN_ID))
        continue

    if MODE == "--apply-ports-678":
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip)
            all_ok = False
            continue
        print("Applying ports 6->7->8 VLAN9 (ordered)...")
        apply_ports_678_ordered(ip)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        ok, reasons = verify_target(after)
        print("VERIFY:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        if not switch_reachable(ip):
            print("NOTE: mgmt IP %s unreachable after port 8; recover via trunk port 1 or temporary cable on VLAN9" % ip)
        continue

    if MODE in ("--apply", "--apply-safe"):
        if not switch_reachable(ip):
            print("SKIP: switch unreachable at", ip, "(no HTTP login); not applying")
            all_ok = False
            continue
        safe = MODE == "--apply-safe"
        print("Applying VLAN config (%s)..." % ("apply-safe ports 1-5" if safe else "full"))
        apply_switch(ip, safe=safe)
        time.sleep(0.5)
        vids, u, t, pvids = read_vlan_state(ip)
        after = summarize(vids, u, t, pvids)
        links = read_link_state(ip)
        print_port_table(after, links, "AFTER:")
        if safe:
            print("VERIFY: skipped full target check (--apply-safe); re-run --verify when ready for full apply")
            continue
        ok, reasons = verify_target(after)
        print("VERIFY:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        continue

    if MODE == "--verify":
        ok, reasons = verify_target(before)
        print("VERIFY:", "PASS" if ok else "FAIL")
        for r in reasons:
            print("  -", r)
        if not ok:
            all_ok = False
        continue

    print("Unknown mode:", MODE, file=sys.stderr)
    sys.exit(2)

sys.exit(0 if all_ok else 1)
PY
}

case "$MODE" in
  --dry-run|--apply|--apply-safe|--apply-pve01-pve02|--apply-trunk-2-5|--apply-trunk-1-5|--apply-table1|--apply-port1-only|--apply-port2-only|--apply-port2-trunk|--apply-ports-345-trunk-v9-30|--apply-port1-home-trunk|--apply-ports-678|--apply-ports-678-vlan1500|--apply-port8-only|--verify|--dump-ports) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown option: $MODE" >&2; usage; exit 1 ;;
esac

require_python3
run_python
