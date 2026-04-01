# get_app_last_used_time.ps1
# V1.1.0 L1 Skill - Get application last used time from Prefetch files

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. UAC elevation for Prefetch directory access
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $outputFile = Join-Path $env:TEMP "ps_output_$([guid]::NewGuid()).json"
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
        $argList += $outputFile
        
        $process = Start-Process powershell -Verb RunAs -ArgumentList $argList -PassThru -Wait
        
        if ($inputFileTemp -and (Test-Path $inputFileTemp)) {
            Remove-Item $inputFileTemp -Force -ErrorAction SilentlyContinue
        }
        
        $timeout = 100
        $elapsed = 0
        while (-not (Test-Path $outputFile) -and $elapsed -lt $timeout) {
            Start-Sleep -Milliseconds 100
            $elapsed++
        }
        if (Test-Path $outputFile) {
            $output = Get-Content $outputFile -Raw -Encoding UTF8
            Write-Output $output
            Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        } else {
            $errorJson = @{
                ok = $false
                data = $null
                error = @{ code = "ELEVATION_OUTPUT_MISSING"; message = "Admin process did not generate output file"; retriable = $false }
                metadata = @{ exec_time_ms = 0; skill_version = "1.1.0" }
            } | ConvertTo-Json -Compress
            Write-Output $errorJson
        }
        exit $process.ExitCode
    } catch {
        $errorJson = @{
            ok = $false
            data = $null
            error = @{ code = "ELEVATION_FAILED"; message = "Elevation failed: $_"; retriable = $false }
            metadata = @{ exec_time_ms = 0; skill_version = "1.1.0" }
        } | ConvertTo-Json -Compress
        Write-Output $errorJson
        exit 1
    }
}

# 1. Strict mode and environment setup
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# Handle InputFile if provided (elevated process)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# 2. JSON output functions
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

    # 5. Budget check
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded before scanning." $true
        return
    }

    # 6. Core logic - Analyze Windows Prefetch files
    $prefetchPath = "$env:SystemRoot\Prefetch"
    $limit = if ($Parameter -and $Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 30 }

    if (-not (Test-Path $prefetchPath)) {
        Emit-Error 'PATH_NOT_FOUND' "Prefetch directory not found: $prefetchPath" $false
        return
    }

    $apps = @()
    $pfFiles = @(Get-ChildItem $prefetchPath -Filter '*.pf' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $limit)

    foreach ($file in $pfFiles) {
        # Budget check
        if (-not (Test-Budget $__sw $BudgetMs)) {
            Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded during scanning." $true
            return
        }
        
        # Extract app name from filename (format: APPNAME-HASH.pf)
        $baseName = $file.BaseName
        $appName = $baseName -replace '-[A-F0-9]{8}$', ''
        
        $apps += @{
            app_name = $appName
            last_used = $file.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            last_used_friendly = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            prefetch_file = $file.Name
            file_size_bytes = $file.Length
        }
    }

    # 7. Success output
    Emit-Success @{
        apps = $apps
        total_count = $apps.Count
        prefetch_path = $prefetchPath
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
