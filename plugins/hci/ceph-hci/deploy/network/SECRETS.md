# Lab network secrets (no plaintext in git)

## Policy

- **Never** commit `SW_PASS`, `IDRAC_PASS`, guest SSH passwords, or API tokens in plaintext.
- Tracked files may reference variable names only.
- Optional encrypted blob: `lab-network-secrets.env.enc` (AES-256-CBC, PBKDF2).
- Passphrase for that blob lives **only** in KeePass / out-of-band (`LAB_NETWORK_SECRETS_PASSPHRASE`).

## Files

| File | In git? | Purpose |
|------|---------|---------|
| `lab-network-secrets.env.example` | yes | placeholders |
| `lab-network-secrets.env` | **no** (gitignored) | local plaintext for operators |
| `lab-network-secrets.env.enc` | yes (encrypted) | shareable ciphertext |
| `load-lab-secrets.sh` | yes | decrypt/source into env |
| `encrypt-lab-secrets.sh` | yes | rebuild `.enc` from plaintext |

## Usage

```bash
cd plugins/hci/ceph-hci/deploy/network

# One-time: local plaintext (gitignored)
cp lab-network-secrets.env.example lab-network-secrets.env
$EDITOR lab-network-secrets.env

# Optional: encrypt for repo (passphrase from KeePass)
export LAB_NETWORK_SECRETS_PASSPHRASE='…'
./encrypt-lab-secrets.sh
# commit only lab-network-secrets.env.enc

# Before running network scripts:
source ./load-lab-secrets.sh
bash ./setup-tplink-lab-vlans.sh --dump-ports
bash ./fix-powerdns-forwarders.sh --verify
```

## History note

Earlier commits on `feature/ceph-hci-plugin` briefly contained plaintext lab passwords.
Those were removed from HEAD; **rotate** switch/iDRAC/guest passwords if the fork was shared,
and optionally purge history with `git filter-repo` + force-push (explicit operator action).
