<#
.SYNOPSIS
    Reconciles the SDN user-defined routes (UDR) of one Pattern B customer. Idempotent.
    Procedure, rules and guard: Production-Runbook\9.6 Customer-UDR-Operations.

.PARAMETER CheckOnly
    Reports drift, changes nothing.

.PARAMETER Credential
    NC REST credential. Omit it to use the current identity (guard task).

.PARAMETER VNetResourceId
    Only where the VMM module isn't available (an NC node). Otherwise the ID comes from VMM.

.NOTES
    Exit codes: 0 = OK (no drift, or drift fixed)
                1 = error
                2 = drift found (-CheckOnly only)
                3 = policy finding (VIP backend not the firewall, or a Port ACL). Never fixed automatically.

    Interactive run (paste the Read-Host line on its own):
      $pw = Read-Host "svc-sdn password" -AsSecureString
      $cred = New-Object System.Management.Automation.PSCredential("CONTOSO\svc-sdn", $pw)
      .\Apply-CustomerA-Dev-UDR.ps1 -Credential $cred
#>
[CmdletBinding()]
param(
    [string]       $ConnectionUri = "https://ncrest.contoso.local",
    [pscredential] $Credential,
    [string]       $VNetResourceId,
    [string]       $VmmServer = "VMM01.contoso.local",
    [switch]       $CheckOnly
)
$ErrorActionPreference = "Stop"

# ===== DESIRED STATE (values only: edit this block, never the engine) =====

$Customer      = "CustomerA-Dev"
$VMNetworkName = "CustomerA-Dev-Net"                    # the NC resource ID comes from this VM network's ExternalId. Never identify a customer by prefix

# VIP / NAT backends allowed for this customer (L26): the external firewall only
$FirewallIPs    = @("10.10.10.10")

# SEC-INT-FW-01 interface per backend subnet (open question Q1) and in INT-SEC-MGT (Q2)
$IntFw = [ordered]@{
    "10.1.20.0/24" = @{ Name = "Agent";   Ip = "<intfw-ip-10.1.20>" }
    "10.1.30.0/24" = @{ Name = "Chef";    Ip = "<intfw-ip-10.1.30>" }
    "10.1.40.0/24" = @{ Name = "K8s";     Ip = "<intfw-ip-10.1.40>" }
    "10.1.50.0/24" = @{ Name = "MongoDB"; Ip = "<intfw-ip-10.1.50>" }
    "10.1.60.0/24" = @{ Name = "Core";    Ip = "<intfw-ip-10.1.60>" }
    "10.1.70.0/24" = @{ Name = "LB70";    Ip = "<intfw-ip-10.1.70>" }
    "10.1.80.0/24" = @{ Name = "LB80";    Ip = "<intfw-ip-10.1.80>" }
}
$IntFwInMgt  = "<intfw-ip-10.1.200>"               # Q2
$ExtFwInMgt  = "10.1.200.6"
$ExtFwInVpn  = "10.10.200.5"

$PfxMgt      = "10.1.200.0/24"                     # INT-SEC-MGT
$PfxVpn      = "10.10.200.0/24"                    # Open_VPN, working assumption A1 (Q3)
$PfxOut      = "10.10.10.0/24"                     # OUT-OUT-FW
$PfxPrivate  = "10.10.1.0/24"                      # CustomerA-Private-Network

# Every other subnet needs an explicit route: a VNet system route (/24) beats 0.0.0.0/0 by longest prefix,
# and a UDR only wins against a system route of the SAME length (Microsoft, lab-verified T1). See 01 Networking.md §4.
$AllPrefixes = @($IntFw.Keys) + @($PfxMgt, $PfxVpn, $PfxOut, $PfxPrivate)

function New-AllRoutes([string] $OwnPrefix, [string] $NextHop) {
    foreach ($p in $AllPrefixes) { if ($p -ne $OwnPrefix) { @{ Prefix = $p; NextHop = $NextHop } } }
    @{ Prefix = "0.0.0.0/0"; NextHop = $NextHop }
}

$RouteTables = [ordered]@{}
$SubnetMap   = [ordered]@{}

# 7 backend subnets: everything -> SEC-INT-FW-01's interface in that subnet
foreach ($p in $IntFw.Keys) {
    $rt = "$Customer-RT-$($IntFw[$p].Name)"
    $RouteTables[$rt] = @(New-AllRoutes $p $IntFw[$p].Ip)
    $SubnetMap[$p]    = $rt
}

# INT-SEC-MGT (both firewalls + SEC-INT-MGT-01): backends -> SEC-INT-FW-01, everything else -> SEC-EXT-FW-01
$rtMgt = "$Customer-RT-INT-SEC-MGT"
$RouteTables[$rtMgt] = @(
    foreach ($p in $IntFw.Keys) { @{ Prefix = $p; NextHop = $IntFwInMgt } }
    @{ Prefix = $PfxVpn;     NextHop = $ExtFwInMgt }
    @{ Prefix = $PfxOut;     NextHop = $ExtFwInMgt }
    @{ Prefix = $PfxPrivate; NextHop = $ExtFwInMgt }
    @{ Prefix = "0.0.0.0/0"; NextHop = $ExtFwInMgt }
)
$SubnetMap[$PfxMgt] = $rtMgt

# Open_VPN (OpenVPN VM + SEC-EXT-FW-01): everything -> SEC-EXT-FW-01's interface in this subnet
$rtVpn = "$Customer-RT-Open_VPN"
$RouteTables[$rtVpn] = @(New-AllRoutes $PfxVpn $ExtFwInVpn)
$SubnetMap[$PfxVpn]  = $rtVpn

# CustomerA-Private-Network: NO route table. A next hop must be a firewall IP in the SAME subnet, and no firewall has a NIC here.
# No VM may be placed on this subnet until Q16 is answered: it would reach every subnet around the firewalls.
$SubnetMap[$PfxPrivate] = $null

# OUT-OUT-FW: the external firewall's transit subnet has NO route table (lab result 4)
$SubnetMap[$PfxOut] = $null

# ===== ENGINE (same in every customer script: Production-Runbook\9.6) =====

function Get-RouteKey([string] $Prefix, [string] $NextHop) { ("{0}|virtualappliance|{1}" -f $Prefix, $NextHop).ToLowerInvariant() }

function Test-IpInPrefix([string] $Ip, [string] $Prefix) {
    $net, $len = $Prefix -split '/'
    $toInt = { param($a) $b = [System.Net.IPAddress]::Parse($a).GetAddressBytes(); [Array]::Reverse($b); [BitConverter]::ToUInt32($b, 0) }
    $mask  = if ([int]$len -eq 0) { [uint32]0 } else { [uint32]([uint64]4294967295 -band ([uint64]4294967295 -shl (32 - [int]$len))) }
    ((& $toInt $Ip) -band $mask) -eq ((& $toInt $net) -band $mask)
}

$placeholders = @($FirewallIPs) + @($RouteTables.Values | ForEach-Object { $_ } | ForEach-Object { $_.NextHop })
$open = @($placeholders | Where-Object { $_ -match '<' } | Sort-Object -Unique)
if ($open.Count -gt 0) { [Console]::Error.WriteLine("Desired state still has placeholders: $($open -join ', ')"); exit 1 }

# Design rule: the next hop is always the firewall's IP in the SAME subnet as the route table
$outside = @(foreach ($p in $SubnetMap.Keys) {
    if ($SubnetMap[$p]) {
        foreach ($r in $RouteTables[$SubnetMap[$p]]) { if (-not (Test-IpInPrefix $r.NextHop $p)) { "$($SubnetMap[$p]): $($r.NextHop) isn't in $p" } }
    }
})
if ($outside.Count -gt 0) { [Console]::Error.WriteLine("Next hop outside the subnet: $(($outside | Sort-Object -Unique) -join '; ')"); exit 1 }

try {
    Import-Module NetworkController       # before any New-Object Microsoft.Windows.NetworkController.* (L23)

    $nc = @{ ConnectionUri = $ConnectionUri }
    if ($Credential) { $nc.Credential = $Credential }

    # VMM VM network ExternalId = NC virtual network resource ID (lab-verified). The last good ID is cached,
    # so the guard keeps working while the VMM service is stopped by the nightly backup (8.4 §7)
    if (-not $VNetResourceId) {
        $idCache = Join-Path $PSScriptRoot "$Customer.vnetid"
        try {
            Import-Module VirtualMachineManager
            [void](Get-SCVMMServer -ComputerName $VmmServer)
            $vmn = Get-SCVMNetwork -Name $VMNetworkName
            if (-not $vmn -or -not $vmn.ExternalId) { throw "VM network $VMNetworkName not found, or it has no ExternalId" }
            $VNetResourceId = "$($vmn.ExternalId)"
            Set-Content -Path $idCache -Value $VNetResourceId
        } catch {
            if (-not (Test-Path $idCache)) { throw }
            $VNetResourceId = (Get-Content $idCache -TotalCount 1).Trim()
            Write-Warning "VMM not reachable ($($_.Exception.Message)): using the cached resource ID $VNetResourceId"
        }
    }

    $vnet     = Get-NetworkControllerVirtualNetwork @nc -ResourceId $VNetResourceId
    $prefixes = @($vnet.Properties.Subnets | ForEach-Object { $_.Properties.AddressPrefix })
    $missing  = @($SubnetMap.Keys | Where-Object { $_ -notin $prefixes })
    if ($missing.Count -gt 0) { throw "VNet $VNetResourceId has no subnet $($missing -join ', '): wrong resource ID, or subnet not created yet" }

    $drift  = New-Object System.Collections.ArrayList
    $tables = @{}
    Get-NetworkControllerRouteTable @nc | ForEach-Object { $tables[$_.ResourceId] = $_ }

    # 1. Route tables
    foreach ($name in $RouteTables.Keys) {
        $want = @($RouteTables[$name] | ForEach-Object { Get-RouteKey $_.Prefix $_.NextHop } | Sort-Object)
        $have = @()
        if ($tables.ContainsKey($name)) {
            $have = @($tables[$name].Properties.Routes | ForEach-Object {
                "{0}|{1}|{2}" -f $_.Properties.AddressPrefix, $_.Properties.NextHopType, $_.Properties.NextHopIpAddress
            } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
        }
        if (($want -join ';') -eq ($have -join ';')) { continue }

        [void]$drift.Add("Route table $name differs from the desired state")
        if ($CheckOnly) { continue }

        $props = New-Object Microsoft.Windows.NetworkController.RouteTableProperties
        foreach ($r in $RouteTables[$name]) {
            $route = New-Object Microsoft.Windows.NetworkController.Route
            $route.ResourceId = $r.Prefix -replace '[./]', '_'
            $route.Properties = New-Object Microsoft.Windows.NetworkController.RouteProperties
            $route.Properties.AddressPrefix    = $r.Prefix
            $route.Properties.NextHopType      = "VirtualAppliance"
            $route.Properties.NextHopIpAddress = $r.NextHop
            $props.Routes += $route
        }
        [void](New-NetworkControllerRouteTable @nc -ResourceId $name -Properties $props -Force)
        $tables[$name] = Get-NetworkControllerRouteTable @nc -ResourceId $name
    }

    # 2. Subnet -> route table links (L28: VMM subnet changes remove them)
    $putNeeded = $false
    foreach ($s in $vnet.Properties.Subnets) {
        $prefix = $s.Properties.AddressPrefix
        if (-not $SubnetMap.Contains($prefix)) { Write-Warning "Subnet $prefix isn't in the desired state: add it to `$SubnetMap"; continue }
        $wantRt = $SubnetMap[$prefix]
        $haveRt = $null
        if ($s.Properties.RouteTable -and $s.Properties.RouteTable.ResourceRef) { $haveRt = ($s.Properties.RouteTable.ResourceRef -split '/')[-1] }
        if ($wantRt -eq $haveRt) { continue }

        [void]$drift.Add("Subnet $prefix has route table '$haveRt', desired '$wantRt'")
        if ($CheckOnly) { continue }
        if ($wantRt) { $s.Properties.RouteTable = $tables[$wantRt] } else { $s.Properties.RouteTable = $null }
        $putNeeded = $true
    }

    # 3. One PUT of the virtual network, only if a link changed (L25: each PUT re-programs the hosts)
    if ($putNeeded) {
        [void](New-NetworkControllerVirtualNetwork @nc -ResourceId $vnet.ResourceId -Properties $vnet.Properties -Force)
        $deadline = (Get-Date).AddMinutes(5)
        do {
            Start-Sleep -Seconds 5
            $state = (Get-NetworkControllerVirtualNetwork @nc -ResourceId $VNetResourceId).Properties.ProvisioningState
        } until ($state -in "Succeeded", "Failed" -or (Get-Date) -gt $deadline)
        if ($state -ne "Succeeded") { throw "Virtual network $VNetResourceId ended in state '$state'" }
        Write-Warning "Virtual network updated: hosts were re-programmed. Re-test the VIPs now (L25)."
    }

    # 4. Final state
    if ($drift.Count -eq 0) {
        "No drift ($Customer)"
    } else {
        $drift | ForEach-Object { "DRIFT: $_" }
        if (-not $CheckOnly) { "Applied ($Customer)" }
    }
    $final = Get-NetworkControllerVirtualNetwork @nc -ResourceId $VNetResourceId
    $final.Properties.Subnets | ForEach-Object {
        $ref = if ($_.Properties.RouteTable) { ($_.Properties.RouteTable.ResourceRef -split '/')[-1] } else { "(none)" }
        [pscustomobject]@{ Subnet = $_.Properties.AddressPrefix; RouteTable = $ref }
    } | Sort-Object Subnet | Format-Table -AutoSize | Out-String | Write-Output

    # 5. Policy checks: reported, never fixed automatically
    $findings = New-Object System.Collections.ArrayList
    foreach ($s in $final.Properties.Subnets) {
        if ($s.Properties.AccessControlList -and $s.Properties.AccessControlList.ResourceRef) {
            [void]$findings.Add("Port ACL on subnet $($s.Properties.AddressPrefix) (L22): $($s.Properties.AccessControlList.ResourceRef)")
        }
    }
    $ipByRef = @{}
    foreach ($n in @(Get-NetworkControllerNetworkInterface @nc)) {
        foreach ($c in @($n.Properties.IpConfigurations)) {
            if (-not $c.Properties.Subnet -or $c.Properties.Subnet.ResourceRef -notlike "/virtualNetworks/$VNetResourceId/*") { continue }
            $ipByRef[("/networkInterfaces/{0}/ipConfigurations/{1}" -f $n.ResourceId, $c.ResourceId).ToLowerInvariant()] = $c.Properties.PrivateIPAddress
            if ($c.Properties.AccessControlList -and $c.Properties.AccessControlList.ResourceRef) {
                [void]$findings.Add("Port ACL on NIC $($c.Properties.PrivateIPAddress) (L22): $($c.Properties.AccessControlList.ResourceRef)")
            }
        }
    }
    foreach ($lb in @(Get-NetworkControllerLoadBalancer @nc)) {
        $refs = @()
        foreach ($pool in @($lb.Properties.BackendAddressPools)) { $refs += @($pool.Properties.BackendIPConfigurations | ForEach-Object { $_.ResourceRef }) }
        foreach ($rule in @($lb.Properties.InboundNatRules))     { if ($rule.Properties.BackendIPConfiguration) { $refs += $rule.Properties.BackendIPConfiguration.ResourceRef } }
        foreach ($ref in ($refs | Where-Object { $_ })) {
            $ip = $ipByRef[$ref.ToLowerInvariant()]
            if ($ip -and $ip -notin $FirewallIPs) { [void]$findings.Add("Load balancer $($lb.ResourceId) has backend $ip, not the firewall (L26)") }
        }
    }
    $findings | ForEach-Object { "FINDING: $_" }

    if ($CheckOnly -and $drift.Count -gt 0) { exit 2 }
    if ($findings.Count -gt 0) { exit 3 }
    exit 0
}
catch {
    [Console]::Error.WriteLine("ERROR: $_")
    exit 1
}
