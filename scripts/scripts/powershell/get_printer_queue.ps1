# get_printer_queue.ps1
# V1.1.0 L1 Skill - Get printer queue jobs

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

# 3. Budget guard
function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

# Handle InputFile (for subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

try {
    # 4. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    if (-not $script:SkillArgs) {
        Emit-Error 'INVALID_ARGUMENT' 'Invalid or empty SkillArgs JSON payload.' $false
        return
    }
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
    $printerName = if ($Parameter.PSObject.Properties['printer_name']) { $Parameter.printer_name } else { $null }
    if (-not $printerName) {
        Emit-Error 'INVALID_ARGUMENT' 'Parameter "printer_name" is required.' $false
        return
    }
    
    $statusFilter = if ($Parameter.PSObject.Properties['status_filter']) { $Parameter.status_filter } else { $null }
    
    # Verify printer exists and get info
    $driverName = $null
    $portName = $null
    $printer = $null
    try {
        $printer = Get-Printer -Name $printerName -ErrorAction Stop
        $driverName = $printer.DriverName
        $portName = $printer.PortName
    } catch {
        # Try WMI fallback to check printer existence
        $wmiPrinter = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $printerName }) | Select-Object -First 1
        if (-not $wmiPrinter) {
            Emit-Error 'TARGET_NOT_FOUND' "Printer '$printerName' not found." $false
            return
        }
        $driverName = $wmiPrinter.DriverName
        $portName = if ($wmiPrinter.PSObject.Properties['PortName']) { $wmiPrinter.PortName } else { $null }
    }
    
    $jobs = @()
    $fallback = $false
    try {
        # Primary path: Get-PrintJob
        $printJobs = @(Get-PrintJob -PrinterName $printerName -ErrorAction Stop)
        foreach ($job in $printJobs) {
            $st = $job.JobStatus.ToString()
            
            if ($statusFilter -and ($st -ne $statusFilter)) { continue }

            $submittedTime = if ($job.PSObject.Properties['SubmittedTime'] -and $job.SubmittedTime) {
                $job.SubmittedTime.ToString('o')
            } else { $null }
            
            $jobs += @{
                job_id = $job.Id
                document_name = $job.DocumentName
                owner = $job.UserName
                pages_printed = $job.PagesPrinted
                total_pages = $job.TotalPages
                size_bytes = $job.Size
                submitted_time = $submittedTime
                status = $st
                driver_name = $driverName
                port_name = $portName
            }
        }
    } catch {
        # Fallback path: Win32_PrintJob
        $fallback = $true
        $wmiJobs = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$printerName,*" })
        foreach ($job in $wmiJobs) {
            $st = if ($job.PSObject.Properties['JobStatus']) { $job.JobStatus } else { "Unknown" }
            if ($statusFilter -and ($st -ne $statusFilter)) { continue }

            $timeSubmitted = if ($job.PSObject.Properties['TimeSubmitted'] -and $job.TimeSubmitted) {
                $job.TimeSubmitted.ToString('o')
            } else { $null }
            
            $jobs += @{
                job_id = $job.JobId
                document_name = $job.Document
                owner = $job.Owner
                pages_printed = if ($job.PSObject.Properties['PagesPrinted']) { $job.PagesPrinted } else { 0 }
                total_pages = if ($job.PSObject.Properties['TotalPages']) { $job.TotalPages } else { 0 }
                size_bytes = if ($job.PSObject.Properties['Size']) { $job.Size } else { 0 }
                submitted_time = $timeSubmitted
                status = $st
                driver_name = $driverName
                port_name = $portName
            }
        }
    }
    
    Emit-Success @{ 
        printer_name = $printerName
        printer_queue = $jobs
        job_count = $jobs.Count
    } @{ fallback_mode = $fallback }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
