# get_usb_info.ps1
# V1.1.0 L1 Skill - Get USB device information

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

try {
    # 3. Parameter injection
    if ($InputFile -and (Test-Path $InputFile)) {
        $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
    }
    $script:SkillArgs = $InputObject | ConvertFrom-Json

    # 4. Core logic - Get USB device information
    $usbDevices = @()

    # Find all PnP USB devices, filter for USB storage devices
    $pnpDevices = @(Get-PnpDevice -Class 'USB' -ErrorAction SilentlyContinue)

    if ($pnpDevices.Count -gt 0) {
        # Filter USB storage devices
        $pnpDevices = @($pnpDevices | Where-Object {
            $service = if ($_.PSObject.Properties['Service']) { $_.Service } else { $null }
            $status = if ($_.PSObject.Properties['Status']) { $_.Status } else { $null }
            $present = if ($_.PSObject.Properties['Present']) { $_.Present } else { $false }
            
            $service -eq 'USBSTOR' -and $status -eq 'OK' -and $present -eq $true
        })

        foreach ($device in $pnpDevices) {
            $vid = $null
            $pid = $null

            # Extract VID and PID from InstanceId (e.g. 'USB\VID_0781&PID_5581\\...')
            if ($device.PSObject.Properties['InstanceId'] -and $device.InstanceId) {
                if ($device.InstanceId -match 'VID_([0-9A-Fa-f]{4})') {
                    $vid = $Matches[1]
                }
                if ($device.InstanceId -match 'PID_([0-9A-Fa-f]{4})') {
                    $pid = $Matches[1]
                }
            }
            
            # Safely access device properties
            $friendlyName = if ($device.PSObject.Properties['FriendlyName']) { $device.FriendlyName } else { "Unknown" }
            $manufacturer = if ($device.PSObject.Properties['Manufacturer']) { $device.Manufacturer } else { "Unknown" }
            $service = if ($device.PSObject.Properties['Service']) { $device.Service } else { "Unknown" }
            $instanceId = if ($device.PSObject.Properties['InstanceId']) { $device.InstanceId } else { "Unknown" }

            $usbDevices += @{
                pnp_device_id = $instanceId
                friendly_name = $friendlyName
                manufacturer = $manufacturer
                vid = $vid
                pid = $pid
                service = $service
            }
        }
    }

    # 5. Success output
    Emit-Success @{ usb_storage_devices = $usbDevices }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
