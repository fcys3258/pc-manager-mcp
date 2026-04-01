# get_device_status.ps1
# V1.1.0 L1 Skill - Get device status information

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

    # 4. Core logic - Get device status
    $namePattern = $null
    if ($Parameter -and $Parameter.PSObject.Properties['name_pattern']) {
        $namePattern = $Parameter.name_pattern
    }
    
    $className = $null
    if ($Parameter -and $Parameter.PSObject.Properties['class_name']) {
        $className = $Parameter.class_name
    }

    $devices = @(Get-PnpDevice -ErrorAction SilentlyContinue)
    if ($namePattern) {
        $devices = @($devices | Where-Object { $_.FriendlyName -like $namePattern })
    }
    if ($className) {
        $devices = @($devices | Where-Object { $_.Class -eq $className })
    }

    $deviceList = @()
    foreach ($device in $devices) {
        $deviceInfo = @{
            pnp_device_id = if ($device.InstanceId) { $device.InstanceId } else { $null }
            friendly_name = if ($device.FriendlyName) { $device.FriendlyName } else { $null }
            class = if ($device.Class) { $device.Class } else { $null }
            status = if ($device.Status) { $device.Status } else { $null }
            problem_code = if ($device.PSObject.Properties['ProblemCode']) { $device.ProblemCode } else { 0 }
            is_present = if ($device.PSObject.Properties['Present']) { $device.Present } else { $false }
        }
        $deviceList += $deviceInfo
    }
    
    # 5. Success output
    Emit-Success @{ devices = $deviceList }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
