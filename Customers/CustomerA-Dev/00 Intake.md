# CustomerA Dev – 00 Intake

> Template and field sources: 9.1. Pattern: **B** (the PM decided "same design"). First customer: pilot of the whole migration.

## 1. General

| Field | Value |
|---|---|
| Customer / short name | CustomerA Dev / `CustomerA-Dev` |
| Contacts, application testers | Open (Q7) |
| Downtime window / rollback period | Open (Q7) |
| vCenter / ESXi version | Open (Q11). VMM 2025 supports 7.0 and 8.0 only |
| Datastore type | Open (Q11). VMM can't convert VMs on vSAN |

## 2. NSX topology

| Item | Value |
|---|---|
| Tier-0 | `D-VRF-CustomerA` (VRF), BGP to the provider AS 65000 via 10.212.47.68/31 and 10.212.48.68/31 |
| Tier-1 | `CustomerA-ESG`: NAT + gateway firewall |

## 3. Segments on Tier-1

| Segment | Gateway | Used by | Notes |
|---|---|---|---|
| INT-SEC-MGT | 10.1.200.1/24 | SEC-INT-MGT-01 10.1.200.250, SEC-EXT-FW-01 10.1.200.6 | |
| Open_VPN | 10.10.100.1/24 in NSX | OpenVPN VM 10.10.200.10, external FW 10.10.200.5 in the diagram | **Inconsistent** (Q3) |
| OUT-OUT-FW | 10.10.10.1/24 | SEC-EXT-FW-01 10.10.10.10 | Static routes on Tier-1: 10.0.0.0/8 and 10.10.200.0/24 via 10.10.10.10 |
| CustomerA-Private-Network | 10.10.1.1/24 | No VM known | 10.10.1.10 / 10.10.1.100 appear only in disabled NAT rules |

## 4. Isolated networks behind SEC-INT-FW-01 (not on Tier-1)

| Network | NSX network name | Prefix | SEC-INT-FW-01 interface |
|---|---|---|---|
| Agent | INT-3RD-AGT | 10.1.20.0/24 | Open (Q1) |
| Chef | INT-DEV-OPS | 10.1.30.0/24 | Open (Q1) |
| K8s | INT-KUB-SRV | 10.1.40.0/24 | Open (Q1) |
| MongoDB | INT-DB-SRV | 10.1.50.0/24 | Open (Q1) |
| Core | INT-COR-SRV | 10.1.60.0/24 | Open (Q1) |
| LB | INT-LB-INTIF | 10.1.70.0/24 | Open (Q1) |
| LB | Unknown (Q12) | 10.1.80.0/24 | Open (Q1). No VM known |
| ? | INT-INF-SRV | Unknown (Q12) | CADNS is on it. May be 10.1.80.0/24, or a 12th network |

## 5. VMs

Source: CustomerA Dev NSX/vCenter export. Disk = total per VM. **Firmware, MAC, gateway and DNS** are still open (Q10).
SEC-INT-FW-01's export row shows only its first network (INT-DB-SRV). Its other interfaces: Q1, Q2.

| VM | OS | Firmware | vCPU | RAM | Disk | IP | NSX network | Default GW | Power | Migrate |
|---|---|---|---|---|---|---|---|---|---|---|
| Kubernetes Master-R | CentOS 7 | Q10 | 4 | 8 GB | 110 GB | 10.1.40.55 | INT-KUB-SRV | Q1 | On | Yes |
| KubernetesWorker | CentOS 7 | Q10 | 14 | 32 GB | 172 GB | 10.1.40.56 | INT-KUB-SRV | Q1 | On | Yes |
| K8s-Worker02 | CentOS 8 | Q10 | 14 | 32 GB | 232 GB | 10.1.40.57 | INT-KUB-SRV | Q1 | On | Yes |
| K8s-Worker03 | CentOS 8 | Q10 | 14 | 32 GB | 232 GB | 10.1.40.58 | INT-KUB-SRV | Q1 | On | Yes |
| Agents_restore2 | CentOS 7 | Q10 | 6 | 16 GB | 118 GB | 10.1.20.55 | INT-3RD-AGT | Q1 | On | Yes |
| Core-Server | CentOS 7 | Q10 | 8 | 16 GB | 206 GB | 10.1.60.55 | INT-COR-SRV | Q1 | On | Yes |
| MongoDB | CentOS 7 | Q10 | 16 | 32 GB | 434 GB | 10.1.50.55 | INT-DB-SRV | Q1 | On | Yes |
| Loadbalancer | CentOS 7 | Q10 | 2 | 8 GB | 110 GB | 10.1.70.55 | INT-LB-INTIF | Q1 | On | Yes |
| Chef | CentOS 7 | Q10 | 2 | 8 GB | 160 GB | 10.1.30.55 | INT-DEV-OPS | Q1 | On | Yes |
| SEC-INT-MGT-01 | Windows Server 2019 | Q10 | 2 | 4 GB | 94 GB | 10.1.200.250 | INT-SEC-MGT | Q10 | On | Yes |
| SEC-EXT-FW-01 | FreeBSD 13 or later | Q10 | 4 | 16 GB | 116 GB | 10.1.200.6 / 10.10.10.10 / 10.10.200.5 | INT-SEC-MGT (+ others) | Q5 | On | Yes |
| SEC-INT-FW-01 | FreeBSD 13 or later | Q10 | 2 | 16 GB | 116 GB | Unknown (Q1, Q2) | INT-DB-SRV (+ others) | Q5 | On | Yes |
| OpenVPN | Ubuntu Linux (64-bit) | Q10 | 2 | 2 GB | 52 GB | 10.10.200.10 | Openvpn | Q3 | **Off** | Q6 |
| Lora-Network | CentOS 8 | Q10 | 8 | 32 GB | 62 GB | 10.1.70.56 | INT-LB-INTIF | Q1 | **Off** | Q6 |
| CADNS.CustomerA.mgmt | Windows Server 2019 | Q10 | 2 | 4 GB | 94 GB | Q12 | INT-INF-SRV | Q12 | **Off** | Q6 |

| Totals | VMs | vCPU | RAM | Disk |
|---|---|---|---|---|
| Powered on | 12 | 88 | 220 GB | 2,100 GB |
| Powered off | 3 | 12 | 38 GB | 208 GB |
| **All** | **15** | **100** | **258 GB** | **2,308 GB** |

## 6. Firewall VMs

| Firewall | Interface | Segment | IP | First IP? |
|---|---|---|---|---|
| SEC-EXT-FW-01 | External | OUT-OUT-FW | 10.10.10.10 | No |
| SEC-EXT-FW-01 | Internal | INT-SEC-MGT | 10.1.200.6 | No |
| SEC-EXT-FW-01 | VPN | Open_VPN | 10.10.200.5 | No |
| SEC-INT-FW-01 | 7 backends | 10.1.20–10.1.80 | Q1 | **Check (Q1)** |
| SEC-INT-FW-01 | Toward external FW | INT-SEC-MGT, assumed | Q2 | Q2 |

Product and config export: Q5.

## 7. NSX gateway firewall (Tier-1)

As given: allow SSH to .147, allow .21, internet out, default ingress allow, default drop. Export the exact rule table from NSX (Q13). In SDN these rules move to SEC-EXT-FW-01: there's no gateway firewall and no Port ACL on Pattern B.

## 8. NAT rules (enabled)

| # | Type | Public IP | Protocol | Port | Internal IP | Notes |
|---|---|---|---|---|---|---|
| 1 | DNAT | 198.51.100.36 | TCP | 30482 | 10.1.40.55 | K8s NodePort on the master |
| 2 | DNAT | 198.51.100.36 | TCP + UDP | 30479 | 10.1.40.55 | K8s NodePort on the master |
| 3 | DNAT | 198.51.100.36 | TCP | 443 | 10.1.70.55 | |
| 4 | DNAT | 198.51.100.36 | TCP | 80 | 10.1.70.55 | |
| 5 | DNAT | 198.51.100.36 | TCP | 1883 | 10.1.70.55 | MQTT |
| 6 | DNAT | 198.51.100.36 | TCP | 8000 | 10.1.20.55 | |
| 7 | DNAT | 198.51.100.147 | TCP | 22 | 10.1.20.55 | |
| 8 | DNAT | 198.51.100.21 | **Any** | Any | 10.10.200.10 | OpenVPN: explicit ports needed (Q4). The VM is powered off today |
| 9 | SNAT | 198.51.100.21 | – | – | 10.1.200.0/24 | |
| 10 | SNAT | 198.51.100.21 | – | – | 10.10.10.0/24 | |

The backend subnets have no SNAT on Tier-1: the external firewall NATs them to its own IP. This is why the design is symmetric.

**Disabled rules:** not migrated unless the customer asks. Exact list: export from NSX (Q13).

## 9. Public IPs

| Public IP | Used for | Fits `IPP-PublicVIP`? |
|---|---|---|
| 198.51.100.21 | SNAT + OpenVPN | Q8 |
| 198.51.100.36 | Services | Q8 |
| 198.51.100.147 | SSH | Q8 |

## 10. VPN and routing

| Item | Value |
|---|---|
| NSX IPsec | None |
| FortiGate L3 | None |
| In-guest VPN VM | OpenVPN (Ubuntu) 10.10.200.10. Port/protocol and client pool: Q4 |
| Static routes on Tier-1 | 10.0.0.0/8 and 10.10.200.0/24 via 10.10.10.10 |
| Load balancers | Open: the `Loadbalancer` VM is the customer's. Any NSX LB: Q13 |

## 11. Open questions

| # | Question | Owner | Blocks | Answer | Date |
|---|---|---|---|---|---|
| Q1 | SEC-INT-FW-01 interface IP in each of the 7 backend subnets, and the default gateway configured in each backend VM. If a firewall interface is the subnet's first IP, it must change | CustomerA | UDR, 9.2 | | |
| Q2 | Does SEC-INT-FW-01 have an interface in INT-SEC-MGT (10.1.200.0/24) to reach the external firewall 10.1.200.6? If not, how does backend traffic reach it? | CustomerA | UDR | | |
| Q3 | Open_VPN segment: 10.10.100.0/24 (NSX) or 10.10.200.0/24 (VM + firewall IPs)? Working assumption: 10.10.200.0/24. The export puts the OpenVPN VM on a network called **`Openvpn`**, not `Open_VPN`: are these **two** networks (Tier-1 segment 10.10.100.0/24, and an isolated 10.10.200.0/24)? If so, is the Tier-1 one used by anything? | Provider / CustomerA | Subnet list | | |
| Q4 | OpenVPN port/protocol (DNAT "Any" today, typically UDP 1194) and its client pool. Is it NATed by the VM or routed? | CustomerA | NAT, UDR | | |
| Q5 | Firewall product on both FreeBSD VMs, and a config export of both | CustomerA | Migration, DNAT | | |
| Q6 | Powered-off VMs (OpenVPN, Lora-Network, CADNS): migrate or not? OpenVPN off means rule 8 is unused today | CustomerA | Waves, NAT | | |
| Q7 | Downtime window, rollback period, contacts, who tests the applications | CustomerA / PM | Cutover | | |
| Q8 | When does NSX stop advertising the 3 public IPs and our MUX start? Are they inside `IPP-PublicVIP`, and is the router filter updated? | The provider network team | Cutover | | |
| Q9 | MongoDB: data size and acceptable downtime | CustomerA | Waves | | |
| Q10 | Firmware (BIOS/UEFI), MAC, gateway, DNS of every VM, disk bus (no IDE). OS, vCPU, RAM and disk are answered (§5) | Provider | Generation | | |
| Q11 | vCenter/ESXi version and datastore type | Provider | Tool choice | | |
| Q12 | CADNS IP. What's the prefix of **INT-INF-SRV**: is it 10.1.80.0/24 (listed as "LB"), or a 12th network? Which DNS servers do the VMs use? **Must close before the VM network is created:** adding a subnet later triggers L28 | CustomerA / Provider | Subnet list, pools | | |
| Q13 | NSX export: exact gateway firewall rules, disabled NAT rules, any NSX LB | Provider | Firewall config | | |
| Q14 | Does either firewall use port 22 on 10.10.10.10 for its own management? It would clash with the SSH rule (01 Networking §6) | CustomerA | DNAT | | |
| Q15 | SEC-INT-MGT-01 internet traffic goes through SEC-EXT-FW-01 in SDN (today it uses Tier-1 SNAT directly). Accepted? | CustomerA | UDR | | |
| Q16 | CustomerA-Private-Network (10.10.1.0/24): no VM, no firewall NIC, only disabled NAT rules. Is it needed? If yes, a firewall must get a NIC there (UDR next hops must be in the same subnet). Until answered: no VM on this subnet | CustomerA | Subnet use | | |
| Q17 | How do admins and monitoring reach each firewall? L29: only through the firewall's IP in their own subnet | CustomerA | Firewall config | | |
| Q18 | ESXi management NIC speed used for VMM conversion, and the datastore read speed | Provider | Window size | | |

---

## Gate (9.1)

> Record the results in `05 As-Built.md`.

- Q1–Q18 answered, or an owner and date set.
- No "Any" left in the NAT table.
