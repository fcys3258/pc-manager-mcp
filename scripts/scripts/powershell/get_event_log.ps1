# get_event_log.ps1
# V1.1.0 L1 Skill - Query Windows Event Log (conditional UAC for Security log only)

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Helper: Check if Security log is requested and we need elevation
function Test-NeedsElevation($inputJson) {
    try {
        $args = $inputJson | ConvertFrom-Json
        $logName = if ($args.parameter -and $args.parameter.PSObject.Properties['log_name']) { 
            $args.parameter.log_name 
        } else { 'System' }
        return ($logName -eq 'Security')
    } catch {
        return $false
    }
}

# 0. Conditional UAC elevation (only for Security log)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$inputJson = if ($InputFile -and (Test-Path $InputFile)) { Get-Content $InputFile -Raw -Encoding UTF8 } else { $InputObject }

if (-not $isAdmin -and (Test-NeedsElevation $inputJson)) {
    try {
        $outputFileParam = if ($OutputFile) { $OutputFile } else { Join-Path $env:TEMP "ps_output_$([guid]::NewGuid()).json" }
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
        
        $inputFileTemp = $null
        if ($InputObject) {
            $inputFileTemp = Join-Path $env:TEMP "ps_input_$([guid]::NewGuid()).json"
            [System.IO.File]::WriteAllText($inputFileTemp, $InputObject, [System.Text.UTF8Encoding]::new($false))
            $argList += "-InputFile"
            $argList += $inputFileTemp
        } elseif ($InputFile -and (Test-Path $InputFile)) {
            $argList += "-InputFile"
            $argList += $InputFile
        }
        
        $argList += "-OutputFile"
        $argList += $outputFileParam
        
        $process = Start-Process powershell -Verb RunAs -ArgumentList $argList -PassThru -Wait

        if ($inputFileTemp -and (Test-Path $inputFileTemp)) {
            Remove-Item $inputFileTemp -Force -ErrorAction SilentlyContinue
        }
        
        if (-not $OutputFile) {
            $timeout = 100; $elapsed = 0
            while (-not (Test-Path $outputFileParam) -and $elapsed -lt $timeout) {
                Start-Sleep -Milliseconds 100; $elapsed++
            }
            if (Test-Path $outputFileParam) {
                $output = Get-Content $outputFileParam -Raw -Encoding UTF8
                Write-Output $output
                Remove-Item $outputFileParam -Force -ErrorAction SilentlyContinue
            } else {
                Write-Output (@{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Administrator process did not generate output";retriable=$false};metadata=@{skill_version="1.1.0"}} | ConvertTo-Json -Compress)
            }
        }
        exit $process.ExitCode
    } catch {
        Write-Output (@{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Elevation failed: $_";retriable=$false};metadata=@{skill_version="1.1.0"}} | ConvertTo-Json -Compress)
        exit 1
    }
}

# Process InputFile if provided
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
    if ($script:SkillArgs -and $script:SkillArgs.metadata) {
        $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
    }
    $extraMeta.GetEnumerator() | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
    $finalMetadata['exec_time_ms'] = $__sw.ElapsedMilliseconds
    $finalMetadata['skill_version'] = "1.1.0"
    $body = @{ ok = $true; data = $data; error = $null; metadata = $finalMetadata }
    $json = $body | ConvertTo-Json -Depth 6 -Compress
    if ($script:OutputFilePath) { [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false)) }
    else { Write-Output $json }
}

function Emit-Error($code, $message, $retriable = $false, $extraMeta = @{}) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true
    $finalMetadata = @{}
    if ($script:SkillArgs -and $script:SkillArgs.metadata) {
        $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
    }
    $extraMeta.GetEnumerator() | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
    $finalMetadata['exec_time_ms'] = $__sw.ElapsedMilliseconds
    $finalMetadata['skill_version'] = "1.1.0"
    $body = @{ ok = $false; data = $null; error = @{ code = $code; message = $message; retriable = [bool]$retriable }; metadata = $finalMetadata }
    $json = $body | ConvertTo-Json -Depth 6 -Compress
    if ($script:OutputFilePath) { [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false)) }
    else { Write-Output $json }
}

function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    return ($sw.ElapsedMilliseconds -lt $budget_ms)
}


try {
    # 3. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    if (-not $script:SkillArgs) {
        Emit-Error 'INVALID_ARGUMENT' 'Invalid or empty SkillArgs JSON payload.' $false
        return
    }
    $Parameter = $script:SkillArgs.parameter
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }

    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # 4. Core logic
    $logName = if ($Parameter -and $Parameter.PSObject.Properties['log_name']) { $Parameter.log_name } else { 'System' }
    $levelStr = if ($Parameter -and $Parameter.PSObject.Properties['level']) { $Parameter.level } else { $null }
    $eventId = if ($Parameter -and $Parameter.PSObject.Properties['event_id']) { $Parameter.event_id } else { $null }
    $timeRangeHours = if ($Parameter -and $Parameter.PSObject.Properties['time_range_hours']) { $Parameter.time_range_hours } else { 24 }
    $maxEvents = if ($Parameter -and $Parameter.PSObject.Properties['max_events']) { $Parameter.max_events } else { 100 }
    $providerName = if ($Parameter -and $Parameter.PSObject.Properties['provider_name']) { $Parameter.provider_name } else { $null }

    $startTime = (Get-Date).AddHours(-$timeRangeHours)
    $filter = @{ LogName = $logName; StartTime = $startTime }
    
    # Map string level to int
    if ($levelStr) {
        $levelMap = @{ "Critical" = 1; "Error" = 2; "Warning" = 3; "Information" = 4; "Verbose" = 5 }
        if ($levelMap.ContainsKey($levelStr)) { $filter['Level'] = $levelMap[$levelStr] }
        elseif ($levelStr -match '^\d+$') { $filter['Level'] = [int]$levelStr }
    }
    
    if ($eventId) { $filter['Id'] = $eventId }
    if ($providerName) { $filter['ProviderName'] = $providerName }

    # $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $maxEvents -ErrorAction SilentlyContinue
    # === FIX: Wrap result in @() to force array type ===
    $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $maxEvents -ErrorAction SilentlyContinue)

    $eventEntries = @()
    if ($events) {
        foreach ($event in $events) {
            $message = if ($event.Message) { $event.Message.Substring(0, [Math]::Min(2000, $event.Message.Length)) } else { "" }
            $eventEntries += @{
                time_created = $event.TimeCreated.ToString('o')
                id = $event.Id
                level = $event.LevelDisplayName
                provider_name = $event.ProviderName
                message = $message
            }
        }
    }

    $isTruncated = if ($events) { $events.Count -ge $maxEvents } else { $false }
    Emit-Success @{ events = $eventEntries; total_found = $eventEntries.Count } @{ truncated = $isTruncated }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
