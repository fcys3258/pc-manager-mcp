# get_pnp_device_list.ps1
# V1.1.0 L1 Skill - Get PnP device list

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

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
    if ($InputFile -and (Test-Path $InputFile)) {
        $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
    }
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $Parameter = $script:SkillArgs.parameter

    # 4. Core logic - Get PnP device list
    $problemOnly = $false
    if ($Parameter -and $Parameter.PSObject.Properties['problem_only']) {
        $problemOnly = $Parameter.problem_only
    }
    $limit = if ($Parameter -and $Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 50 }
    $sortBy = if ($Parameter -and $Parameter.PSObject.Properties['sort_by']) { $Parameter.sort_by } else { 'friendly_name' }

    $devices = @(Get-PnpDevice -ErrorAction SilentlyContinue)
    if ($problemOnly) {
        # ProblemCode 22 (Disabled) is not considered a problem for this filter
        $devices = @($devices | Where-Object { 
            $pc = 0
            if ($_.PSObject.Properties['ProblemCode']) {
                $pc = $_.ProblemCode
            }
            $pc -ne 0 -and $pc -ne 22
        })
    }

    $deviceList = @()
    foreach ($device in $devices) {
        $problemCode = 0
        if ($device.PSObject.Properties['ProblemCode']) {
            $problemCode = $device.ProblemCode
        }
        
        $isPresent = $true
        if ($device.PSObject.Properties['Present']) {
            $isPresent = $device.Present
        }
        
        $deviceList += @{
            pnp_device_id = $device.InstanceId
            friendly_name = $device.FriendlyName
            class = $device.Class
            status = $device.Status
            problem_code = $problemCode
            is_present = $isPresent
        }
    }
    
    # Sort
    $sortedList = switch ($sortBy) {
        'class' { $deviceList | Sort-Object class }
        'status' { $deviceList | Sort-Object status }
        'problem_code' { $deviceList | Sort-Object problem_code }
        default { $deviceList | Sort-Object friendly_name }
    }

    # Limit
    $limitedList = $sortedList | Select-Object -First $limit
    
    # Ensure array output
    if ($limitedList -isnot [Array]) {
        $limitedList = @($limitedList)
    }

    # 5. Success output
    Emit-Success @{ 
        devices = $limitedList
        total_found = $deviceList.Count
        returned_count = $limitedList.Count
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
