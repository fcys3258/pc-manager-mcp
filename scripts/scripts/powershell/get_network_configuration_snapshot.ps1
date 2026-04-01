# get_network_configuration_snapshot.ps1
# V1.1.0 L1 Skill - Get network configuration snapshot
# expected_cost: low
# danger_level: P0_READ
# group: C07_network_config

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Handle InputFile (subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# 1. Strict mode and environment settings
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# 2. Unified JSON output functions
$global:__hasEmitted = $false
$__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
$script:SkillArgs = $null
$script:OutputFilePath = $OutputFile

function Emit-Success($data, $extraMeta = @{}) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true

    $finalMetadata = @{}
    if ($script:SkillArgs -and $script:SkillArgs.metadata) {
        $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object {
            $finalMetadata[$_.Name] = $_.Value
        }
    }
    $extraMeta.GetEnumerator() | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
    $finalMetadata['exec_time_ms'] = $__sw.ElapsedMilliseconds
    $finalMetadata['skill_version'] = "1.1.0"

    $body = @{
        ok = $true
        data = $data
        error = $null
        metadata = $finalMetadata
    }
    $json = $body | ConvertTo-Json -Depth 6 -Compress
    if ($script:OutputFilePath) {
        [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false))
    } else {
        Write-Output $json
    }
}

function Emit-Error($code, $message, $retriable = $false, $extraMeta = @{}) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true

    $finalMetadata = @{}
    if ($script:SkillArgs -and $script:SkillArgs.metadata) {
        $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object {
            $finalMetadata[$_.Name] = $_.Value
        }
    }
    $extraMeta.GetEnumerator() | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
    $finalMetadata['exec_time_ms'] = $__sw.ElapsedMilliseconds
    $finalMetadata['skill_version'] = "1.1.0"

    $body = @{
        ok = $false
        data = $null
        error = @{
            code = $code
            message = $message
            retriable = [bool]$retriable
        }
        metadata = $finalMetadata
    }
    $json = $body | ConvertTo-Json -Depth 6 -Compress
    if ($script:OutputFilePath) {
        [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false))
    } else {
        Write-Output $json
    }
}

# 3. Budget guard
function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

try {
    # 4. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }

    # 5. Check budget
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # 6. Core logic
    $adapters = @()
    $fallback = $false

    # a. Network Adapters
    try {
        # Primary path: Get-NetAdapter
        $netAdapters = Get-NetAdapter | Where-Object { $_.Status -ne 'Not Present' }
        foreach ($adapter in $netAdapters) {
            $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex -Detailed -ErrorAction SilentlyContinue
            $wifiInfo = $null
            if ($adapter.InterfaceDescription -like "*Wi-Fi*") {
                $wifiProfile = Get-NetConnectionProfile -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
                # For multi-language compatibility, do not parse localized netsh output for Wi-Fi signal strength
                $wifiInfo = @{
                    wifi_ssid = if ($wifiProfile) { $wifiProfile.Name } else { $null }
                    wifi_signal_strength = $null
                }
            }

            $adapters += @{
                interface_name = $adapter.Name
                status = $adapter.Status
                mac_address = $adapter.MacAddress
                ip_addresses = $ipConfig.IPv4Address.IPAddress + $ipConfig.IPv6Address.IPAddress
                default_gateways = $ipConfig.IPv4DefaultGateway.NextHop + $ipConfig.IPv6DefaultGateway.NextHop
                dns_servers = $ipConfig.DNSServer.ServerAddresses
                is_physical = $adapter.Physical
            } + $wifiInfo
        }
    } catch {
        # Fallback path: Win32_NetworkAdapterConfiguration
        $fallback = $true
        $denyList = @('isatap','Teredo','Loopback','VMware','VirtualBox','Hyper-V')
        $wmiAdapters = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' -ErrorAction SilentlyContinue | Where-Object {
            $ifaceDesc = $_.Description
            $isDenied = $false
            foreach ($deny in $denyList) {
                if ($ifaceDesc -like "*$deny*") { $isDenied = $true; break }
            }
            -not $isDenied
        })
        foreach ($adapter in $wmiAdapters) {
            $adapters += @{
                interface_name = $adapter.Description
                status = 'Up'
                mac_address = $adapter.MACAddress
                ip_addresses = @($adapter.IPAddress)
                default_gateways = @($adapter.DefaultIPGateway)
                dns_servers = @($adapter.DNSServerSearchOrder)
                is_physical = $true
            }
        }
    }

    # b. Firewall
    $firewallProfiles = @()
    try {
        Get-NetFirewallProfile | ForEach-Object {
            $firewallProfiles += @{
                name = $_.Name
                is_enabled = $_.Enabled
            }
        }
    } catch {
        # Ignore if firewall cmdlets are not available
    }

    # c. Proxy
    $isProxyEnabled = $false
    $proxyServer = $null
    try {
        $proxySettings = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $isProxyEnabled = [bool]$proxySettings.ProxyEnable
        if ($isProxyEnabled) {
            $proxyServer = $proxySettings.ProxyServer
        }
    } catch {
        # Ignore if cannot read registry
    }

    $result = @{
        adapters = $adapters
        firewall_profiles = $firewallProfiles
        is_proxy_enabled = $isProxyEnabled
        proxy_server = $proxyServer
    }

    # 7. Success output
    Emit-Success $result @{ fallback_mode = $fallback }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
