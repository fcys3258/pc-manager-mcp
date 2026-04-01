# check_time_synchronization.ps1
# V1.1.0 L1 Skill - Check time synchronization status

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
    # 3. Parameter injection - support InputFile
    if ($InputFile -and (Test-Path $InputFile)) {
        $InputObject = Get-Content -Path $InputFile -Raw -Encoding UTF8
    }
    $script:SkillArgs = $InputObject | ConvertFrom-Json

    # 4. Core logic
    
    # Handle GBK encoding for Chinese Windows
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
    } catch { }
    
    $w32tmOutput = w32tm /query /status /verbose 2>&1
    [Console]::OutputEncoding = $prevEncoding
    
    # Parse output
    $leapIndicator = $null
    $stratum = $null
    $source = $null
    $lastSyncTime = $null
    $phaseOffset = $null
    $pollInterval = $null
    
    foreach ($line in $w32tmOutput) {
        $lineStr = $line.ToString().Trim()
        
        # Leap Indicator (0=normal sync)
        if ($lineStr -match 'Leap Indicator[:\s]+(\d+)') {
            $leapIndicator = [int]$Matches[1]
        }
        
        # Stratum (1=primary time source)
        if ($lineStr -match 'Stratum[:\s]+(\d+)') {
            $stratum = [int]$Matches[1]
        }
        
        # Source (time source)
        if ($lineStr -match 'Source[:\s]+(.+)') {
            $source = $Matches[1].Trim()
        }
        
        # Last Successful Sync Time
        if ($lineStr -match 'Last Successful Sync Time[:\s]+(.+)') {
            $lastSyncTime = $Matches[1].Trim()
        }
        
        # Phase Offset (critical time offset, in seconds)
        if ($lineStr -match 'Phase Offset[:\s]+([-\d.]+)s') {
            $phaseOffset = [double]$Matches[1]
        }
        
        # Poll Interval
        if ($lineStr -match 'Poll Interval[:\s]+(\d+)') {
            $pollInterval = [int]$Matches[1]
        }
    }
    
    # If w32tm query failed, try backup method
    if ($null -eq $phaseOffset) {
        try {
            $w32timeService = Get-Service -Name 'w32time' -ErrorAction Stop
            if ($w32timeService.Status -ne 'Running') {
                Emit-Success @{
                    service_running = $false
                    status = 'error'
                    message = 'Windows Time service is not running'
                    recommendation = 'Start the Windows Time service: net start w32time'
                }
                return
            }
        } catch { }
    }
    
    # Evaluate sync status
    $status = 'ok'
    $issues = @()
    $recommendation = $null
    
    # Check Leap Indicator
    if ($null -ne $leapIndicator) {
        if ($leapIndicator -eq 3) {
            $status = 'error'
            $issues += 'Clock is not synchronized (Leap Indicator = 3)'
        }
    }
    
    # Check time offset
    if ($null -ne $phaseOffset) {
        $absOffset = [Math]::Abs($phaseOffset)
        if ($absOffset -gt 300) {
            $status = 'error'
            $issues += "Time offset is critical: $([Math]::Round($phaseOffset, 2))s (>5 minutes)"
            $recommendation = 'Critical: Kerberos authentication will fail. Run: w32tm /resync /force'
        } elseif ($absOffset -gt 60) {
            if ($status -ne 'error') { $status = 'warning' }
            $issues += "Time offset is high: $([Math]::Round($phaseOffset, 2))s (>1 minute)"
            $recommendation = 'Run: w32tm /resync to synchronize time'
        }
    }
    
    # Check time source
    if ($source -eq 'Local CMOS Clock') {
        if ($status -eq 'ok') { $status = 'warning' }
        $issues += 'Using local CMOS clock instead of network time source'
    }
    
    # Calculate readable offset
    $phaseOffsetReadable = $null
    if ($null -ne $phaseOffset) {
        if ([Math]::Abs($phaseOffset) -lt 1) {
            $phaseOffsetReadable = "$([Math]::Round($phaseOffset * 1000, 0))ms"
        } else {
            $phaseOffsetReadable = "$([Math]::Round($phaseOffset, 2))s"
        }
    }

    # 5. Success output
    Emit-Success @{
        leap_indicator = $leapIndicator
        stratum = $stratum
        source = $source
        last_sync_time = $lastSyncTime
        phase_offset_seconds = $phaseOffset
        phase_offset_readable = $phaseOffsetReadable
        poll_interval_seconds = $pollInterval
        status = $status
        issues = $issues
        recommendation = $recommendation
        is_synchronized = ($leapIndicator -ne 3 -and $status -ne 'error')
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
