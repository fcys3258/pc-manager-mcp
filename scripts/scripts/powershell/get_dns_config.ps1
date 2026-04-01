# get_dns_config.ps1
# V1.1.0 L1 Skill - Get system DNS configuration
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

try {
    # 3. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json

    # 4. Core logic - Get DNS configuration
    $dnsConfigs = @()
    $fallbackMode = $false

    try {
        # Primary path: Get-DnsClientServerAddress (Windows 8+)
        $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
        
        foreach ($adapter in $adapters) {
            $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
            
            $ipv4Dns = @($dns | Where-Object { $_.AddressFamily -eq 2 } | Select-Object -ExpandProperty ServerAddresses -ErrorAction SilentlyContinue)
            $ipv6Dns = @($dns | Where-Object { $_.AddressFamily -eq 23 } | Select-Object -ExpandProperty ServerAddresses -ErrorAction SilentlyContinue)
            
            $dnsConfigs += @{
                interface_name = $adapter.Name
                interface_index = $adapter.InterfaceIndex
                interface_description = $adapter.InterfaceDescription
                status = $adapter.Status
                ipv4_dns = if ($ipv4Dns) { $ipv4Dns } else { @() }
                ipv6_dns = if ($ipv6Dns) { $ipv6Dns } else { @() }
            }
        }
    } catch {
        # Fallback path: WMI (Windows 7 compatible)
        $fallbackMode = $true
        $wmiAdapters = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' -ErrorAction SilentlyContinue)
        
        foreach ($adapter in $wmiAdapters) {
            $dnsConfigs += @{
                interface_name = $adapter.Description
                interface_index = $adapter.Index
                dns_servers = if ($adapter.DNSServerSearchOrder) { @($adapter.DNSServerSearchOrder) } else { @() }
                dhcp_enabled = $adapter.DHCPEnabled
                ip_addresses = if ($adapter.IPAddress) { @($adapter.IPAddress) } else { @() }
            }
        }
    }

    # 5. Success output
    $resultData = @{
        dns_configs = $dnsConfigs
        adapter_count = $dnsConfigs.Count
    }
    
    $extraMeta = @{}
    if ($fallbackMode) {
        $extraMeta['fallback_mode'] = $true
        $extraMeta['fallback_reason'] = 'Get-NetAdapter not available, using WMI'
    }
    
    Emit-Success $resultData $extraMeta

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
