# get_usb_storage_devices.ps1
# V1.1.0 L1 Skill - Get USB storage device list

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

    # 4. Core logic - Get USB storage devices
    $devices = @()
    
    # Get devices with USBSTOR service (USB storage devices)
    $usbDevices = @(Get-PnpDevice -ErrorAction SilentlyContinue | 
        Where-Object { $_.Service -eq 'USBSTOR' -and $_.Present })
    
    foreach ($device in $usbDevices) {
        $instanceId = $device.InstanceId
        
        # Extract VID/PID from InstanceId
        $vid = $null
        $pid = $null
        
        if ($instanceId -match 'VID_([0-9A-Fa-f]{4})') {
            $vid = $matches[1].ToUpper()
        }
        if ($instanceId -match 'PID_([0-9A-Fa-f]{4})') {
            $pid = $matches[1].ToUpper()
        }
        
        $devices += @{
            friendly_name = $device.FriendlyName
            status = $device.Status
            instance_id = $instanceId
            vid = $vid
            pid = $pid
            class = $device.Class
            manufacturer = $device.Manufacturer
        }
    }
    
    # Also get corresponding disk drive information
    $diskDrives = @()
    try {
        $usbDisks = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | 
            Where-Object { $_.InterfaceType -eq 'USB' })
        
        foreach ($disk in $usbDisks) {
            $diskDrives += @{
                model = $disk.Model
                serial_number = $disk.SerialNumber
                size_gb = [math]::Round($disk.Size / 1GB, 2)
                interface_type = $disk.InterfaceType
                media_type = $disk.MediaType
            }
        }
    } catch {
        # Ignore errors when getting disk information
    }

    # 5. Success output
    Emit-Success @{
        devices = $devices
        disk_drives = $diskDrives
        device_count = $devices.Count
        disk_count = $diskDrives.Count
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
