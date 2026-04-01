# cancel_print_job.ps1
# V1.1.0 L1 Skill - Cancel print job(s)

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. Auto-elevate (using InputFile to avoid command line escaping issues)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
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
            $timeout = 100
            $elapsed = 0
            while (-not (Test-Path $outputFileParam) -and $elapsed -lt $timeout) {
                Start-Sleep -Milliseconds 100
                $elapsed++
            }
            if (Test-Path $outputFileParam) {
                $output = Get-Content $outputFileParam -Raw -Encoding UTF8
                Write-Output $output
                Remove-Item $outputFileParam -Force -ErrorAction SilentlyContinue
            } else {
                $errBody = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Admin process did not generate output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $errBody
            }
        }
        exit $process.ExitCode
    } catch {
        $errBody = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Elevation failed: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
        Write-Output $errBody
        exit 1
    }
}

# Handle InputFile (subprocess mode)
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

# 3. Budget guard
function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

try {
    # 4. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $Parameter = $script:SkillArgs.parameter
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }

    # 5. Check budget
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # 6. Core logic
    
    # Parameter validation
    if (-not $Parameter -or -not $Parameter.PSObject.Properties['printer_name']) {
        Emit-Error 'INVALID_ARGUMENT' 'Missing required parameter: printer_name' $false
        return
    }
    if (-not $Parameter.PSObject.Properties['job_id']) {
        Emit-Error 'INVALID_ARGUMENT' 'Missing required parameter: job_id' $false
        return
    }
    
    $printerName = $Parameter.printer_name
    $jobId = $Parameter.job_id
    
    # Validate job_id format
    if ($jobId -ne 'all') {
        $jobIdInt = 0
        if (-not [int]::TryParse($jobId.ToString(), [ref]$jobIdInt)) {
            Emit-Error 'INVALID_ARGUMENT' "job_id must be 'all' or a valid integer, got: $jobId" $false
            return
        }
    }
    
    $cancelledCount = 0
    $failedCount = 0
    $totalBefore = 0
    $fallbackUsed = $false

    $dryRun = if ($Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }
    
    # First verify printer exists
    try {
        $printer = Get-Printer -Name $printerName -ErrorAction Stop
    } catch {
        Emit-Error 'TARGET_NOT_FOUND' "Printer '$printerName' not found." $false
        return
    }

    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'
            would_perform_action = "Cancel print job(s) for printer '$printerName' (Job ID: $jobId)" 
        }
        return
    }

    try {
        # Primary path: Use PrintManagement module
        $jobs = @(Get-PrintJob -PrinterName $printerName -ErrorAction Stop)
        if ($jobId -ne 'all') {
            $jobIdInt = [int]$jobId
            $jobs = @($jobs | Where-Object { $_.Id -eq $jobIdInt })
        }
        $totalBefore = $jobs.Count
        
        foreach ($job in $jobs) {
            try {
                Remove-PrintJob -InputObject $job -ErrorAction Stop
                $cancelledCount++
            } catch {
                $failedCount++
            }
        }
    } catch {
        # Fallback path: Use WMI
        $fallbackUsed = $true
        try {
            $wmiJobs = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$printerName,*" })
            if ($jobId -ne 'all') {
                $jobIdInt = [int]$jobId
                $wmiJobs = @($wmiJobs | Where-Object { $_.JobId -eq $jobIdInt })
            }
            $totalBefore = $wmiJobs.Count

            foreach ($job in $wmiJobs) {
                try {
                    Invoke-CimMethod -InputObject $job -MethodName "Delete" -ErrorAction Stop | Out-Null
                    $cancelledCount++
                } catch {
                    $failedCount++
                }
            }
        } catch {
            Emit-Error 'ACTION_FAILED' "Failed to get or cancel print jobs using both primary and fallback methods. Reason: $($_.Exception.Message)" $false
            return
        }
    }

    if ($totalBefore -eq 0) {
        if ($jobId -ne 'all') {
            Emit-Error 'TARGET_NOT_FOUND' "Print job with ID $jobId not found on printer '$printerName'." $false
        } else {
            Emit-Success @{ 
                result = 'no_jobs_found'
                printer_name = $printerName
                message = "No print jobs found on printer '$printerName'." 
            }
        }
        return
    }
    
    # 7. Success output
    Emit-Success @{ 
        result = 'completed'
        printer_name = $printerName
        total_jobs_before = $totalBefore
        jobs_cancelled = $cancelledCount
        jobs_failed = $failedCount
    } @{ fallback_mode = $fallbackUsed }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
