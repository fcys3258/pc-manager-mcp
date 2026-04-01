# get_active_power_plan.ps1
# V1.1.0 L1 Skill - Get active power plan and available plans
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

    # 4. Core logic - Get power plan information using powercfg
    
    # Handle GBK encoding for Chinese Windows
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
    } catch { }
    
    # Get all power plans via powercfg /list
    $powercfgList = & powercfg /list 2>&1
    [Console]::OutputEncoding = $prevEncoding
    
    $availablePlans = @()
    $activePlanGuid = $null
    $activePlanName = $null
    
    foreach ($line in $powercfgList) {
        $lineStr = $line.ToString()
        # Match pattern: Power Scheme GUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  (Plan Name) *
        # The * indicates active plan
        if ($lineStr -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\s+\(([^)]+)\)(\s*\*)?') {
            $planGuid = $Matches[1]
            $planName = $Matches[2].Trim()
            $isActive = $Matches[3] -match '\*'
            
            $availablePlans += @{
                name = $planName
                guid = $planGuid
                is_active = $isActive
            }
            
            if ($isActive) {
                $activePlanGuid = $planGuid
                $activePlanName = $planName
            }
        }
    }
    
    # Check battery/AC status
    $hasBattery = $false
    $isOnAcPower = $true
    $batteryArr = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if ($batteryArr.Count -gt 0) {
        $battery = $batteryArr[0]
        $hasBattery = $true
        # BatteryStatus: 1=Discharging, 2=On AC, other values also indicate AC power
        $batteryStatus = if ($battery.PSObject.Properties['BatteryStatus']) { $battery.BatteryStatus } else { 2 }
        $isOnAcPower = $batteryStatus -ne 1
    }

    $result = @{
        active_plan_name = $activePlanName
        active_plan_guid = $activePlanGuid
        available_plans = $availablePlans
        plan_count = $availablePlans.Count
        has_battery = $hasBattery
        is_on_ac_power = $isOnAcPower
        power_source = if ($hasBattery) { if ($isOnAcPower) { "AC Power" } else { "Battery" } } else { "AC Power (Desktop)" }
    }
    
    Emit-Success $result

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
