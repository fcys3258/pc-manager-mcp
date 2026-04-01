# get_battery_status.ps1
# V1.1.0 L1 Skill - Get battery status and health information
# expected_cost: 'low'
# danger_level: 'P0_READ'
# group: C12 (Power Temperature)

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Handle InputFile (for elevated subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# 1. Strict mode and environment setup
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
    if ($script:SkillArgs -and $script:SkillArgs.PSObject.Properties['metadata'] -and $script:SkillArgs.metadata) {
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
    if ($script:SkillArgs -and $script:SkillArgs.PSObject.Properties['metadata'] -and $script:SkillArgs.metadata) {
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
    if ($InputObject) {
        $script:SkillArgs = $InputObject | ConvertFrom-Json
    } else {
        $script:SkillArgs = @{ parameter = @{}; metadata = @{} }
    }

    # 4. Core logic - Get battery information
    $batteryArr = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if ($batteryArr.Count -eq 0) {
        Emit-Success @{ supported = $false; reason = "No battery detected on this system" }
        return
    }
    $battery = $batteryArr[0]

    # Get detailed battery info from WMI
    $batteryStatusArr = @(Get-CimInstance -ClassName BatteryStatus -Namespace root\wmi -ErrorAction SilentlyContinue)
    $batteryStatus = if ($batteryStatusArr.Count -gt 0) { $batteryStatusArr[0] } else { $null }
    $batteryFullChargedArr = @(Get-CimInstance -ClassName BatteryFullChargedCapacity -Namespace root\wmi -ErrorAction SilentlyContinue)
    $batteryFullCharged = if ($batteryFullChargedArr.Count -gt 0) { $batteryFullChargedArr[0] } else { $null }
    $batteryStaticArr = @(Get-CimInstance -ClassName BatteryStaticData -Namespace root\wmi -ErrorAction SilentlyContinue)
    $batteryStatic = if ($batteryStaticArr.Count -gt 0) { $batteryStaticArr[0] } else { $null }

    # Safely access capacity information
    $designCapacity = if ($batteryStatic -and $batteryStatic.PSObject.Properties['DesignedCapacity']) { 
        $batteryStatic.DesignedCapacity 
    } else { 
        $null 
    }
    $fullChargeCapacity = if ($batteryFullCharged -and $batteryFullCharged.PSObject.Properties['FullChargedCapacity']) { 
        $batteryFullCharged.FullChargedCapacity 
    } else { 
        $null 
    }
    $remainingCapacity = if ($batteryStatus -and $batteryStatus.PSObject.Properties['RemainingCapacity']) { 
        $batteryStatus.RemainingCapacity 
    } else { 
        $null 
    }

    # Calculate battery health percentage
    $healthPercent = if ($designCapacity -and $fullChargeCapacity -and $designCapacity -gt 0) {
        [math]::Round(($fullChargeCapacity / $designCapacity) * 100, 2)
    } else {
        $null
    }

    # Map battery status code to description
    $statusCode = if ($battery.PSObject.Properties['BatteryStatus']) { $battery.BatteryStatus } else { $null }
    $statusDescription = switch ($statusCode) {
        1 { "Discharging" }
        2 { "On AC Power" }
        3 { "Fully Charged" }
        4 { "Low" }
        5 { "Critical" }
        6 { "Charging" }
        7 { "Charging and High" }
        8 { "Charging and Low" }
        9 { "Charging and Critical" }
        10 { "Undefined" }
        11 { "Partially Charged" }
        default { "Unknown" }
    }

    $result = @{
        supported = $true
        estimated_charge_remaining_percent = if ($battery.PSObject.Properties['EstimatedChargeRemaining']) { $battery.EstimatedChargeRemaining } else { $null }
        estimated_run_time_minutes = if ($battery.PSObject.Properties['EstimatedRunTime']) { $battery.EstimatedRunTime } else { $null }
        status_code = $statusCode
        status_description = $statusDescription
        is_charging = if ($batteryStatus -and $batteryStatus.PSObject.Properties['Charging']) { $batteryStatus.Charging } else { $null }
        health_percent = $healthPercent
        design_capacity_mwh = $designCapacity
        full_charge_capacity_mwh = $fullChargeCapacity
        remaining_capacity_mwh = $remainingCapacity
        cycle_count = if ($batteryStatus -and $batteryStatus.PSObject.Properties['CycleCount']) { $batteryStatus.CycleCount } else { $null }
    }
    
    Emit-Success $result

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
