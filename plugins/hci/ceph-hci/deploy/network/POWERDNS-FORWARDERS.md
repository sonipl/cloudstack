# PowerDNS01 / PowerDNS02 external recursion baseline

**Status:** LIVE / working (verified 2026-07-31)  
**Hosts:** powerdns01 `10.0.10.21`, powerdns02 `10.0.10.22`  
**Role:** Authoritative `vmalpha.com` (pdns on `127.0.0.1:5353`) + dnsmasq on `:53` for clients  
**Canonical operator copy:** `/Users/psoni/Forman/deploy/network/`

## Symptom (fixed)

Clients using `nameserver 10.0.10.21` / `.22` could resolve lab names (`ac01.vmalpha.com`) but
`nslookup www.google.com` hung / timed out.

## Root cause

- dnsmasq forwarders were `192.168.68.1` and `1.1.1.1` (correct design).
- Host default gateway was **`10.0.10.1`**, which does **not** answer ARP from these VMs
  (`ip neigh` → `INCOMPLETE`), so upstream DNS was unreachable.
- Authoritative answers still worked because they stay local (`127.0.0.1#5353`).

## Permanent fix

| Setting | Value |
|---------|--------|
| Default GW (NM `ens192`) | **vyos01 `10.0.10.3`** |
| dnsmasq upstreams | `1.1.1.1`, `8.8.8.8`, `192.168.68.1` |
| Auth path | `server=/vmalpha.com/127.0.0.1#5353` (+ reverse zones) |

Persisted on disk:

- `/etc/NetworkManager/system-connections/ens192.nmconnection` → `gateway=10.0.10.3`
- `/etc/dnsmasq.d/vmalpha-split.conf` → upstream `server=` lines

## Re-apply / verify

```bash
# From ac01 (or any host with sshpass + reachability to 10.0.10.21/22):
bash deploy/network/fix-powerdns-forwarders.sh
bash deploy/network/fix-powerdns-forwarders.sh --verify

# Client check:
dig @10.0.10.21 www.google.com A +short
dig @10.0.10.22 www.google.com A +short
dig @10.0.10.21 ac01.vmalpha.com A +short
```

## Related

- `lab-network-target.env` — `PDNS01_HOST`, `PDNS02_HOST`, `PDNS_DEFAULT_GW`
- `fix-powerdns-forwarders.sh` — idempotent apply
- `../k8s/scripts/ensure-k8s-dns.sh` (Forman) — dnsmasq frontend for both PDNS hosts; notes GW requirement
- Foreman resolver `192.168.71.22` already had working recursion (unaffected)
