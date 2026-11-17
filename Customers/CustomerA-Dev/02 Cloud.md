# CustomerA Dev – 02 Cloud

> Procedure: 9.3.

| Item | Value |
|---|---|
| Cloud | `CustomerA-Dev-Cloud` |
| Host group | `All Hosts\Provider-DC\Cluster1` |
| Logical network | `HNV-PA` only |
| Load Balancers / VIP Templates | None (admins create the VIPs, 9.3) |
| Port classification | `Medium bandwidth` |
| Cost Center | `CustomerA`, set **on each VM** (cloud description too): `New-SCCloud` has no such field (9.3 §2) |
| Tag | `CustomerA-Dev`, set **on each VM** (cloud description too) |

## Capacity

Computed from `00 Intake.md` §5. The powered-off VMs depend on Q6.

| Resource | 12 powered on | If Q6 adds all 3 powered-off | Headroom | Cloud capacity |
|---|---|---|---|---|
| VM count | 12 | 15 | `<headroom>` | |
| vCPU | 88 | 100 | `<headroom>` | |
| Memory | 220 GB | 258 GB | `<headroom>` | |
| Storage | 2,100 GB | 2,308 GB | `<headroom>` | |

- Storage is the disk size in the export. Converted VHDX size may differ.
- **CSV01 (~3 TB, 5.1) is sized for infrastructure VMs.** CustomerA Dev alone needs 2.1–2.3 TB, so it needs its own customer CSV LUN (0.2 §7).
- Check N-1 before migration: 220–258 GB of RAM plus the infrastructure and SDN VMs must fit on 3 hosts (`ClusterReserve 1`, 6.3). Host RAM: 0.2 §8.

---

## Gate (9.3)

> Record the results in `05 As-Built.md`.

- Cloud created, capacity set.
- 9.3 §3 check returns nothing after migration.
- Every VM has Cost Center `CustomerA` and Tag `CustomerA-Dev`.
