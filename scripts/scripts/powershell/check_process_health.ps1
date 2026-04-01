# check_process_health.ps1
# V1.1.0 L1 Skill - Check process health by analyzing crash/hang events

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Strict mode and environment setup
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# Handle InputFile
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# Unified JSON output functions
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

# Budget guard function
function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

try {
    # Parse input arguments
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    if (-not $script:SkillArgs) {
        Emit-Error 'INVALID_ARGUMENT' 'Invalid or empty SkillArgs JSON payload.' $false
        return
    }
    $Parameter = $script:SkillArgs.parameter
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) { $script:SkillArgs.metadata.timeout_ms } else { $null }

    # Check budget
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # Core logic - get parameters
    $processName = if ($Parameter.PSObject.Properties['process_name']) { $Parameter.process_name } else { $null }
    if (-not $processName) {
        Emit-Error 'INVALID_ARGUMENT' 'Missing required parameter: process_name' $false
        return
    }
    $timeRangeHours = if ($Parameter.PSObject.Properties['time_range']) { $Parameter.time_range } else { 24 }
    $limit = if ($Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 100 }

    $startTime = (Get-Date).AddHours(-$timeRangeHours)

    # Check 1: Application Errors (ID 1000)
    $errorFilter = @{
        LogName = 'Application'
        Id = 1000
        StartTime = $startTime
    }
    $errorEvents = Get-WinEvent -FilterHashtable $errorFilter -MaxEvents $limit -ErrorAction SilentlyContinue
    
    $crashEvents = @()
    if ($errorEvents) {
        foreach ($event in $errorEvents) {
            if ($event.Message -like "*$processName*") {
                $crashEvents += @{
                    time_created = $event.TimeCreated.ToString('yyyy-MM-ddTHH:mm:ss')
                    id = $event.Id
                    message = $event.Message.Substring(0, [Math]::Min(500, $event.Message.Length))
                    type = "Application Error"
                }
            }
        }
    }

    # Check 2: Application Hangs (ID 1002)
    $hangFilter = @{
        LogName = 'Application'
        Id = 1002
        StartTime = $startTime
    }
    $hangEventsResult = Get-WinEvent -FilterHashtable $hangFilter -MaxEvents $limit -ErrorAction SilentlyContinue

    $hangEvents = @()
    if ($hangEventsResult) {
        foreach ($event in $hangEventsResult) {
            if ($event.Message -like "*$processName*") {
                $hangEvents += @{
                    time_created = $event.TimeCreated.ToString('yyyy-MM-ddTHH:mm:ss')
                    id = $event.Id
                    message = $event.Message.Substring(0, [Math]::Min(500, $event.Message.Length))
                    type = "Application Hang"
                }
            }
        }
    }

    # Check 3: Live Status
    $liveStats = $null
    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($processes) {
        $liveStats = @()
        foreach ($p in $processes) {
            $cpu = 0
            try {
                $cpuValue = $p.CPU
                if ($cpuValue -is [TimeSpan]) {
                    $cpu = $cpuValue.TotalSeconds
                } else {
                    $cpu = [double]$cpuValue
                }
            } catch {}
            $mem = 0
            try { $mem = [math]::Round($p.WorkingSet / 1MB, 2) } catch {}
            
            $liveStats += @{
                id = $p.Id
                cpu_seconds = $cpu
                memory_mb = $mem
                responding = $p.Responding
            }
        }
    }

    $result = @{
        crash_events = $crashEvents
        hang_events = $hangEvents
        total_crashes = $crashEvents.Count
        total_hangs = $hangEvents.Count
        process_name = $processName
        time_range_hours = $timeRangeHours
        live_status = $liveStats
    }

    Emit-Success $result

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
