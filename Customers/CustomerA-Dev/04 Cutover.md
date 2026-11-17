# CustomerA Dev – 04 Cutover

> Procedure: 9.5. This file holds CustomerA's values only.

| Item | Value |
|---|---|
| Window | Q7 |
| Rollback deadline | Q7 |
| Testers | Q7 |
| The provider network contact | Q8 |
| Test client outside HNV-PA (L27) | `<test-client>` |
| Public /32s to move | 198.51.100.21, 198.51.100.36, 198.51.100.147 |
| From | NSX Tier-0 `D-VRF-CustomerA` (AS 65000 peers 10.212.47.68/31, 10.212.48.68/31) |
| To | MUX01, MUX02 (8.7) |

## Cutover gates

Go through these in order. Stop if one fails.

| # | Gate | How | Result |
|---|---|---|---|
| 1 | All migrating VMs running, waves complete | 03 Migration-Waves | |
| 2 | **UDR guard running** | `Get-ScheduledTaskInfo "SDN - UDR Guard"` on MGMT01 | |
| 3 | `No drift` | `Apply-CustomerA-Dev-UDR.ps1 -CheckOnly` | |
| 4 | SEC-EXT-FW-01 config in place (01 Networking §6 actions) | CustomerA / Provider | |
| 5 | NSX stopped advertising the 3 /32s | Router, provider | |
| 6 | NAT connection and 8 VIPs created (.21 rule per Q4/Q6) | 01 Networking §6 | |
| 7 | **VIP backend check**: exit 0, no `FINDING` | `Apply-CustomerA-Dev-UDR.ps1 -CheckOnly` | |
| 8 | Each /32 via both MUX | Router, provider | |
| 9 | Application tests | Testers | |

## Public port tests (from outside HNV-PA, new connection each time)

| Public IP | Port | Protocol | Expected | Result |
|---|---|---|---|---|
| .36 | 443 | TCP | Loadbalancer | |
| .36 | 80 | TCP | Loadbalancer | |
| .36 | 1883 | TCP (MQTT) | Loadbalancer | |
| .36 | 8000 | TCP | Agents_restore2 | |
| .36 | 30482 | TCP | K8s master | |
| .36 | 30479 | TCP + UDP | K8s master | |
| .147 | 22 | TCP | Agents_restore2 | |
| .21 | 1194 (Q4) | UDP | OpenVPN, if migrated (Q6) | |
| Outbound | – | – | Backend VM reaches the internet as .21 | |

Disable the rule on the firewall for one port: it must stop (the firewall is really in the path, L26).

## Rollback

Per 9.5 §3. VMware VMs stay powered off until `<rollback-end-date>`.

---

## Gate (9.5)

> Record the results in `05 As-Built.md`.

- All cutover gates passed, including **UDR guard running** and **VIP backend check**.
- Customer sign-off.
