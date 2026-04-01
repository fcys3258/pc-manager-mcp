# reset_audio_service.ps1
# V1.1.0 L1 Skill - Reset audio services

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
                $err = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Admin process did not generate output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $err
            }
        }
        exit $process.ExitCode
    } catch {
        $err = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Elevation failed: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
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

try {
    # 3. Parameter injection
    if ($InputObject) {
        $script:SkillArgs = $InputObject | ConvertFrom-Json
    } else {
        $script:SkillArgs = @{ metadata = @{} }
    }
    
    $Parameter = $script:SkillArgs.parameter
    
    # dry_run check
    $dryRun = if ($Parameter -and $Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }
    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'
            would_perform_action = "Restart AudioEndpointBuilder service (will also restart dependent Audiosrv)"
        }
        return
    }

    # 4. Core logic
    $results = @()
    
    # Restarting AudioEndpointBuilder will automatically restart dependent Audiosrv
    try {
        # First ensure service is not disabled
        $aeb = Get-Service -Name 'AudioEndpointBuilder' -ErrorAction Stop
        if ($aeb.StartType -eq 'Disabled') {
            Set-Service -Name 'AudioEndpointBuilder' -StartupType Automatic
            $results += @{
                service = 'AudioEndpointBuilder'
                action = 'enabled'
                previous_start_type = 'Disabled'
            }
        }
        
        # Restart service
        Restart-Service -Name 'AudioEndpointBuilder' -Force -ErrorAction Stop
        $results += @{
            service = 'AudioEndpointBuilder'
            action = 'restarted'
            status = 'success'
        }
    } catch {
        $results += @{
            service = 'AudioEndpointBuilder'
            action = 'restart_failed'
            error = $_.Exception.Message
        }
    }
    
    # Wait for service to stabilize
    Start-Sleep -Milliseconds 500
    
    # Check final status
    $finalStatus = @()
    foreach ($svcName in @('Audiosrv', 'AudioEndpointBuilder')) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            $finalStatus += @{
                name = $svcName
                status = $svc.Status.ToString()
                is_running = $svc.Status -eq 'Running'
            }
        } catch {
            $finalStatus += @{
                name = $svcName
                status = 'Error'
                error = $_.Exception.Message
            }
        }
    }

    # 5. Success output
    $runningServices = @($finalStatus | Where-Object { $_.is_running })
    $allRunning = $runningServices.Count -eq $finalStatus.Count
    
    Emit-Success @{
        result = if ($allRunning) { 'success' } else { 'partial_success' }
        actions = $results
        final_status = $finalStatus
        all_services_running = $allRunning
        note = "Audio services have been reset. Active audio sessions may have been interrupted."
    } @{ disruptive = $true }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
