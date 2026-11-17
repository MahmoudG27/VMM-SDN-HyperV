# CustomerA Dev – 01 Networking

> Procedure: 9.2 and 9.6. **Pattern B.** Questions Qn: `00 Intake.md` §11.
> ⚠️ marks a value or route that depends on an open question.

## 1. Design summary

| Item | Decision |
|---|---|
| VM network | `CustomerA-Dev-Net` on `HNV-PA`, Hyper-V Network Virtualization, 11 subnets |
| Firewalls | SEC-EXT-FW-01 and SEC-INT-FW-01 stay in the path through UDR |
| RAS Gateway | **None**: the VPN is the customer's own VM |
| Port ACLs | **None** (Pattern B) |
| Public IPs | 198.51.100.21 / .36 / .147, all inbound to **SEC-EXT-FW-01 10.10.10.10 only** (L26) |
| Tier-1 NAT + gateway firewall | Move into SEC-EXT-FW-01's config (§6, customer/provider action) |

## 2. VM subnets and pools

Default gateway = first IP, answered by the distributed router. Pools from `.2` (L15). Create **all 11 at the start** (L28).

| # | VM subnet | NSX source | Prefix | Gateway | Pool `IPP-…` | Range |
|---|---|---|---|---|---|---|
| 1 | `CustomerA-Dev-INT-SEC-MGT` | Segment | 10.1.200.0/24 | 10.1.200.1 | `IPP-CustomerA-Dev-INT-SEC-MGT` | .2–.254 |
| 2 | `CustomerA-Dev-OUT-OUT-FW` | Segment | 10.10.10.0/24 | 10.10.10.1 | `IPP-CustomerA-Dev-OUT-OUT-FW` | .2–.254 |
| 3 | `CustomerA-Dev-Open_VPN` | Segment ⚠️ Q3 | 10.10.200.0/24 | 10.10.200.1 | `IPP-CustomerA-Dev-Open_VPN` | .2–.254 |
| 4 | `CustomerA-Dev-Private` | Segment | 10.10.1.0/24 | 10.10.1.1 | `IPP-CustomerA-Dev-Private` | .2–.254 |
| 5 | `CustomerA-Dev-Agent` | Backend | 10.1.20.0/24 | 10.1.20.1 | `IPP-CustomerA-Dev-Agent` | .2–.254 |
| 6 | `CustomerA-Dev-Chef` | Backend | 10.1.30.0/24 | 10.1.30.1 | `IPP-CustomerA-Dev-Chef` | .2–.254 |
| 7 | `CustomerA-Dev-K8s` | Backend | 10.1.40.0/24 | 10.1.40.1 | `IPP-CustomerA-Dev-K8s` | .2–.254 |
| 8 | `CustomerA-Dev-MongoDB` | Backend | 10.1.50.0/24 | 10.1.50.1 | `IPP-CustomerA-Dev-MongoDB` | .2–.254 |
| 9 | `CustomerA-Dev-Core` | Backend | 10.1.60.0/24 | 10.1.60.1 | `IPP-CustomerA-Dev-Core` | .2–.254 |
| 10 | `CustomerA-Dev-LB70` | Backend | 10.1.70.0/24 | 10.1.70.1 | `IPP-CustomerA-Dev-LB70` | .2–.254 |
| 11 | `CustomerA-Dev-LB80` | Backend | 10.1.80.0/24 | 10.1.80.1 | `IPP-CustomerA-Dev-LB80` | .2–.254 |

- DNS on the pools: ⚠️ Q12.
- **Open_VPN assumption A1:** the subnet is 10.10.200.0/24, because the OpenVPN VM, the firewall interface and the Tier-1 static route all use it. If Q3 changes it, edit this table and the script **before** creating the VM network.
- **Backend gateways:** every VM uses the subnet's `.1`, whatever it uses in NSX. If SEC-INT-FW-01 uses `.1` in a subnet (⚠️ Q1), its interface changes, because SDN reserves that IP.

```powershell
# MGMT01 (VMM PowerShell) – 9.2 §2 with CustomerA values; compare with View Script
$ln  = Get-SCLogicalNetwork -Name "HNV-PA"
$vmn = New-SCVMNetwork -Name "CustomerA-Dev-Net" -LogicalNetwork $ln -IsolationType "WindowsNetworkVirtualization" `
       -Description "PATTERN B: after ANY subnet change run Apply-CustomerA-Dev-UDR.ps1 (9.6)"
$tiers = [ordered]@{
    "INT-SEC-MGT" = "10.1.200"; "OUT-OUT-FW" = "10.10.10"; "Open_VPN" = "10.10.200"; "Private" = "10.10.1"
    "Agent" = "10.1.20"; "Chef" = "10.1.30"; "K8s" = "10.1.40"; "MongoDB" = "10.1.50"
    "Core" = "10.1.60"; "LB70" = "10.1.70"; "LB80" = "10.1.80"
}
foreach ($t in $tiers.Keys) {
    $n   = $tiers[$t]
    $sv  = New-SCSubnetVLan -Subnet "$n.0/24"
    $sub = New-SCVMSubnet -Name "CustomerA-Dev-$t" -VMNetwork $vmn -SubnetVLan $sv
    New-SCStaticIPAddressPool -Name "IPP-CustomerA-Dev-$t" -VMSubnet $sub -Subnet "$n.0/24" `
        -IPAddressRangeStart "$n.2" -IPAddressRangeEnd "$n.254" `
        -DefaultGateway (New-SCDefaultGateway -IPAddress "$n.1" -Automatic) -DNSServer "<customera-dns>"   # Q12
}
```

NC resource ID: `Apply-CustomerA-Dev-UDR.ps1` reads it from `(Get-SCVMNetwork -Name "CustomerA-Dev-Net").ExternalId` (9.6).

- **Subnet list isn't final until Q3 and Q12 close.** The export shows a network `INT-INF-SRV` (CADNS) with no known prefix: it's either 10.1.80.0/24 or a 12th subnet. A subnet added after the UDRs exist triggers L28.

## 3. Firewall interface plan

| Firewall | NIC | VM subnet | IP | Role | Status |
|---|---|---|---|---|---|
| SEC-EXT-FW-01 | 1 | OUT-OUT-FW | 10.10.10.10 | External. Backend of every VIP/NAT rule | Known |
| SEC-EXT-FW-01 | 2 | INT-SEC-MGT | 10.1.200.6 | Toward SEC-INT-FW-01 and management | Known |
| SEC-EXT-FW-01 | 3 | Open_VPN | 10.10.200.5 | Toward OpenVPN | ⚠️ Q3 |
| SEC-INT-FW-01 | 1 | Agent | `<intfw-ip-10.1.20>` | Backend | ⚠️ Q1 |
| SEC-INT-FW-01 | 2 | Chef | `<intfw-ip-10.1.30>` | Backend | ⚠️ Q1 |
| SEC-INT-FW-01 | 3 | K8s | `<intfw-ip-10.1.40>` | Backend | ⚠️ Q1 |
| SEC-INT-FW-01 | 4 | MongoDB | `<intfw-ip-10.1.50>` | Backend | ⚠️ Q1 |
| SEC-INT-FW-01 | 5 | Core | `<intfw-ip-10.1.60>` | Backend | ⚠️ Q1 |
| SEC-INT-FW-01 | 6 | LB70 | `<intfw-ip-10.1.70>` | Backend | ⚠️ Q1 |
| SEC-INT-FW-01 | 7 | LB80 | `<intfw-ip-10.1.80>` | Backend | ⚠️ Q1 |
| SEC-INT-FW-01 | 8 | INT-SEC-MGT | `<intfw-ip-10.1.200>` | Toward SEC-EXT-FW-01 | ⚠️ Q2 |

**SEC-INT-FW-01 has 8 NICs: within the Hyper-V limit** on a Windows Server 2025 host: 64 standard adapters on Gen 2, 8 standard + 4 legacy on Gen 1 ([Hyper-V maximum scale limits](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/maximum-scale-limits)). If the VM is **Gen 1** (BIOS, Q10) it's exactly at the 8-standard limit, so a 12th network behind this firewall (⚠️ Q12) would need a 9th NIC, and Gen 1 has no standard slot left for it. In that case the path is the 9.4 §1 alternative (new Gen 2 appliance + config import), not conversion. Microsoft's NVA page also notes multi-NIC appliances need each interface known to NC; VMM does this for VM network NICs, *to be verified*.
**Firewall routing inside the guests:** IP forwarding on. SEC-INT-FW-01 default route → 10.1.200.6. SEC-EXT-FW-01 default route → 10.10.10.1, and routes for the 7 backends → `<intfw-ip-10.1.200>`.

## 4. UDR desired state

Source of truth: `Apply-CustomerA-Dev-UDR.ps1`. Next hop type `VirtualAppliance` for all routes.

| Route table | Subnet | Routes | Next hop | Status |
|---|---|---|---|---|
| `CustomerA-Dev-RT-Agent` | 10.1.20.0/24 | All 10 other subnets + 0.0.0.0/0 | `<intfw-ip-10.1.20>` | ⚠️ Q1 |
| `CustomerA-Dev-RT-Chef` | 10.1.30.0/24 | same | `<intfw-ip-10.1.30>` | ⚠️ Q1 |
| `CustomerA-Dev-RT-K8s` | 10.1.40.0/24 | same | `<intfw-ip-10.1.40>` | ⚠️ Q1 |
| `CustomerA-Dev-RT-MongoDB` | 10.1.50.0/24 | same | `<intfw-ip-10.1.50>` | ⚠️ Q1 |
| `CustomerA-Dev-RT-Core` | 10.1.60.0/24 | same | `<intfw-ip-10.1.60>` | ⚠️ Q1 |
| `CustomerA-Dev-RT-LB70` | 10.1.70.0/24 | same | `<intfw-ip-10.1.70>` | ⚠️ Q1 |
| `CustomerA-Dev-RT-LB80` | 10.1.80.0/24 | same | `<intfw-ip-10.1.80>` | ⚠️ Q1 |
| `CustomerA-Dev-RT-INT-SEC-MGT` | 10.1.200.0/24 | 7 backend prefixes | `<intfw-ip-10.1.200>` | ⚠️ Q2 |
| | | 10.10.200.0/24, 10.10.10.0/24, 10.10.1.0/24, 0.0.0.0/0 | 10.1.200.6 | ⚠️ Q2, Q15 |
| `CustomerA-Dev-RT-Open_VPN` | 10.10.200.0/24 | All 10 other subnets + 0.0.0.0/0 | 10.10.200.5 | ⚠️ Q3 |
| *(none)* | 10.10.10.0/24 | **No route table** (lab result 4) | – | Decided |
| *(none)* | 10.10.1.0/24 | **No route table:** no firewall has a NIC here, and a next hop must be in the same subnet | – | ⚠️ Q16. **No VM on this subnet until Q16 closes** |

**Why each decision:**

1. **Every other subnet is listed, not only the backends and 0.0.0.0/0** (lab-verified, T1). With `0.0.0.0/0` only, traffic to another subnet of the VNet goes directly via `.1`. Without 10.1.200.0/24, 10.10.10.0/24, 10.10.200.0/24 and 10.10.1.0/24 in the backend tables, a backend would reach those subnets through the distributed router, around SEC-INT-FW-01.
2. **INT-SEC-MGT holds both firewalls.** It needs routes because SDN forwards by IP route: a firewall's static route with an on-link next hop may not be honoured the way it is on a real L2 network. So the UDR on this subnet is what carries firewall-to-firewall traffic (*to be verified*). Backends → SEC-INT-FW-01 and everything else → SEC-EXT-FW-01.
3. **No loop on INT-SEC-MGT.** SEC-EXT-FW-01 sends backend traffic out of 10.1.200.6, which the UDR sends to SEC-INT-FW-01. SEC-INT-FW-01 sends internet traffic out of its INT-SEC-MGT NIC, which the UDR sends to 10.1.200.6. Neither firewall sends traffic back out of the NIC it arrived on for the same prefix, as long as their own routes follow §3.
4. **OUT-OUT-FW has no route table** (lab result 4). Only SEC-EXT-FW-01 is on it. A 0.0.0.0/0 there would loop.
5. **Open_VPN** behaves like today: 10.10.200.0/24 is reached only through SEC-EXT-FW-01 (Tier-1 static route today).
6. **VPN client pool:** today's Tier-1 route covers 10.10.200.0/24. If the real client pool is a different prefix (⚠️ Q4) and isn't NATed by the VM, add `<vpn-client-pool>` → 10.10.200.10 to `CustomerA-Dev-RT-Open_VPN`, and → 10.1.200.6 / backend firewall IPs elsewhere.
7. **SEC-INT-MGT-01 behaviour changes** (⚠️ Q15): to backends it goes straight to SEC-INT-FW-01, and to the internet through SEC-EXT-FW-01, which replaces the direct Tier-1 SNAT.
8. **SDN outbound NAT covers the whole VM network**, wider than NSX (SNAT only for 2 subnets). In practice all traffic reaches it from 10.10.10.10, since every other subnet routes to a firewall.
9. **Next hops are always in the route table's own subnet** (design rule, T2 inconclusive). All 9 tables follow it, and the script refuses anything else. That's why CustomerA-Private-Network has no route table: if Q16 keeps it, a firewall gets a NIC there and a table is added.

## 5. Path check (every flow symmetric)

| Flow | Forward | Return | OK? |
|---|---|---|---|
| Backend → backend (Agent → K8s) | 10.1.20.55 → RT-Agent → SEC-INT-FW-01 → K8s NIC → 10.1.40.55 | 10.1.40.55 → RT-K8s → SEC-INT-FW-01 → Agent NIC | Yes |
| Backend → internet | Backend → RT → SEC-INT-FW-01 → INT-SEC-MGT NIC → UDR → 10.1.200.6 → SNAT to 10.10.10.10 → `.1` → outbound NAT .21 | Reverse | Yes, ⚠️ Q2 |
| Internet → .36:443 | MUX → 10.10.10.10 → DNAT → 10.1.200.6 → UDR → SEC-INT-FW-01 → 10.1.70.55 | 10.1.70.55 → RT-LB70 → SEC-INT-FW-01 → UDR → 10.1.200.6 → 10.10.10.10 → DSR to the client | Yes (lab result 4) |
| SEC-INT-MGT-01 → backend | .250 → RT-INT-SEC-MGT → SEC-INT-FW-01 → backend | Backend → RT → SEC-INT-FW-01 → INT-SEC-MGT on-link | Yes, ⚠️ Q2 |
| SEC-INT-MGT-01 → internet | .250 → RT-INT-SEC-MGT 0/0 → 10.1.200.6 → SNAT → outbound NAT | Reverse | Yes, ⚠️ Q15 |
| VPN client → backend | Client → .21:1194 → 10.10.10.10 → DNAT → 10.10.200.5 → 10.10.200.10; decrypted → RT-Open_VPN → 10.10.200.5 → 10.1.200.6 → SEC-INT-FW-01 → backend | Reverse | Yes, ⚠️ Q3, Q4 |

**Firewall access (L29):** a firewall answers on its own IP only from the NIC that owns it. Use its IP in **your own** subnet (⚠️ Q17):

| From | SEC-EXT-FW-01 | SEC-INT-FW-01 |
|---|---|---|
| SEC-INT-MGT-01 (10.1.200.250) | 10.1.200.6 ✅ · 10.10.10.10 / 10.10.200.5 ❌ | `<intfw-ip-10.1.200>` ✅ · its backend IPs ❌ |
| OpenVPN (10.10.200.10) | 10.10.200.5 ✅ | – |
| A backend VM | – | Its interface in that backend subnet ✅ |

The ❌ cases aren't faults: don't troubleshoot them. Forwarded traffic isn't affected, and neither is the firewall's own NAT, because 10.10.10.10 leaves the NIC that owns it.

## 6. Public IPs, VIPs and NAT

Created **in the cutover window** (9.2 §4, 04 Cutover). All inbound → **10.10.10.10**, never a backend (L26).

| Public IP | Mechanism | Protocol | Port | Backend | Then SEC-EXT-FW-01 DNATs to |
|---|---|---|---|---|---|
| 198.51.100.21 | **NAT connection** `CustomerA-Dev-NAT` (outbound NAT) | – | – | – | – |
| 198.51.100.21 | NAT rule ⚠️ Q4, Q6 | UDP | 1194 | 10.10.10.10:1194 | 10.10.200.10:1194 |
| 198.51.100.36 | VIP `CustomerA-Dev-VIP-36-30482-tcp` | TCP | 30482 | 10.10.10.10 | 10.1.40.55 |
| 198.51.100.36 | VIP `CustomerA-Dev-VIP-36-30479-tcp` | TCP | 30479 | 10.10.10.10 | 10.1.40.55 |
| 198.51.100.36 | VIP `CustomerA-Dev-VIP-36-30479-udp` | UDP | 30479 | 10.10.10.10 | 10.1.40.55 |
| 198.51.100.36 | VIP `CustomerA-Dev-VIP-36-443-tcp` | TCP | 443 | 10.10.10.10 | 10.1.70.55 |
| 198.51.100.36 | VIP `CustomerA-Dev-VIP-36-80-tcp` | TCP | 80 | 10.10.10.10 | 10.1.70.55 |
| 198.51.100.36 | VIP `CustomerA-Dev-VIP-36-1883-tcp` | TCP | 1883 | 10.10.10.10 | 10.1.70.55 |
| 198.51.100.36 | VIP `CustomerA-Dev-VIP-36-8000-tcp` | TCP | 8000 | 10.10.10.10 | 10.1.20.55 |
| 198.51.100.147 | VIP `CustomerA-Dev-VIP-147-22-tcp` | TCP | 22 | 10.10.10.10 | 10.1.20.55 |

- **.36 and .147 use SLB VIPs** because Microsoft's NAT procedure shows one IP per NAT connection. If the pilot shows one VM network accepts more NAT connections, inbound NAT rules are an alternative. *To be verified.*
- The firewall receives VIP traffic as 10.10.10.10:`<port>` (lab-verified: VIP 40.40.40.11 → FW1 10.0.2.10:80 → A1), so the DNAT keys on the port. All ports above are unique across the 3 public IPs, so this works. Port 22 must not also be the firewall's own management on 10.10.10.10 (⚠️ Q14).
- The 8 VIP templates are generic (one per port/protocol, Microsoft Network Controller, Custom TCP/UDP): 8.7 §6. UDP templates have no health monitor.
- The 3 IPs must be inside `IPP-PublicVIP` (⚠️ Q8).

**Customer/provider actions on SEC-EXT-FW-01** (in the firewall config, before cutover):

| # | Action | Owner |
|---|---|---|
| 1 | Add the DNAT rules in the last column | CustomerA / Provider |
| 2 | Add the Tier-1 gateway firewall rules (allow SSH, allow VPN, internet out, default drop). The firewall is now the only filter | CustomerA / Provider |
| 3 | Default route → 10.10.10.1, routes per §3 | CustomerA / Provider |
| 4 | SNAT the backends to 10.10.10.10 (as today), plus INT-SEC-MGT (⚠️ Q15) | CustomerA / Provider |
| 5 | VMs on OUT-OUT-FW/INT-SEC-MGT: remove any dependency on Tier-1 NAT | CustomerA / Provider |

## 7. Overlapping ranges

CustomerA uses 10.10.100.0/24 (NSX, ⚠️ Q3) and 10.10.200.0/24, the same as our Management and HNV-PA **placeholders** in 0.0 §3.
This is allowed: tenant addresses live inside the overlay. It must never be routed toward the fabric management network (L13): no RAS Gateway connection on this VM network.

```powershell
# MGMT01 (VMM PowerShell) – must return nothing: no VPN/L3 connection on CustomerA-Dev-Net
$vmn = Get-SCVMNetwork -Name "CustomerA-Dev-Net"
Get-SCVMNetworkGateway -VMNetwork $vmn | ForEach-Object { Get-SCVPNConnection -VMNetworkGateway $_ }
```

From a CustomerA VM, a fabric management IP (e.g. DC01) must not answer. Test this if the real ranges still overlap.

## 8. Build order

| # | Step | When |
|---|---|---|
| 1 | Close Q1–Q5, Q12, Q15, Q16 | Before anything |
| 2 | VM network, all subnets, pools (§2) | Pre-cutover |
| 3 | Fill the script's firewall IPs (the resource ID comes from VMM) | Pre-cutover |
| 4 | Firewall VMs on Hyper-V with all NICs (03 Migration-Waves) | Window |
| 5 | Apply script, `No drift`, guard on (9.6) | Before the first backend VM |
| 6 | L28 drill (Gate 9.6) | Before public IPs |
| 7 | NAT + VIPs (§6) | Cutover, after NSX stops advertising |

---

## Gate (9.2)

> Record the results in `05 As-Built.md`.

- All subnets, pools from `.2`, gateway `.1`, `ExternalId` returned by VMM.
- No placeholder left in `Apply-CustomerA-Dev-UDR.ps1`. Apply run, `No drift`.
- `tracert` from a backend to **each** other subnet: `.1`, then SEC-INT-FW-01.
- §5 paths tested in both directions.
- L29: each firewall reachable on its IP in the tester's own subnet. Monitoring and admin access use those IPs.
- No VM on CustomerA-Private-Network unless Q16 added a firewall NIC and a route table.
- §7 check returns nothing.
- Public tests from outside HNV-PA (L27), at cutover.
