# get_wifi_details.ps1
# V1.1.0 L1 Skill - Get Wi-Fi connection details
# expected_cost: low
# danger_level: P0_READ
# group: C08_network_probe

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

    # 4. Core logic - Handle GBK encoding for Chinese Windows
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
    } catch { }
    
    $netshOutput = netsh wlan show interfaces 2>&1
    [Console]::OutputEncoding = $prevEncoding
    
    # Check if wireless adapter exists
    $outputStr = $netshOutput | Out-String
    if ($outputStr -match 'no wireless interface' -or $outputStr -match 'Wireless AutoConfig') {
        # Has WLAN service but may not have interface
    }
    
    $hasInterface = $false
    foreach ($line in $netshOutput) {
        $lineStr = $line.ToString()
        if ($lineStr -match 'There is \d+ interface' -or $lineStr -match 'Name\s*:') {
            $hasInterface = $true
            break
        }
    }
    
    if (-not $hasInterface) {
        Emit-Success @{
            wifi_available = $false
            connected = $false
            message = 'No wireless interface found on this system'
        }
        return
    }

    # Parse Wi-Fi interface info
    $interfaceName = $null
    $ssid = $null
    $bssid = $null
    $networkType = $null
    $radioType = $null
    $authentication = $null
    $cipher = $null
    $channel = $null
    $receiveRate = $null
    $transmitRate = $null
    $signal = $null
    $state = $null
    $wifiProfile = $null
    
    foreach ($line in $netshOutput) {
        $lineStr = $line.ToString().Trim()
        
        if ($lineStr -match 'Name\s*:\s*(.+)') {
            $interfaceName = $matches[1].Trim()
        }
        elseif ($lineStr -match '^\s*SSID\s*:\s*(.+)') {
            $ssid = $matches[1].Trim()
        }
        elseif ($lineStr -match 'BSSID\s*:\s*([0-9a-fA-F:]+)') {
            $bssid = $matches[1].Trim()
        }
        elseif ($lineStr -match 'Network type\s*:\s*(.+)') {
            $networkType = $matches[1].Trim()
        }
        elseif ($lineStr -match 'Radio type\s*:\s*(.+)') {
            $radioType = $matches[1].Trim()
        }
        elseif ($lineStr -match 'Authentication\s*:\s*(.+)') {
            $authentication = $matches[1].Trim()
        }
        elseif ($lineStr -match 'Cipher\s*:\s*(.+)') {
            $cipher = $matches[1].Trim()
        }
        elseif ($lineStr -match 'Channel\s*:\s*(\d+)') {
            $channel = [int]$matches[1]
        }
        elseif ($lineStr -match 'Receive rate \(Mbps\)\s*:\s*([\d.]+)') {
            $receiveRate = [double]$matches[1]
        }
        elseif ($lineStr -match 'Transmit rate \(Mbps\)\s*:\s*([\d.]+)') {
            $transmitRate = [double]$matches[1]
        }
        elseif ($lineStr -match 'Signal\s*:\s*(\d+)%') {
            $signal = [int]$matches[1]
        }
        elseif ($lineStr -match 'State\s*:\s*(.+)') {
            $state = $matches[1].Trim()
        }
        elseif ($lineStr -match 'Profile\s*:\s*(.+)') {
            $wifiProfile = $matches[1].Trim()
        }
    }
    
    # Determine connection status
    $isConnected = ($state -eq 'connected')
    
    # Evaluate signal quality
    $signalQuality = 'unknown'
    $issues = @()
    
    if ($null -ne $signal) {
        if ($signal -ge 80) {
            $signalQuality = 'excellent'
        } elseif ($signal -ge 60) {
            $signalQuality = 'good'
        } elseif ($signal -ge 40) {
            $signalQuality = 'fair'
            $issues += 'Signal strength is moderate, consider moving closer to the router'
        } elseif ($signal -ge 20) {
            $signalQuality = 'weak'
            $issues += 'Signal strength is weak, this may cause slow speeds and disconnections'
        } else {
            $signalQuality = 'very_weak'
            $issues += 'Signal strength is very weak, connection may be unstable'
        }
    }
    
    # Check rate
    if ($null -ne $receiveRate -and $receiveRate -lt 50) {
        $issues += "Low receive rate: $receiveRate Mbps"
    }
    
    # Determine frequency band
    $frequencyBand = $null
    if ($null -ne $channel) {
        if ($channel -le 14) {
            $frequencyBand = '2.4GHz'
        } else {
            $frequencyBand = '5GHz'
        }
    }

    # 5. Success output
    $diagnosis = "Wi-Fi is not connected"
    if ($issues.Count -gt 0) {
        $diagnosis = "Wi-Fi issues detected: slow network may be caused by weak signal"
    } elseif ($isConnected) {
        $diagnosis = "Wi-Fi connection is healthy"
    }
    
    Emit-Success @{
        wifi_available = $true
        connected = $isConnected
        interface_name = $interfaceName
        ssid = $ssid
        bssid = $bssid
        network_type = $networkType
        radio_type = $radioType
        authentication = $authentication
        cipher = $cipher
        channel = $channel
        frequency_band = $frequencyBand
        receive_rate_mbps = $receiveRate
        transmit_rate_mbps = $transmitRate
        signal_percent = $signal
        signal_quality = $signalQuality
        state = $state
        profile = $wifiProfile
        issues = $issues
        diagnosis = $diagnosis
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
