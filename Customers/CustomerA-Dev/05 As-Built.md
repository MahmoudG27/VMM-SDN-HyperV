# CustomerA Dev – 05 As-Built

> Filled in during execution. **No secrets**: vault entry names only. Gates: 9.0–9.6.

## 1. Gates

| Gate | Date | Result | Notes |
|---|---|---|---|
| 9.0 Overview | | | |
| 9.1 Intake | | | |
| 9.2 Networking | | | |
| 9.3 Cloud | | | |
| 9.4 Migration | | | |
| 9.5 Cutover | | | |
| 9.6 UDR operations (incl. L28 drill) | | | |

## 2. Network

| Item | Value |
|---|---|
| VM network / `ExternalId` (NC resource ID) | `CustomerA-Dev-Net` / |
| Open_VPN prefix (Q3) | |
| SEC-INT-FW-01 IPs (Q1, Q2) | |
| Apply script version (git commit) | |
| OpenVPN port / client pool (Q4) | |

## 3. Public IPs

| Public IP | Object | MUX advertising (date) | NSX stopped (date) |
|---|---|---|---|
| 198.51.100.21 | `CustomerA-Dev-NAT` | | |
| 198.51.100.36 | VIPs | | |
| 198.51.100.147 | VIP | | |

## 4. VMs

| VM | Host / CSV | Gen | Disks | IP | Converted (date, duration) | Tools removed | Notes |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

## 5. Operations

| Item | Result |
|---|---|
| UDR guard running | |
| VIP backend check clean | |
| Backups configured | |
| Monitoring added | |
| Rollback period ended (date) | |
| VMware VMs deleted, NSX objects released (date) | |

## 6. Pilot answers (first real run of 9.x)

| To be verified | Answer |
|---|---|
| NC property names in the script | |
| VMM role `SDN-UDR-Read` can read `ExternalId` | |
| On-link firewall next hop vs UDR on INT-SEC-MGT | |
| Does a NAT connection advertise immediately? | |
| Second NAT connection on one VM network | |
| Outbound NAT on .21 combined with SEC-EXT-FW-01's own SNAT (lab used an L3 connection) | |
| 7 SLB VIPs on .36 with different ports (lab used one VIP per IP) | |
| FreeBSD / CentOS / Ubuntu conversion by VMM | |
| Conversion throughput (GB/h) | |
| `Set-SCCloud` Tag / Cost Center | |

## 7. Change log

| Date | File / step | Who | What | Gate result |
|---|---|---|---|---|
| | | | | |
