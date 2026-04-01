# get_monitor_topology.ps1
# V1.1.0 L1 Skill - Get monitor topology

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
    $monitors = @()
    $videoControllers = @()
    
    # Get video controller info (current resolution)
    try {
        $vcs = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        foreach ($vc in $vcs) {
            $adapterRam = if ($vc.PSObject.Properties['AdapterRAM'] -and $vc.AdapterRAM) { 
                [math]::Round($vc.AdapterRAM / 1MB, 0) 
            } else { $null }
            $driverDate = if ($vc.PSObject.Properties['DriverDate'] -and $vc.DriverDate) { 
                $vc.DriverDate.ToString('o') 
            } else { $null }
            
            $videoControllers += @{
                name = $vc.Name
                adapter_ram_mb = $adapterRam
                driver_version = $vc.DriverVersion
                driver_date = $driverDate
                current_horizontal_resolution = $vc.CurrentHorizontalResolution
                current_vertical_resolution = $vc.CurrentVerticalResolution
                current_refresh_rate = $vc.CurrentRefreshRate
                current_bits_per_pixel = $vc.CurrentBitsPerPixel
                video_mode = $vc.VideoModeDescription
                status = $vc.Status
            }
        }
    } catch { }
    
    # Get monitor physical parameters (WMI)
    try {
        $monitorParams = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue)
        $monitorIds = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
        
        $idx = 0
        foreach ($mp in $monitorParams) {
            $monitorId = $monitorIds | Where-Object { $_.InstanceName -eq $mp.InstanceName } | Select-Object -First 1
            
            # Decode manufacturer name and product code
            $manufacturer = $null
            $productCode = $null
            $serialNumber = $null
            $friendlyName = $null
            
            if ($monitorId) {
                if ($monitorId.ManufacturerName) {
                    $manufacturer = -join ($monitorId.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                }
                if ($monitorId.ProductCodeID) {
                    $productCode = -join ($monitorId.ProductCodeID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                }
                if ($monitorId.SerialNumberID) {
                    $serialNumber = -join ($monitorId.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                }
                if ($monitorId.UserFriendlyName) {
                    $friendlyName = -join ($monitorId.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                }
            }
            
            # Calculate physical size (cm to inch)
            $widthCm = $mp.MaxHorizontalImageSize
            $heightCm = $mp.MaxVerticalImageSize
            $diagonalInch = if ($widthCm -gt 0 -and $heightCm -gt 0) {
                [math]::Round([math]::Sqrt($widthCm * $widthCm + $heightCm * $heightCm) / 2.54, 1)
            } else { $null }
            
            $monitors += @{
                index = $idx
                instance_name = $mp.InstanceName
                manufacturer = $manufacturer
                product_code = $productCode
                serial_number = $serialNumber
                friendly_name = $friendlyName
                active = $mp.Active
                width_cm = $widthCm
                height_cm = $heightCm
                diagonal_inch = $diagonalInch
                display_transfer_characteristics = $mp.DisplayTransferCharacteristic
            }
            $idx++
        }
    } catch { }
    
    # Get desktop configuration
    $desktopInfo = $null
    try {
        $desktopArr = @(Get-CimInstance Win32_Desktop -ErrorAction SilentlyContinue)
        $desktop = if ($desktopArr.Count -gt 0) { $desktopArr[0] } else { $null }
        if ($desktop) {
            $wallpaper = if ($desktop.PSObject.Properties['Wallpaper']) { $desktop.Wallpaper } else { $null }
            $ssActive = if ($desktop.PSObject.Properties['ScreenSaverActive']) { $desktop.ScreenSaverActive } else { $null }
            $ssTimeout = if ($desktop.PSObject.Properties['ScreenSaverTimeout']) { $desktop.ScreenSaverTimeout } else { $null }
            $desktopInfo = @{
                wallpaper = $wallpaper
                screen_saver_active = $ssActive
                screen_saver_timeout = $ssTimeout
            }
        }
    } catch { }
    
    # Detect primary monitor
    $primaryMonitor = $null
    if ($videoControllers.Count -gt 0) {
        $primary = $videoControllers[0]
        $primaryMonitor = @{
            resolution = "$($primary.current_horizontal_resolution)x$($primary.current_vertical_resolution)"
            refresh_rate = $primary.current_refresh_rate
            adapter_name = $primary.name
        }
    }

    # 5. Success output
    Emit-Success @{
        monitors = $monitors
        monitor_count = $monitors.Count
        video_controllers = $videoControllers
        video_controller_count = $videoControllers.Count
        primary_display = $primaryMonitor
        desktop = $desktopInfo
        is_multi_monitor = $monitors.Count -gt 1 -or $videoControllers.Count -gt 1
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
