# Apache CloudStack Plugin - HCI Ceph (vSAN-like hyperconverged integration)

This plugin turns a **KVM + Apache CloudStack + Ceph** deployment into a
vSAN-like hyperconverged infrastructure (HCI) solution: the same hosts run
VMs (KVM) and contribute storage (Ceph OSDs), while CloudStack gains
data-service awareness of the underlying Ceph clusters — analogous to how
vCenter/vSAN tracks object health, compliance and placement.

## What vSAN does -> what this plugin does

| VMware vSAN capability | Equivalent in this plugin |
|---|---|
| vSAN health service | `CephHciManager` polls `ceph status` per backing Ceph cluster and caches health |
| vSAN placement on healthy objects only | `CephHciStoragePoolAllocator` excludes RBD pools on unhealthy/degraded Ceph clusters from VM & volume placement |
| vSAN degraded/critical alarms | CloudStack alerts (`ALERT.STORAGE.MISC`) raised on Ceph health transitions and recovery |
| vSAN health UI | `listHciCephHealth` API (per-pool: health, OSDs up/in, PGs, quorum, allocation state) |
| Skyline re-check on demand | `refreshHciCephHealth` API |

KVM-side RBD operations (clone/snapshot/thin provisioning via Ceph
layering) are already native in CloudStack's KVM agent
(`LibvirtStorageAdaptor`, `KVMStorageProcessor`); this plugin adds the
management-plane intelligence on top.

## Components

- `CephHciManagerImpl` — management server component. Groups all `Up` RBD
  primary storage pools by Ceph cluster endpoint (`monHost:port`), polls
  `ceph status -f json` over SSH on a configurable interval, caches health,
  and emits alerts on HEALTH transitions.
- `CephHciStoragePoolAllocator` — storage pool allocator. Behaves like the
  standard random allocator across cluster- and zone-scoped pools, but skips
  RBD pools whose Ceph cluster is not in an accepted health state.
- API commands (Root Admin):
  - `listHciCephHealth` — per-pool Ceph health and allocation state.
  - `refreshHciCephHealth` — forces an immediate health refresh.
- `CephClusterHealth` — tolerant parser for `ceph status -f json`
  (handles both `health.status` and `health.overall_status` schemas).

## Global settings (ConfigKeys)

| Setting | Default | Description |
|---|---|---|
| `ceph.hci.allocation.enforce.health` | `true` | Exclude RBD pools on unhealthy Ceph clusters from allocation |
| `ceph.hci.health.accepted.states` | `HEALTH_OK,HEALTH_WARN` | Health states still acceptable for allocation |
| `ceph.hci.health.check.interval` | `300` | Seconds between Ceph health polls (0 disables) |
| `ceph.hci.monitor.ssh.user` | `root` | SSH user for Ceph monitors |
| `ceph.hci.monitor.ssh.port` | `22` | SSH port for Ceph monitors |
| `ceph.hci.monitor.ssh.password` | (empty) | SSH password; empty = use private key |
| `ceph.hci.monitor.ssh.privatekey.path` | `/root/.ssh/id_rsa` | Management-server SSH key for monitors |

## Reference topology (vSAN-like, 3+ nodes)

```
        +----------------------------------------------------+
        |          CloudStack Management Server              |
        |   cloud-plugin-hci-ceph (health, alerts, placement)|
        +-------------------------+--------------------------+
                                  |
        +-------------------------+--------------------------+
        |              KVM + Ceph HCI cluster                |
        |  node1: KVM agent + Ceph MON/MGR + OSDs            |
        |  node2: KVM agent + Ceph MON + OSDs                |
        |  node3: KVM agent + Ceph MON + OSDs                |
        |                                                    |
        |  Ceph pool "cloudstack" (size=3) ->                |
        |  CloudStack RBD primary storage (zone-wide)        |
        +----------------------------------------------------+
```

Deploy Ceph (Reef/Squid) with `cephadm` across the KVM hosts, create an RBD
pool, then add it to CloudStack as **RBD primary storage** with the MON
addresses. The plugin discovers all `Up` RBD pools automatically.

## Building

```bash
# from the repository root (requires JDK 11+/17 and Maven)
mvn -pl plugins/hci/ceph-hci -am install
# full packaging
mvn -P systemvm install -DskipTests
```

## Testing

```bash
mvn -pl plugins/hci/ceph-hci test
```

Covers: `ceph status` JSON parsing (legacy + modern schema), OSD degradation
detection, health-acceptance rules, and allocator gating (unhealthy pools
excluded and added to the avoid set, zone-wide pools included).
