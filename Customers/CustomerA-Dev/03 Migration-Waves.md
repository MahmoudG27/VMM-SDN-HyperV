# CustomerA Dev – 03 Migration waves

> Procedure: 9.4. CustomerA Dev is the **pilot of the whole migration**: every "to be verified" in 9.x gets its first real answer here. Record the answers in `05 As-Built.md`.

## 1. VM placement

Generation follows the source firmware (still open, Q10). Host preference is a starting point: confirm it against host RAM (0.2 §8) and the N-1 check (02 Cloud).

| VM | VM subnet | IP | OS | vCPU | RAM | Disk | Gen | Host preference | Wave | Migrate |
|---|---|---|---|---|---|---|---|---|---|---|
| SEC-EXT-FW-01 | OUT-OUT-FW / INT-SEC-MGT / Open_VPN | 10.10.10.10 / 10.1.200.6 / 10.10.200.5 | FreeBSD 13+ | 4 | 16 GB | 116 GB | Q10 | Any | 1 | Yes |
| SEC-INT-FW-01 | 7 backends + INT-SEC-MGT (Q2) | `<intfw-ip-*>` (Q1) | FreeBSD 13+ | 2 | 16 GB | 116 GB | Q10 | Any | 1 | Yes |
| SEC-INT-MGT-01 | INT-SEC-MGT | 10.1.200.250 | WS2019 | 2 | 4 GB | 94 GB | Q10 | Any | 1 | Yes |
| Kubernetes Master-R | K8s | 10.1.40.55 | CentOS 7 | 4 | 8 GB | 110 GB | Q10 | Not with a worker | 2 | Yes |
| KubernetesWorker | K8s | 10.1.40.56 | CentOS 7 | 14 | 32 GB | 172 GB | Q10 | Host A | 2 | Yes |
| K8s-Worker02 | K8s | 10.1.40.57 | CentOS 8 | 14 | 32 GB | 232 GB | Q10 | Host B | 2 | Yes |
| K8s-Worker03 | K8s | 10.1.40.58 | CentOS 8 | 14 | 32 GB | 232 GB | Q10 | Host C | 2 | Yes |
| Loadbalancer | LB70 | 10.1.70.55 | CentOS 7 | 2 | 8 GB | 110 GB | Q10 | Any | 3 | Yes |
| Agents_restore2 | Agent | 10.1.20.55 | CentOS 7 | 6 | 16 GB | 118 GB | Q10 | Any | 3 | Yes |
| Core-Server | Core | 10.1.60.55 | CentOS 7 | 8 | 16 GB | 206 GB | Q10 | Any | 3 | Yes |
| Chef | Chef | 10.1.30.55 | CentOS 7 | 2 | 8 GB | 160 GB | Q10 | Any | 3 | Yes |
| MongoDB | MongoDB | 10.1.50.55 | CentOS 7 | 16 | 32 GB | 434 GB | Q10 | Host D (no K8s worker) | 4 | Yes |
| OpenVPN | Open_VPN | 10.10.200.10 | Ubuntu 64-bit | 2 | 2 GB | 52 GB | Q10 | Any | Q6 | Q6 |
| Lora-Network | LB70 | 10.1.70.56 | CentOS 8 | 8 | 32 GB | 62 GB | Q10 | Any | Q6 | Q6 |
| CADNS.CustomerA.mgmt | INT-INF-SRV (Q12) | Q12 | WS2019 | 2 | 4 GB | 94 GB | Q10 | Any | Q6 | Q6 |

Host A–D = HV01–HV04 in any order. The three K8s workers and MongoDB are the largest VMs, so they're spread over the 4 hosts.

## 2. Waves

There's **no L2 path** between NSX and SDN (0.0 §7). CustomerA's subnets all depend on the firewalls, so a VM on one side can't reach a VM on the other. All waves run in **one window**, unless a temporary L3 path is decided with the provider.

| Wave | VMs | Data | Why this order | Check before the next wave |
|---|---|---|---|---|
| 0 | No VM: VM network, script filled, cloud, VIP templates, vCenter in VMM (9.4 §2) | – | Nothing depends on it | Gates 9.2 (network part), 9.3 |
| 1 | SEC-EXT-FW-01, SEC-INT-FW-01, SEC-INT-MGT-01 | 326 GB | **Firewalls first:** every path depends on them. The management server gives a test point | NICs mapped, Apply `No drift`, guard on, L28 drill, L29 access from SEC-INT-MGT-01 to 10.1.200.6 |
| 2 | Kubernetes master + 3 workers | 746 GB | Together: the cluster shouldn't be split | Cluster nodes Ready |
| 3 | Loadbalancer, Agents_restore2, Core-Server, Chef | 594 GB | Each is one VM | Services up, `tracert` through the firewall |
| 4 | MongoDB | 434 GB | **Last:** largest single VM. Time it from the earlier waves' throughput | Data intact (Q9) |
| 5 | Powered-off VMs, if Q6 says yes | 208 GB | They're off, so no pressure | – |
| Cutover | Public IPs | – | 04 Cutover | Gate 9.5 |

- End-to-end application tests only pass after wave 4.
- **Total in the window: 2,100 GB** (up to 2,308 GB with wave 5). Wave 2 is the largest wave. Measure the conversion speed in wave 1, then check that the rest fits (Q7, Q9). If it doesn't, move a wave to a separate date only if the customer accepts the outage, because the two platforms can't reach each other.
- **Conversion time estimate for 2.1 TB (copy only, from the ESXi management network):** ≈ 6–7 h at 1 Gbps, ≈ 2–3 h at 10 Gbps. Depends on the ESXi management NIC and datastore read speed (Q18). Boot checks, IP fixes and tests come on top.
- Max 10 parallel conversions per ESXi → Hyper-V pair (9.4 §1).

## 3. OS steps (references)

| VM | Steps |
|---|---|
| SEC-EXT-FW-01, SEC-INT-FW-01 | 9.4 §3 FreeBSD: remove open-vm-tools, export config, remap `vmx*` → `hn*` **by MAC** from the console. FreeBSD conversion by VMM is *to be verified*; alternative: new appliance + config import |
| All CentOS 7 and 8 VMs (10) | 9.4 §3 CentOS: `yum remove open-vm-tools`, `dracut -f --add-drivers "hv_vmbus hv_storvsc hv_netvsc"`, `ifcfg-ens192` → `ifcfg-eth0` without `HWADDR`, fstab by UUID. CentOS 8 repositories are archived, so `yum remove` works but don't plan package installs |
| OpenVPN | 9.4 §3 Ubuntu (*to be verified*) |
| SEC-INT-MGT-01, CADNS.CustomerA.mgmt | 9.4 §3 Windows: save the IP config, uninstall VMware Tools, re-apply the IP on the new NIC. L24 for TCP tests |
| All | Snapshot → remove Tools → verify → **delete the snapshot** → shut down → convert (VMM requires no snapshots) |
| All backend VMs | Gateway inside the guest = the subnet's `.1` |

---

## Gate (9.4)

> Record the results in `05 As-Built.md`.

- Every wave's check passed.
- Apply `-CheckOnly` = `No drift` after each wave.
- Conversion speed and FreeBSD/Linux results recorded for the next customers.
