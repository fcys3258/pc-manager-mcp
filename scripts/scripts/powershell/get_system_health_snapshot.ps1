# get_system_health_snapshot.ps1
# V1.1.0 L1 Skill - Get system health snapshot

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 1. Strict mode and environment settings
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# Handle InputFile (for subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# 2. Unified JSON output functions
$global:__hasEmitted = $false
$__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
$script:SkillArgs = $null
$script:OutputFilePath = $OutputFile

function Emit-Success($data, $extraMeta = @{}) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true

    # Merge with host metadata
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

    # Merge with host metadata
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

# 3. Lightweight budget guard
function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

try {
    # 4. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $Parameter = $script:SkillArgs.parameter
    $BudgetMs = 0
    if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $BudgetMs = $script:SkillArgs.metadata.timeout_ms
    }

    # 5. Check budget
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # 6. Core logic
    # Safely access sampling_ms parameter
    $samplingMs = 1000
    if ($Parameter -and $Parameter.PSObject.Properties['sampling_ms']) {
        $samplingMs = $Parameter.sampling_ms
    }
    if (-not $samplingMs -or $samplingMs -lt 100) {
        $samplingMs = 1000
    }
    $sampleIntervalSec = [math]::Round($samplingMs / 1000, 3)

    $counters = @(
        '\Processor(_Total)\% Processor Time',
        '\Memory\% Committed Bytes In Use',
        '\PhysicalDisk(_Total)\% Disk Time',
        '\PhysicalDisk(_Total)\Disk Read Bytes/sec',
        '\PhysicalDisk(_Total)\Disk Write Bytes/sec'
    )

    try {
        $counterSample = Get-Counter -Counter $counters -SampleInterval $sampleIntervalSec -MaxSamples 2 -ErrorAction Stop
        
        # Safely extract performance counter values
        $cpuSamples = $counterSample.CounterSamples | Where-Object { $_.Path -like '*processor(*%' }
        $cpuUsage = if ($cpuSamples) { ($cpuSamples | Select-Object -Last 1).CookedValue } else { 0 }
        
        $memSamples = $counterSample.CounterSamples | Where-Object { $_.Path -like '*memory\% committed bytes in use' }
        $memUsage = if ($memSamples) { ($memSamples | Select-Object -Last 1).CookedValue } else { 0 }
        
        $diskTimeSamples = $counterSample.CounterSamples | Where-Object { $_.Path -like '*physicaldisk(*\% disk time' }
        $diskActiveTime = if ($diskTimeSamples) { ($diskTimeSamples | Select-Object -Last 1).CookedValue } else { 0 }
        
        $diskReadSamples = $counterSample.CounterSamples | Where-Object { $_.Path -like '*physicaldisk(*\disk read bytes/sec' }
        $diskRead = if ($diskReadSamples) { ($diskReadSamples | Select-Object -Last 1).CookedValue } else { 0 }
        
        $diskWriteSamples = $counterSample.CounterSamples | Where-Object { $_.Path -like '*physicaldisk(*\disk write bytes/sec' }
        $diskWrite = if ($diskWriteSamples) { ($diskWriteSamples | Select-Object -Last 1).CookedValue } else { 0 }

        $result = @{
            cpu_usage_percent = [math]::Round($cpuUsage, 2)
            memory_usage_percent = [math]::Round($memUsage, 2)
            disk_active_time_percent = [math]::Round($diskActiveTime, 2)
            disk_read_bytes_per_sec = [math]::Round($diskRead, 2)
            disk_write_bytes_per_sec = [math]::Round($diskWrite, 2)
        }

        # 7. Success output
        Emit-Success $result @{ sampling_ms = $samplingMs }

    } catch {
        # Fallback: if Get-Counter fails, try to get values separately
        $fallback = $true
        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
        
        $osArr = @(Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
        $os = if ($osArr.Count -gt 0) { $osArr[0] } else { $null }
        $memUsage = if ($os) { (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100 } else { 0 }

        $result = @{
            cpu_usage_percent = [math]::Round($cpuUsage, 2)
            memory_usage_percent = [math]::Round($memUsage, 2)
            disk_active_time_percent = -1 # Cannot easily get in fallback mode
            disk_read_bytes_per_sec = -1
            disk_write_bytes_per_sec = -1
        }
        Emit-Success $result @{ sampling_ms = $samplingMs; fallback_mode = $true }
    }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
