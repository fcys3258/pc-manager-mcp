# get_bsod_history.ps1
# V1.1.0 L1 Skill - Get BSOD crash history

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

function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

# Common BugCheck code explanations
$BugCheckCodes = @{
    '0x0000000a' = @{ name = 'IRQL_NOT_LESS_OR_EQUAL'; cause = 'Driver accessing invalid memory at high IRQL' }
    '0x0000001e' = @{ name = 'KMODE_EXCEPTION_NOT_HANDLED'; cause = 'Kernel exception not handled' }
    '0x00000024' = @{ name = 'NTFS_FILE_SYSTEM'; cause = 'NTFS file system error' }
    '0x0000003b' = @{ name = 'SYSTEM_SERVICE_EXCEPTION'; cause = 'System service exception' }
    '0x00000050' = @{ name = 'PAGE_FAULT_IN_NONPAGED_AREA'; cause = 'Memory page fault' }
    '0x0000007e' = @{ name = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'; cause = 'System thread exception' }
    '0x0000007f' = @{ name = 'UNEXPECTED_KERNEL_MODE_TRAP'; cause = 'CPU trap (possible hardware issue)' }
    '0x0000009f' = @{ name = 'DRIVER_POWER_STATE_FAILURE'; cause = 'Driver power state failure' }
    '0x000000be' = @{ name = 'ATTEMPTED_WRITE_TO_READONLY_MEMORY'; cause = 'Driver writing to read-only memory' }
    '0x000000c2' = @{ name = 'BAD_POOL_CALLER'; cause = 'Driver memory pool corruption' }
    '0x000000d1' = @{ name = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'; cause = 'Driver accessing paged memory at high IRQL' }
    '0x000000ef' = @{ name = 'CRITICAL_PROCESS_DIED'; cause = 'Critical system process terminated' }
    '0x000000f4' = @{ name = 'CRITICAL_OBJECT_TERMINATION'; cause = 'Critical object termination' }
    '0x00000116' = @{ name = 'VIDEO_TDR_FAILURE'; cause = 'Graphics driver timeout (GPU hang)' }
    '0x00000124' = @{ name = 'WHEA_UNCORRECTABLE_ERROR'; cause = 'Hardware error (CPU/Memory/Disk)' }
    '0x00000133' = @{ name = 'DPC_WATCHDOG_VIOLATION'; cause = 'Driver taking too long' }
    '0x0000013a' = @{ name = 'KERNEL_MODE_HEAP_CORRUPTION'; cause = 'Kernel heap corruption' }
    '0x00000139' = @{ name = 'KERNEL_SECURITY_CHECK_FAILURE'; cause = 'Security check failure' }
    '0x00000019' = @{ name = 'BAD_POOL_HEADER'; cause = 'Pool header corruption' }
    '0x0000001a' = @{ name = 'MEMORY_MANAGEMENT'; cause = 'Memory management error' }
}

try {
    # 3. Parameter injection
    if ($InputFile -and (Test-Path $InputFile)) {
        $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
    }
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    if (-not $script:SkillArgs) {
        Emit-Error 'INVALID_ARGUMENT' 'Invalid or empty SkillArgs JSON payload.' $false
        return
    }
    $Parameter = $script:SkillArgs.parameter
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }
    
    # Query days
    $days = if ($Parameter -and $Parameter.PSObject.Properties['days']) { 
        [int]$Parameter.days 
    } else { 30 }
    
    $maxEvents = if ($Parameter -and $Parameter.PSObject.Properties['max_events']) { 
        [int]$Parameter.max_events 
    } else { 20 }

    # Budget check
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded budget." $true
        return
    }

    # 4. Core logic
    $startTime = (Get-Date).AddDays(-$days)
    $crashes = @()
    $unexpectedShutdowns = @()

    # Query BugCheck events (Event ID 1001 from BugCheck provider)
    try {
        $bugCheckEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
            Id = 1001
            StartTime = $startTime
        } -MaxEvents $maxEvents -ErrorAction SilentlyContinue
        
        if ($bugCheckEvents) {
            foreach ($event in $bugCheckEvents) {
                $bugCheckCode = "Unknown"
                $bugCheckName = "Unknown"
                $bugCheckCause = "Unknown cause"
                $dumpFile = ""
                
                # Parse event message for BugCheck code
                if ($event.Message) {
                    if ($event.Message -match 'BugCheck\s+([0-9A-Fa-fx]+)') {
                        $bugCheckCode = $Matches[1].ToLower()
                        if ($BugCheckCodes.ContainsKey($bugCheckCode)) {
                            $bugCheckName = $BugCheckCodes[$bugCheckCode].name
                            $bugCheckCause = $BugCheckCodes[$bugCheckCode].cause
                        }
                    }
                    if ($event.Message -match 'dump file:\s*(.+)') {
                        $dumpFile = $Matches[1].Trim()
                    }
                }
                
                $crashes += @{
                    time = $event.TimeCreated.ToString('o')
                    bug_check_code = $bugCheckCode
                    bug_check_name = $bugCheckName
                    probable_cause = $bugCheckCause
                    dump_file = $dumpFile
                    event_id = $event.Id
                }
            }
        }
    } catch {
        # Ignore if no BugCheck events found
    }
    
    # Query unexpected shutdown events (Event ID 41 - Kernel-Power)
    try {
        $shutdownEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Microsoft-Windows-Kernel-Power'
            Id = 41
            StartTime = $startTime
        } -MaxEvents $maxEvents -ErrorAction SilentlyContinue
        
        if ($shutdownEvents) {
            foreach ($event in $shutdownEvents) {
                $unexpectedShutdowns += @{
                    time = $event.TimeCreated.ToString('o')
                    event_id = $event.Id
                    description = "Unexpected shutdown (power loss or crash)"
                }
            }
        }
    } catch {
        # Ignore if no shutdown events found
    }

    # 5. Success output
    Emit-Success @{
        crashes = $crashes
        unexpected_shutdowns = $unexpectedShutdowns
        crash_count = $crashes.Count
        shutdown_count = $unexpectedShutdowns.Count
        query_days = $days
    }

} catch {
    # 6. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
