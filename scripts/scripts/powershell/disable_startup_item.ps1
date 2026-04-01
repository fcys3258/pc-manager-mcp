# disable_startup_item.ps1
# V1.1.0 L1 Skill - Disable a startup item

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. Auto-elevate to administrator (using InputFile to avoid command line escaping issues)
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
            # Pass through existing InputFile
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
                $error = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Administrator process did not generate output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $error
            }
        }
        exit $process.ExitCode
    } catch {
        $error = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Elevation failed: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
        Write-Output $error
        exit 1
    }
}

# Process InputFile (child process mode)
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

    # Merge with metadata passed from host
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
    
    # Write to file if specified, otherwise output to stdout
    if ($script:OutputFilePath) {
        [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false))
    } else {
        Write-Output $json
    }
}

function Emit-Error($code, $message, $retriable = $false, $extraMeta = @{}) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true

    # Merge with metadata passed from host
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
    
    # Write to file if specified, otherwise output to stdout
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
    
    # Parameter validation
    if (-not $Parameter -or -not $Parameter.PSObject.Properties['startup_id']) {
        Emit-Error 'INVALID_ARGUMENT' 'Missing required parameter: startup_id' $false
        return
    }
    
    $startupId = $Parameter.startup_id
    if (-not $startupId) {
        Emit-Error 'INVALID_ARGUMENT' 'startup_id parameter cannot be empty' $false
        return
    }
    
    # Split using :: as delimiter (use -split with regex to handle :: properly)
    $parts = $startupId -split '::', 3
    if ($parts.Count -lt 3) {
        Emit-Error 'INVALID_ARGUMENT' "Invalid startup_id format. Expected 'TYPE::PATH::NAME'. Got $($parts.Count) parts." $false
        return
    }
    
    $type = $parts[0]
    $path = $parts[1]
    $name = $parts[2]

    $dryRun = if ($Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }
    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'; 
            would_perform_action = "Disable startup item '$name' of type '$type'" 
        }
        return
    }

    switch ($type) {
        "REGISTRY" {
            if (-not $path -or -not $name) {
                Emit-Error 'INVALID_ARGUMENT' "Registry path and name are required." $false
                return
            }
            if (Test-Path $path -PathType Container) {
                # Check if item exists
                $item = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
                if (-not $item) {
                    Emit-Error 'TARGET_NOT_FOUND' "Registry item '$name' not found at '$path'." $false
                    return
                }
                # Check if already disabled
                $disabledName = "$($name)_disabled"
                $disabledItem = Get-ItemProperty -Path $path -Name $disabledName -ErrorAction SilentlyContinue
                if ($disabledItem) {
                    Emit-Success @{ result = 'already_disabled'; reason = "Registry item '$name' is already disabled." }
                    return
                }
                Rename-ItemProperty -Path $path -Name $name -NewName $disabledName -ErrorAction Stop
                Emit-Success @{ result = 'disabled'; reason = "Registry item '$name' at '$path' was disabled." }
            } else {
                Emit-Error 'TARGET_NOT_FOUND' "Registry path '$path' not found." $false
            }
        }
        "TASK" {
            try {
                $task = Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop
                if ($task.State -eq 'Disabled') {
                    Emit-Success @{ result = 'already_disabled'; reason = "Scheduled task '$name' is already disabled." }
                    return
                }
                Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null
                Emit-Success @{ result = 'disabled'; reason = "Scheduled task '$name' was disabled." }
            } catch {
                Emit-Error 'TARGET_NOT_FOUND' "Scheduled task '$name' at path '$path' not found or could not be disabled." $false
            }
        }
        "FOLDER" {
            # For folders, the path is the full file path
            $filePath = $path
            if (Test-Path $filePath) {
                $dir = Split-Path -Path $filePath -Parent
                $disabledDir = Join-Path -Path $dir -ChildPath "disabled_startup"
                $fileName = Split-Path -Path $filePath -Leaf
                $targetPath = Join-Path -Path $disabledDir -ChildPath $fileName
                
                # Check if already disabled
                if (Test-Path $targetPath) {
                    Emit-Success @{ result = 'already_disabled'; reason = "Startup file '$fileName' is already in disabled folder." }
                    return
                }
                
                if (-not (Test-Path $disabledDir)) {
                    New-Item -Path $disabledDir -ItemType Directory | Out-Null
                }
                Move-Item -Path $filePath -Destination $disabledDir -Force
                Emit-Success @{ result = 'disabled'; reason = "Startup file '$filePath' was moved to disabled folder." }
            } else {
                Emit-Error 'TARGET_NOT_FOUND' "Startup file '$filePath' not found." $false
            }
        }
        default {
            Emit-Error 'INVALID_ARGUMENT' "Unknown startup item type '$type'." $false
        }
    }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
