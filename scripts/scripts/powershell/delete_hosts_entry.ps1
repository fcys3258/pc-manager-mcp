# delete_hosts_entry.ps1
# V1.1.0 L1 Skill - Delete Hosts File Entry

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. Auto-elevate to Administrator (using InputFile to avoid command line escaping issues)
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
                $errJson = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Elevated process did not produce output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $errJson
            }
        }
        exit $process.ExitCode
    } catch {
        $errJson = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Failed to elevate privileges: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
        Write-Output $errJson
        exit 1
    }
}

# Handle InputFile (child process mode or direct call)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# Validate InputObject
if (-not $InputObject -or $InputObject.Trim() -eq '') {
    $errJson = @{ok=$false;data=$null;error=@{code="INVALID_INPUT";message="InputObject is empty. Provide JSON via parameter or InputFile.";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
    Write-Output $errJson
    exit 1
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

try {
    # 3. Parse input parameters
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $Parameter = $script:SkillArgs.parameter

    # dry_run check
    $dryRun = if ($Parameter -and $Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }

    # Validate parameters
    $hostname = $null
    if ($Parameter -and $Parameter.PSObject.Properties['hostname']) {
        $hostname = $Parameter.hostname
    }
    if (-not $hostname) {
        Emit-Error 'INVALID_ARGUMENT' 'Parameter "hostname" is required.' $false
        return
    }

    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'
            would_perform_action = "Delete hosts entry for hostname: $hostname"
        }
        return
    }

    # 4. Core logic
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

    if (-not (Test-Path $hostsPath)) {
        Emit-Error 'FILE_NOT_FOUND' "Hosts file not found at: $hostsPath" $false
        return
    }

    # Create backup
    $backupPath = "$hostsPath.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $hostsPath $backupPath -Force -ErrorAction Stop

    # Read and process hosts file
    $originalContent = Get-Content $hostsPath -Encoding UTF8 -ErrorAction Stop
    $newLines = @()
    $removedCount = 0

    foreach ($line in $originalContent) {
        $trimmed = $line.Trim()
        
        # Keep empty lines and comment lines
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            $newLines += $line
            continue
        }
        
        # Check if line contains target hostname
        # Use regex: IP address followed by whitespace, then target hostname (at end or followed by space/other hostnames)
        if ($trimmed -match "^\s*\d+\.\d+\.\d+\.\d+\s+.*\b$([regex]::Escape($hostname))\b") {
            $removedCount++
            continue  # Skip this line
        }
        
        $newLines += $line
    }

    if ($removedCount -eq 0) {
        # Remove backup (no changes made)
        Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
        Emit-Success @{
            deleted_hostname = $hostname
            removed_lines = 0
            backup_path = $null
            message = "Hostname '$hostname' not found in hosts file"
        }
        return
    }

    # Write new content
    Set-Content $hostsPath -Value $newLines -Encoding UTF8 -ErrorAction Stop

    # 5. Success output
    Emit-Success @{
        deleted_hostname = $hostname
        removed_lines = $removedCount
        backup_path = $backupPath
        message = "Successfully removed $removedCount line(s) containing '$hostname'"
    } @{ reversible = $true }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
