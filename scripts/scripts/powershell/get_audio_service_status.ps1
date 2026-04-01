# get_audio_service_status.ps1
# V1.1.0 L1 Skill - Get audio service status

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
    $audioServices = @()
    $serviceNames = @('Audiosrv', 'AudioEndpointBuilder', 'AudioSes')
    
    foreach ($svcName in $serviceNames) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            $audioServices += @{
                name = $svc.Name
                display_name = $svc.DisplayName
                status = $svc.Status.ToString()
                start_type = $svc.StartType.ToString()
                can_stop = $svc.CanStop
                is_running = $svc.Status -eq 'Running'
                is_disabled = $svc.StartType -eq 'Disabled'
            }
        } catch {
            # Service may not exist (e.g., AudioSes on some versions)
            $audioServices += @{
                name = $svcName
                status = 'NotFound'
                is_running = $false
            }
        }
    }
    
    # Check audio endpoint devices
    $audioDevices = @()
    try {
        $pnpAudio = @(Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue)
        foreach ($dev in $pnpAudio) {
            $problemCode = if ($dev.PSObject.Properties['ProblemCode']) { $dev.ProblemCode } else { 0 }
            $audioDevices += @{
                friendly_name = $dev.FriendlyName
                status = $dev.Status
                instance_id = $dev.InstanceId
                class = $dev.Class
                problem_code = $problemCode
            }
        }
    } catch { }
    
    # Check default audio device (via registry)
    $defaultPlayback = $null
    $defaultRecording = $null
    try {
        $audioReg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Multimedia\Sound Mapper' -ErrorAction SilentlyContinue
        if ($audioReg) {
            $defaultPlayback = if ($audioReg.PSObject.Properties['Playback']) { $audioReg.Playback } else { $null }
            $defaultRecording = if ($audioReg.PSObject.Properties['Record']) { $audioReg.Record } else { $null }
        }
    } catch { }

    # 5. Evaluate overall status
    $foundServices = @($audioServices | Where-Object { $_.status -ne 'NotFound' })
    $runningServices = @($audioServices | Where-Object { $_.is_running -eq $true })
    $disabledServices = @($audioServices | Where-Object { $_.ContainsKey('is_disabled') -and $_.is_disabled -eq $true })
    $problematicDevices = @($audioDevices | Where-Object { $_.status -ne 'OK' -and $_.ContainsKey('problem_code') -and $_.problem_code -ne 0 })
    
    $allRunning = $runningServices.Count -eq $foundServices.Count
    $anyDisabled = $disabledServices.Count -gt 0
    $hasProblematicDevices = $problematicDevices.Count -gt 0
    
    $overallStatus = 'healthy'
    $issues = @()
    
    if (-not $allRunning) {
        $overallStatus = 'degraded'
        $issues += 'Some audio services are not running'
    }
    if ($anyDisabled) {
        $overallStatus = 'degraded'
        $issues += 'Some audio services are disabled'
    }
    if ($hasProblematicDevices) {
        $overallStatus = 'degraded'
        $issues += 'Some audio devices have problems'
    }
    
    Emit-Success @{
        services = $audioServices
        devices = $audioDevices
        device_count = $audioDevices.Count
        default_playback = $defaultPlayback
        default_recording = $defaultRecording
        overall_status = $overallStatus
        issues = $issues
        all_services_running = $allRunning
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
