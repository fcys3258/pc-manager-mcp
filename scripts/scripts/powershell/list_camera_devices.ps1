# # list_camera_devices.ps1
# # V1.1.0 L1 Skill - List camera devices

# param(
#     [Parameter(Position=0)]
#     [string]$InputObject = "",
#     [string]$OutputFile = "",
#     [string]$InputFile = ""
# )

# Set-StrictMode -Version Latest
# $ErrorActionPreference = 'Stop'
# [Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# $global:__hasEmitted = $false
# $__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
# $script:SkillArgs = $null
# $script:OutputFilePath = $OutputFile

# function Emit-Success($data, $extraMeta = @{}) {
#     if ($global:__hasEmitted) { return }
#     $global:__hasEmitted = $true
#     $finalMetadata = @{}
#     if ($script:SkillArgs -and $script:SkillArgs.metadata) {
#         $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object {
#             $finalMetadata[$_.Name] = $_.Value
#         }
#     }
#     $extraMeta.GetEnumerator() | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
#     $finalMetadata['exec_time_ms'] = $__sw.ElapsedMilliseconds
#     $finalMetadata['skill_version'] = "1.1.0"
#     $body = @{ ok = $true; data = $data; error = $null; metadata = $finalMetadata }
#     $json = $body | ConvertTo-Json -Depth 6 -Compress
#     if ($script:OutputFilePath) {
#         [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false))
#     } else {
#         Write-Output $json
#     }
# }

# function Emit-Error($code, $message, $retriable = $false, $extraMeta = @{}) {
#     if ($global:__hasEmitted) { return }
#     $global:__hasEmitted = $true
#     $finalMetadata = @{}
#     if ($script:SkillArgs -and $script:SkillArgs.metadata) {
#         $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object {
#             $finalMetadata[$_.Name] = $_.Value
#         }
#     }
#     $extraMeta.GetEnumerator() | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
#     $finalMetadata['exec_time_ms'] = $__sw.ElapsedMilliseconds
#     $finalMetadata['skill_version'] = "1.1.0"
#     $body = @{ ok = $false; data = $null; error = @{ code = $code; message = $message; retriable = [bool]$retriable }; metadata = $finalMetadata }
#     $json = $body | ConvertTo-Json -Depth 6 -Compress
#     if ($script:OutputFilePath) {
#         [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false))
#     } else {
#         Write-Output $json
#     }
# }

# try {
#     if ($InputFile -and (Test-Path $InputFile)) {
#         $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
#     }
#     $script:SkillArgs = $InputObject | ConvertFrom-Json
#     $Parameter = $script:SkillArgs.parameter
    
#     $includeVirtual = $false
#     if ($Parameter -and $Parameter.PSObject.Properties['include_virtual']) { 
#         $includeVirtual = $Parameter.include_virtual 
#     }

#     $cameras = @()
#     $virtualPatterns = @('*Virtual*', '*OBS*', '*ManyCam*', '*XSplit*', '*Snap Camera*', '*CamTwist*', '*SplitCam*', '*Webcamoid*', '*NDI*')
    
#     try {
#         $cameraDevices = @(Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue)
#         foreach ($dev in $cameraDevices) {
#             $isVirtual = $false
#             foreach ($pattern in $virtualPatterns) {
#                 if ($dev.FriendlyName -like $pattern -or $dev.Manufacturer -like $pattern) {
#                     $isVirtual = $true
#                     break
#                 }
#             }
#             if ($isVirtual -and -not $includeVirtual) { continue }
#             $problemCode = if ($dev.PSObject.Properties['ProblemCode']) { $dev.ProblemCode } else { 0 }
#             $isPresent = if ($dev.PSObject.Properties['Present']) { $dev.Present } else { $true }
#             $cameras += @{
#                 friendly_name = $dev.FriendlyName
#                 status = $dev.Status
#                 instance_id = $dev.InstanceId
#                 class = 'Camera'
#                 manufacturer = $dev.Manufacturer
#                 problem_code = $problemCode
#                 is_present = $isPresent
#                 is_virtual = $isVirtual
#                 is_ok = ($dev.Status -eq 'OK')
#             }
#         }
#     } catch { }
    
#     try {
#         $imageDevices = @(Get-PnpDevice -Class Image -ErrorAction SilentlyContinue)
#         foreach ($dev in $imageDevices) {
#             if ($dev.FriendlyName -notmatch 'Camera|Webcam|Video') { continue }
#             $isVirtual = $false
#             foreach ($pattern in $virtualPatterns) {
#                 if ($dev.FriendlyName -like $pattern) { $isVirtual = $true; break }
#             }
#             if ($isVirtual -and -not $includeVirtual) { continue }
#             $exists = $cameras | Where-Object { $_.instance_id -eq $dev.InstanceId }
#             if (-not $exists) {
#                 $problemCode = if ($dev.PSObject.Properties['ProblemCode']) { $dev.ProblemCode } else { 0 }
#                 $isPresent = if ($dev.PSObject.Properties['Present']) { $dev.Present } else { $true }
#                 $cameras += @{
#                     friendly_name = $dev.FriendlyName
#                     status = $dev.Status
#                     instance_id = $dev.InstanceId
#                     class = 'Image'
#                     manufacturer = $dev.Manufacturer
#                     problem_code = $problemCode
#                     is_present = $isPresent
#                     is_virtual = $isVirtual
#                     is_ok = ($dev.Status -eq 'OK')
#                 }
#             }
#         }
#     } catch { }
    
#     try {
#         $usbVideoDevices = @(Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Camera|Webcam|Video' })
#         foreach ($dev in $usbVideoDevices) {
#             $exists = $cameras | Where-Object { $_.instance_id -eq $dev.InstanceId }
#             if (-not $exists) {
#                 $problemCode = if ($dev.PSObject.Properties['ProblemCode']) { $dev.ProblemCode } else { 0 }
#                 $isPresent = if ($dev.PSObject.Properties['Present']) { $dev.Present } else { $true }
#                 $cameras += @{
#                     friendly_name = $dev.FriendlyName
#                     status = $dev.Status
#                     instance_id = $dev.InstanceId
#                     class = 'USB'
#                     manufacturer = $dev.Manufacturer
#                     problem_code = $problemCode
#                     is_present = $isPresent
#                     is_virtual = $false
#                     is_ok = ($dev.Status -eq 'OK')
#                 }
#             }
#         }
#     } catch { }

#     $physicalCameras = @($cameras | Where-Object { -not $_.is_virtual })
#     $workingCameras = @($cameras | Where-Object { $_.is_ok })
#     $problematicCameras = @($cameras | Where-Object { -not $_.is_ok })
    
#     $status = 'healthy'
#     $issues = @()
#     if ($physicalCameras.Count -eq 0) {
#         $status = 'no_camera'
#         $issues += 'No physical camera detected'
#     } elseif ($problematicCameras.Count -gt 0) {
#         $status = 'degraded'
#         foreach ($cam in $problematicCameras) {
#             $issues += "Camera '$($cam.friendly_name)' has status: $($cam.status)"
#         }
#     }
    
#     Emit-Success @{
#         cameras = $cameras
#         total_count = $cameras.Count
#         physical_count = $physicalCameras.Count
#         working_count = $workingCameras.Count
#         problematic_count = $problematicCameras.Count
#         status = $status
#         issues = $issues
#         has_working_camera = ($workingCameras.Count -gt 0)
#     }

# } catch {
#     $exceptionMessage = $_.Exception.Message
#     Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
#         script_path = $MyInvocation.MyCommand.Path
#         line_number = $_.InvocationInfo.ScriptLineNumber
#     }
# }


# list_camera_devices.ps1
# V1.1.1 L1 Skill - List camera devices (Optimized: Removed heavy USB scan)
# expected_cost: low
# danger_level: P0_READ
# group: C12_hardware

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$global:__hasEmitted = $false
$__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
$script:SkillArgs = $null
$script:OutputFilePath = $OutputFile

# --- Helper Functions ---
function Emit-Success($data) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true
    
    $meta = @{
        exec_time_ms = $__sw.ElapsedMilliseconds
        skill_version = "1.1.1"
    }
    if ($script:SkillArgs -and $script:SkillArgs.metadata) {
        $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object { $meta[$_.Name] = $_.Value }
    }

    $payload = @{ ok = $true; data = $data; error = $null; metadata = $meta }
    $json = $payload | ConvertTo-Json -Depth 6 -Compress
    if ($script:OutputFilePath) { [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false)) }
    else { Write-Output $json }
}

function Emit-Error($code, $msg) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true
    
    $meta = @{ exec_time_ms = $__sw.ElapsedMilliseconds; skill_version = "1.1.1" }
    $payload = @{ ok = $false; data = $null; error = @{ code = $code; message = $msg }; metadata = $meta }
    $json = $payload | ConvertTo-Json -Depth 6 -Compress
    if ($script:OutputFilePath) { [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false)) }
    else { Write-Output $json }
}

try {
    # 1. Safe Parameter Parsing
    if ($InputFile -and (Test-Path $InputFile)) {
        $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
    }
    if ($InputObject) { $script:SkillArgs = $InputObject | ConvertFrom-Json }
    
    $includeVirtual = $false
    if ($script:SkillArgs -and $script:SkillArgs.PSObject.Properties['parameter'] -and $script:SkillArgs.parameter) {
        if ($script:SkillArgs.parameter.PSObject.Properties['include_virtual']) {
            $includeVirtual = [bool]$script:SkillArgs.parameter.include_virtual
        }
    }

    # 2. Optimized Constants
    # Use Regex for fast virtual device detection (Case Insensitive)
    $virtualRegex = '(?i)(Virtual|OBS|ManyCam|XSplit|Snap Camera|CamTwist|SplitCam|Webcamoid|NDI|DroidCam|Iriun)'
    
    # 3. Fetch Devices
    # Only query 'Camera' and 'Image' classes. 
    # [Optimization] Removed 'USB' class query which scans all USB hubs/controllers and causes 5s+ delay.
    # Real cameras always appear in Camera (Modern) or Image (Legacy) classes.
    $candidates = @()
    try { $candidates += @(Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue) } catch {}
    try { $candidates += @(Get-PnpDevice -Class Image -ErrorAction SilentlyContinue) } catch {}

    $cameras = @()
    $processedIds = @{} # Hashtable for O(1) deduplication

    foreach ($dev in $candidates) {
        # Deduplication check
        if ($processedIds.ContainsKey($dev.InstanceId)) { continue }
        
        # Filter for Image class: strict name check to avoid scanners/printers
        if ($dev.Class -eq 'Image') {
            if ($dev.FriendlyName -notmatch '(?i)Camera|Webcam|Video') { continue }
        }

        # Virtual Device Check
        $isVirtual = ($dev.FriendlyName -match $virtualRegex) -or 
                     ($dev.Manufacturer -match $virtualRegex)
        
        if ($isVirtual -and -not $includeVirtual) { continue }

        # Safe Property Access
        $problemCode = 0
        if ($dev.PSObject.Properties['ProblemCode']) { $problemCode = $dev.ProblemCode }
        
        $isPresent = $true
        if ($dev.PSObject.Properties['Present']) { $isPresent = $dev.Present }

        # Build Object
        $camObj = @{
            friendly_name = $dev.FriendlyName
            status = $dev.Status
            instance_id = $dev.InstanceId
            class = $dev.Class
            manufacturer = $dev.Manufacturer
            problem_code = $problemCode
            is_present = $isPresent
            is_virtual = $isVirtual
            is_ok = ($dev.Status -eq 'OK')
        }

        $cameras += $camObj
        $processedIds[$dev.InstanceId] = $true
    }

    # 4. Status Summary
    $physicalCameras = @($cameras | Where-Object { -not $_.is_virtual })
    $workingCameras = @($cameras | Where-Object { $_.is_ok })
    $problematicCameras = @($cameras | Where-Object { -not $_.is_ok })
    
    $status = 'healthy'
    $issues = @()
    
    if ($physicalCameras.Count -eq 0) {
        $status = 'no_camera'
        $issues += 'No physical camera detected'
    } elseif ($problematicCameras.Count -gt 0) {
        $status = 'degraded'
        foreach ($cam in $problematicCameras) {
            $issues += "Camera '$($cam.friendly_name)' has status: $($cam.status)"
        }
    }
    
    Emit-Success @{
        cameras = $cameras
        total_count = $cameras.Count
        physical_count = $physicalCameras.Count
        working_count = $workingCameras.Count
        problematic_count = $problematicCameras.Count
        status = $status
        issues = $issues
        has_working_camera = ($workingCameras.Count -gt 0)
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage
}