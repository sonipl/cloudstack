# SW01 / SW02 port & VLAN baseline (Table 1)

**Status:** LIVE / working lab baseline  
**Verified:** 2026-07-31  
**Switches:** TP-Link TL-SG108E — SW01 `192.168.71.11`, SW02 `192.168.71.12`  
**Source spreadsheet:** `SW01-SW02-Ports.xlsx` (same folder; Excel may show Tagged `10-30` as date serial `46325`)  
**Canonical lab copy:** `/Users/psoni/Forman/deploy/network/`  
**Apply / verify:**

```bash
bash deploy/network/setup-tplink-lab-vlans.sh --apply-table1
bash deploy/network/setup-tplink-lab-vlans.sh --dump-ports
```

Do **not** re-run older modes (`--apply-trunk-2-5`, `--apply-ports-678-vlan1500`, etc.) against this lab —
they use a different port map and can strand mgmt.

## Design

| VLAN | Use |
|------|-----|
| 1 | Home / mgmt native (untagged) on trunks + uplink |
| 10–30 | Lab / prov / platform — tagged on pub trunks only |
| 1500 | Private host links (ptv-access) — access only on ports 5–7 |

Port **8** must stay **access VLAN 1** or switch UI at `.11`/`.12` is stranded.

## Port map (VLAN layout identical on both switches)

| Port | Type | PVID | Untagged | Tagged | SW01 cabling | SW02 cabling |
|------|------|------|----------|--------|--------------|--------------|
| 1 | Hybrid trunk | 1 | 1 | 10–30 | Oelbm01-nic2 | Foreman-nic2 |
| 2 | Hybrid trunk | 1 | 1 | 10–30 | Pve03-nic1-pub-trunk | Pve03-nic2-pub-trunk |
| 3 | Hybrid trunk | 1 | 1 | 10–30 | Pve04-nic1-pub-trunk | Pve04-nic2-pub-trunk |
| 4 | Hybrid trunk | 1 | 1 | 10–30 | Pve05-nic1-pub-trunk | Pve05-nic2-pub-trunk |
| 5 | Access | 1500 | 1500 | — | Pve03-nic3-ptv-access | Pve03-nic4-ptv-access |
| 6 | Access | 1500 | 1500 | — | Pve04-nic3-ptv-access | Pve04-nic4-ptv-access |
| 7 | Access | 1500 | 1500 | — | Pve05-nic3-ptv-access | Pve05-nic4-ptv-access |
| 8 | Access | 1 | 1 | — | Uplink / home | Uplink / home |

## Live dump (2026-07-31, post `--apply-table1`, VERIFY PASS)

Both switches:

```
Port PVID  Tagged                         Untagged
1    1     10-30                          1
2    1     10-30                          1
3    1     10-30                          1
4    1     10-30                          1
5    1500  -                              1500
6    1500  -                              1500
7    1500  -                              1500
8    1     -                              1
802.1Q: enabled
```

## Related files

- `lab-network-target.env` — env vars (`SW_LAYOUT=table1`, trunk/private ports)
- `setup-tplink-lab-vlans.sh --apply-table1` — idempotent apply
- `SW01-SW02-Ports.csv` / `.xlsx` — spreadsheet record
