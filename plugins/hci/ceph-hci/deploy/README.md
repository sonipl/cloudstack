# Deploy KVM + Ceph + CloudStack HCI on vc01.vmalpha.com (OEL9)

`vc01.vmalpha.com` resolves to a **VMware vCenter 8** endpoint. This directory
bootstraps three (or more) OEL9 VMs on that vCenter, then installs a
hyperconverged stack:

| Role | Count | Software |
|---|---|---|
| HCI nodes | 3+ | OEL9, KVM/libvirt, cloudstack-agent, Ceph (cephadm Squid/Reef) |
| Management | 1 (can co-locate on node1 for labs) | MariaDB, cloudstack-management + `cloud-plugin-hci-ceph` |

## Prerequisites

1. Access to vCenter `vc01.vmalpha.com` with permission to create VMs.
2. An **OEL9** template (or ISO) available in the vCenter content library /
   datastore. Default template name: `OEL9-Base`.
3. Tools on the operator workstation:
   - [govc](https://github.com/vmware/govmomi)
   - Ansible 2.14+
   - SSH key that will be injected into the VMs
4. Environment (do **not** commit secrets):

```bash
export GOVC_URL='https://vc01.vmalpha.com'
export GOVC_USERNAME='administrator@vsphere.local'
export GOVC_PASSWORD='***'
export GOVC_INSECURE=true          # lab only
export GOVC_DATACENTER='Datacenter'
export GOVC_DATASTORE='datastore1'
export GOVC_NETWORK='VM Network'
export GOVC_CLUSTER='Cluster'      # or GOVC_RESOURCE_POOL
export GOVC_FOLDER='cloudstack-hci'
export OEL9_TEMPLATE='OEL9-Base'
export HCI_SSH_PUBLIC_KEY=~/.ssh/id_rsa.pub
export HCI_SSH_PRIVATE_KEY=~/.ssh/id_rsa
```

## Step 1 — Create VMs from OEL9 template

```bash
cd plugins/hci/ceph-hci/deploy
./govc-create-vms.sh
# Creates: hci-mgmt, hci-node1, hci-node2, hci-node3
# Writes inventory.ini with DHCP/guest-IP addresses once VMware Tools reports them
```

## Step 2 — Install HCI stack (Ansible)

```bash
# Edit inventory.ini if IPs were not auto-detected
ansible-playbook -i inventory.ini ansible/site.yml
```

The playbook:

1. Hardens OEL9 (packages, firewalld ports for Ceph/libvirt/NFS/CloudStack)
2. Installs KVM + cloudstack-agent on `hci_nodes`
3. Bootstraps Ceph via `cephadm` (MON/MGR/OSD on each node; RBD pool `cloudstack`)
4. Installs MariaDB + cloudstack-management on `hci_mgmt` (lab: node1 can be mgmt)
5. Configures MS SSH key access to Ceph MONs for the HCI plugin
6. Prints the CloudStack UI URL and next API steps to add RBD primary storage

## Step 3 — Register Ceph as CloudStack RBD primary storage

After management is up (`http://<mgmt>:8080/client`):

```bash
# On mgmt host — collect MON addresses and cephx key
ceph mon dump -f json
ceph auth get-key client.admin

# Via CloudStack UI or cmk:
# Infrastructure → Primary Storage → Add
#   Protocol: RBD / Ceph
#   Provider: DefaultPrimary
#   RADOS Monitor: <mon1>,<mon2>,<mon3>
#   RADOS Pool: cloudstack
#   RADOS User: admin
#   RADOS Secret: <key>
```

Then verify:

```text
listHciCephHealth
refreshHciCephHealth
```

## Lab sizing (nested under vCenter)

| VM | vCPU | RAM | System disk | Extra disk (OSD) |
|---|---|---|---|---|
| hci-mgmt | 4 | 16 GB | 80 GB | — |
| hci-nodeN | 8 | 32 GB | 80 GB | 200 GB |

Nested virtualization must be enabled on the HCI node VMs (`vhv.enable = TRUE`
is set by `govc-create-vms.sh`).

## Lab switch baseline (SW01 / SW02)

Permanent port/VLAN record for the TP-Link TL-SG108E lab switches (Table 1,
verified 2026-07-31):

- [`network/SW01-SW02-PORTS.md`](network/SW01-SW02-PORTS.md)
- [`network/SW01-SW02-Ports.csv`](network/SW01-SW02-Ports.csv)
- [`network/lab-network-target.env`](network/lab-network-target.env) (no passwords)
- Apply: `source network/load-lab-secrets.sh && bash network/setup-tplink-lab-vlans.sh --apply-table1`

## PowerDNS01 / PowerDNS02 recursion

External recursion (`www.google.com`) for `10.0.10.21` / `.22` — GW must be
**vyos01 `10.0.10.3`** (not `10.0.10.1`):

- [`network/POWERDNS-FORWARDERS.md`](network/POWERDNS-FORWARDERS.md)
- Apply: `source network/load-lab-secrets.sh && bash network/fix-powerdns-forwarders.sh`

## Secrets

Do **not** commit plaintext passwords. See [`network/SECRETS.md`](network/SECRETS.md).
Encrypted blob (optional): `network/lab-network-secrets.env.enc`.

Canonical operator copy also lives under `/Users/psoni/Forman/deploy/network/`.

## Alternative: existing bare-metal / already-running OEL9 hosts

Skip Step 1. Copy `inventory.example.ini` → `inventory.ini`, set host IPs, run
Step 2.
