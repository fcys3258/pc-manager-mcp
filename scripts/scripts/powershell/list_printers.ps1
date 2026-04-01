# list_printers.ps1
# V1.1.0 L1 Skill - List installed printers

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
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }

    # 5. Check budget
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # 6. Core logic
    $Parameter = $script:SkillArgs.parameter
    $limit = if ($Parameter -and $Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 50 }
    $sortBy = if ($Parameter -and $Parameter.PSObject.Properties['sort_by']) { $Parameter.sort_by } else { 'name' }

    $printers = @()
    $fallback = $false
    try {
        # Primary path: Get-Printer
        $printerList = @(Get-Printer -ErrorAction Stop)
        foreach ($p in $printerList) {
            $printers += @{
                name = $p.Name
                status = $p.PrinterStatus.ToString()
                is_default = $p.IsDefault
                driver_name = $p.DriverName
                port_name = if ($p.PSObject.Properties['PortName']) { $p.PortName } else { $null }
                shared = if ($p.PSObject.Properties['Shared']) { $p.Shared } else { $false }
            }
        }
    } catch {
        # Fallback path: Win32_Printer
        $fallback = $true
        $wmiPrinters = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue)
        foreach ($p in $wmiPrinters) {
            $printers += @{
                name = $p.Name
                status = if ($p.PSObject.Properties['PrinterState']) { $p.PrinterState.ToString() } else { "Unknown" }
                is_default = if ($p.PSObject.Properties['Default']) { $p.Default } else { $false }
                driver_name = $p.DriverName
                port_name = if ($p.PSObject.Properties['PortName']) { $p.PortName } else { $null }
                shared = if ($p.PSObject.Properties['Shared']) { $p.Shared } else { $false }
            }
        }
    }
    
    # Sort
    $sortedPrinters = switch ($sortBy) {
        'status' { $printers | Sort-Object { $_.status } }
        'driver_name' { $printers | Sort-Object { $_.driver_name } }
        default { $printers | Sort-Object { $_.name } }
    }

    # Limit
    $limitedPrinters = @($sortedPrinters | Select-Object -First $limit)

    # 7. Success output
    Emit-Success @{ 
        printers = $limitedPrinters
        total_found = $printers.Count
        returned_count = $limitedPrinters.Count
    } @{ fallback_mode = $fallback }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
