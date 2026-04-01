# set_active_power_plan.ps1
# V1.1.0 L1 Skill - Set active power plan
# expected_cost: 'low'
# danger_level: 'P1_WRITE_REVERSIBLE'
# group: C12 (Power Temperature)
# Note: Does NOT require administrator privileges

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Handle InputFile (for subprocess mode)
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
    
    $Parameter = if ($script:SkillArgs.PSObject.Properties['parameter']) { $script:SkillArgs.parameter } else { @{} }

    # 4. Parameter validation
    $planGuid = if ($Parameter -and $Parameter.PSObject.Properties['plan_guid']) { $Parameter.plan_guid } else { $null }
    
    if (-not $planGuid) {
        Emit-Error 'INVALID_ARGUMENT' 'Parameter "plan_guid" is required. Use get_active_power_plan to list available plans.' $false
        return
    }
    
    # Validate GUID format
    if ($planGuid -notmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') {
        Emit-Error 'INVALID_ARGUMENT' "Invalid plan_guid format: $planGuid" $false
        return
    }
    
    # Check dry_run mode
    $dryRun = if ($Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }
    
    # Get current active plan for comparison
    $currentActiveGuid = $null
    try {
        $activePlanRaw = & powercfg /getactivescheme 2>&1
        if ($activePlanRaw -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
            $currentActiveGuid = $Matches[1]
        }
    } catch {}
    
    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'
            would_perform_action = "Set active power plan to: $planGuid"
            current_plan_guid = $currentActiveGuid
            target_plan_guid = $planGuid
        }
        return
    }
    
    # 5. Execute powercfg /setactive
    $null = & powercfg /setactive $planGuid 2>&1
    
    # Verify the change
    $newActiveGuid = $null
    try {
        $activePlanRaw = & powercfg /getactivescheme 2>&1
        if ($activePlanRaw -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
            $newActiveGuid = $Matches[1]
        }
    } catch {}
    
    if ($newActiveGuid -eq $planGuid) {
        Emit-Success @{ 
            result = 'success'
            previous_plan_guid = $currentActiveGuid
            active_plan_guid = $newActiveGuid
            message = "Power plan successfully changed"
        }
    } else {
        Emit-Error 'ACTION_FAILED' "Failed to set power plan. Current active: $newActiveGuid, expected: $planGuid" $false
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
