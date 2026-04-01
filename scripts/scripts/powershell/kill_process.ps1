# kill_process.ps1
# V1.1.0 L1 Skill - Kill process by PID or process_key

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

# UAC elevation block (using InputFile to avoid command line escaping issues)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $outputFileParam = if ($OutputFile) { $OutputFile } else { Join-Path $env:TEMP "ps_output_$([guid]::NewGuid()).json" }
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
        
        $inputFileTemp = $null
        if ($InputObject) {
            # InputObject provided via command line, write to temp file
            $inputFileTemp = Join-Path $env:TEMP "ps_input_$([guid]::NewGuid()).json"
            [System.IO.File]::WriteAllText($inputFileTemp, $InputObject, [System.Text.UTF8Encoding]::new($false))
            $argList += "-InputFile"
            $argList += $inputFileTemp
        } elseif ($InputFile -and (Test-Path $InputFile)) {
            # InputFile provided directly, pass it through
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
                $errResult = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Admin process did not generate output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $errResult
            }
        }
        exit $process.ExitCode
    } catch {
        $errResult = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Elevation failed: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
        Write-Output $errResult
        exit 1
    }
}

# Handle InputFile (subprocess mode)
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

# Helper function to get process tree
function Get-ProcessTree($rootPid, $accumulatedPids) {
    $accumulatedPids += $rootPid
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$rootPid" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        if ($child.ProcessId -notin $accumulatedPids) {
            $accumulatedPids = Get-ProcessTree $child.ProcessId $accumulatedPids
        }
    }
    return $accumulatedPids
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
    $processKey = if ($Parameter.PSObject.Properties['process_key']) { $Parameter.process_key } else { $null }
    $processPid = if ($Parameter.PSObject.Properties['pid']) { $Parameter.pid } else { $null }
    $force = if ($Parameter.PSObject.Properties['force']) { $Parameter.force } else { $false }
    $killTree = if ($Parameter.PSObject.Properties['kill_tree']) { $Parameter.kill_tree } else { $false }
    $dryRun = if ($Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }

    $targetPid = $null
    $targetStartTime = $null

    if ($processKey) {
        $parts = $processKey -split ':', 2
        $targetPid = [int]$parts[0]
        if ($parts.Length -gt 1) {
            $targetStartTime = $parts[1]
        }
    } elseif ($processPid) {
        $targetPid = [int]$processPid
    } else {
        Emit-Error 'INVALID_ARGUMENT' 'Either process_key or pid must be provided.' $false
        return
    }

    $process = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
    if (-not $process) {
        Emit-Success @{ result = 'not_found'; reason = "Process with PID $targetPid not found." }
        return
    }

    # Validate StartTime if provided
    if ($targetStartTime -and $targetStartTime -ne 'Unknown') {
        if ($process.PSObject.Properties['StartTime'] -and $process.StartTime) {
            $actualStartTime = $process.StartTime.ToString('yyyy-MM-ddTHH:mm:ss')
            if ($actualStartTime -ne $targetStartTime) {
                Emit-Success @{ result = 'not_found'; reason = "Process found but start time mismatch." }
                return
            }
        }
    }

    # Safety Checks - Critical system processes
    $criticalProcesses = @('csrss', 'wininit', 'lsass', 'winlogon', 'smss', 'services', 'svchost', 'System', 'Registry', 'MsMpEng', 'SecurityHealthService', 'TrustedInstaller', 'dwm', 'fontdrvhost', 'conhost')
    $processName = if ($process.PSObject.Properties['ProcessName']) { $process.ProcessName } else { "Unknown" }
    
    if ($criticalProcesses -contains $processName) {
        Emit-Success @{ result = 'denied'; reason = "Critical system process." }
        return
    }

    # Identify all PIDs to kill
    $pidsToKill = @($targetPid)
    if ($killTree) {
        $pidsToKill = Get-ProcessTree $targetPid @()
    }

    $processList = @()
    foreach ($pidVal in $pidsToKill) {
        $pName = "Unknown"
        try { $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue; if($p){$pName=$p.ProcessName} } catch {}
        $processList += @{ pid = $pidVal; name = $pName }
    }

    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'
            would_perform_action = "Kill process(es)"
            targets = $processList
            force = $force
            kill_tree = $killTree
        }
        return
    }

    # Execute Kill
    $killed = @()
    $failed = @()

    foreach ($pidVal in $pidsToKill) {
        try {
            $params = @{ Id = $pidVal; ErrorAction = 'Stop' }
            if ($force) { $params['Force'] = $true }
            Stop-Process @params
            $killed += $pidVal
        } catch {
            $failed += @{ pid = $pidVal; error = $_.Exception.Message }
        }
    }

    if ($failed.Count -eq 0) {
        Emit-Success @{ result = 'killed'; targets = $killed }
    } else {
        Emit-Success @{ result = 'partial_success'; killed = $killed; failed = $failed }
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
