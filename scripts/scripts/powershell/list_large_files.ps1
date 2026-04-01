# list_large_files.ps1
# V1.1.0 L1 Skill - List large files (Optimized)

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Helper: Check if path requires elevation (system protected directories)
function Test-NeedsElevation($targetPath) {
    $systemPaths = @(
        $env:windir,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData
    )
    try {
        $resolvedPath = (Resolve-Path $targetPath -ErrorAction SilentlyContinue).Path
        if (-not $resolvedPath) { return $false }
        foreach ($sp in $systemPaths) {
            if ($sp -and $resolvedPath.StartsWith($sp, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    } catch {}
    return $false
}

# Extract path from input for elevation check
$checkPath = $null
if ($InputFile -and (Test-Path $InputFile)) {
    try {
        $tempInput = Get-Content $InputFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($tempInput.parameter -and $tempInput.parameter.PSObject.Properties['path']) {
            $checkPath = $tempInput.parameter.path
        }
    } catch {}
} elseif ($InputObject) {
    try {
        $tempInput = $InputObject | ConvertFrom-Json
        if ($tempInput.parameter -and $tempInput.parameter.PSObject.Properties['path']) {
            $checkPath = $tempInput.parameter.path
        }
    } catch {}
}

# 0. Conditional auto-elevate (only for system directories)
$needsElevation = $checkPath -and (Test-NeedsElevation $checkPath)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($needsElevation -and -not $isAdmin) {
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
                $err = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Admin process did not generate output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $err
            }
        }
        exit $process.ExitCode
    } catch {
        $err = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Privilege elevation failed: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
        Write-Output $err
        exit 1
    }
}

# Handle InputFile (subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

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
    $path = if ($Parameter -and $Parameter.PSObject.Properties['path']) { $Parameter.path } else { $null }
    if (-not $path) {
        Emit-Error 'MISSING_PARAMETER' 'Parameter "path" is required.'
        return
    }

    $limit = if ($Parameter -and $Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 20 }
    $maxDepth = if ($Parameter -and $Parameter.PSObject.Properties['max_depth']) { $Parameter.max_depth } else { 3 }

    if (-not (Test-Path $path -PathType Container)) {
        Emit-Error 'PATH_NOT_FOUND' "Directory '$path' not found."
        return
    }

    if ($limit -le 0) { $limit = 20 }

    $totalCount = 0
    $topFiles = [System.Collections.ArrayList]@()
    $minSize = 0

    # Use -Depth to limit recursion
    $enumerator = Get-ChildItem $path -Recurse -Depth $maxDepth -File -Force -ErrorAction SilentlyContinue

    foreach ($file in $enumerator) {
        $totalCount++

        if (-not (Test-Budget $__sw $BudgetMs)) {
            Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget during directory scan." $true @{
                scanned_items = $totalCount
                current_top_count = $topFiles.Count
            }
            return
        }

        if ($topFiles.Count -lt $limit) {
            [void]$topFiles.Add($file)
            if ($topFiles.Count -eq $limit) {
                $minSize = ($topFiles | Measure-Object -Property Length -Minimum).Minimum
            }
        } else {
            if ($file.Length -le $minSize) {
                continue
            }
            [void]$topFiles.Add($file)
            $sorted = @($topFiles | Sort-Object Length -Descending | Select-Object -First $limit)
            $topFiles.Clear()
            $sorted | ForEach-Object { [void]$topFiles.Add($_) }
            $minSize = $sorted[-1].Length
        }
    }

    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget while building result." $true @{
            scanned_items = $totalCount
            current_top_count = $topFiles.Count
        }
        return
    }

    $sortedFiles = @($topFiles | Sort-Object Length -Descending)

    $largeFiles = @()
    foreach ($file in $sortedFiles) {
        $largeFiles += @{
            path = $file.FullName
            size_mb = [math]::Round($file.Length / 1MB, 2)
            last_write_time = $file.LastWriteTime.ToString('o')
        }
    }

    $truncated = ($totalCount -gt $largeFiles.Count)

    Emit-Success @{ large_files = $largeFiles } @{
        truncated = $truncated
        total_items = $totalCount
        scan_depth_limit = $maxDepth
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
