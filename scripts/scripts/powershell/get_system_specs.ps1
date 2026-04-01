# # get_system_specs.ps1
# # V1.1.0 L1 Skill - Get system static specifications

# param(
#     [Parameter(Position=0)]
#     [string]$InputObject = "",
#     [string]$OutputFile = "",
#     [string]$InputFile = ""
# )

# # 1. Strict mode and environment settings
# Set-StrictMode -Version Latest
# $ErrorActionPreference = 'Stop'
# [Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# # Handle InputFile (for subprocess mode)
# if ($InputFile -and (Test-Path $InputFile)) {
#     $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
# }

# # 2. Unified JSON output functions
# $global:__hasEmitted = $false
# $__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
# $script:SkillArgs = $null
# $script:OutputFilePath = $OutputFile

# function Emit-Success($data, $extraMeta = @{}) {
#     if ($global:__hasEmitted) { return }
#     $global:__hasEmitted = $true

#     # Merge with host metadata
#     $finalMetadata = @{}
#     if ($script:SkillArgs -and $script:SkillArgs.metadata) {
#         $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object {
#             $finalMetadata[$_.Name] = $_.Value
#         }
#     }
#     $extraMeta.GetEnumerator() | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
#     $finalMetadata['exec_time_ms'] = $__sw.ElapsedMilliseconds
#     $finalMetadata['skill_version'] = "1.1.0"

#     $body = @{
#         ok = $true
#         data = $data
#         error = $null
#         metadata = $finalMetadata
#     }
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

#     # Merge with host metadata
#     $finalMetadata = @{}
#     if ($script:SkillArgs -and $script:SkillArgs.metadata) {
#         $script:SkillArgs.metadata.PSObject.Properties | ForEach-Object {
#             $finalMetadata[$_.Name] = $_.Value
#         }
#     }
#     $extraMeta.GetEnumerator() | ForEach-Object { $finalMetadata[$_.Name] = $_.Value }
#     $finalMetadata['exec_time_ms'] = $__sw.ElapsedMilliseconds
#     $finalMetadata['skill_version'] = "1.1.0"

#     $body = @{
#         ok = $false
#         data = $null
#         error = @{
#             code = $code
#             message = $message
#             retriable = [bool]$retriable
#         }
#         metadata = $finalMetadata
#     }
#     $json = $body | ConvertTo-Json -Depth 6 -Compress
#     if ($script:OutputFilePath) {
#         [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false))
#     } else {
#         Write-Output $json
#     }
# }

# # 3. Lightweight budget guard
# function Test-Budget($sw, $budget_ms) {
#     if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
#     if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
#     return $true
# }

# try {
#     # 4. Parameter injection
#     $script:SkillArgs = $InputObject | ConvertFrom-Json
#     $Parameter = $script:SkillArgs.parameter
#     $BudgetMs = 0
#     if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
#         $BudgetMs = $script:SkillArgs.metadata.timeout_ms
#     }

#     # 5. Check budget
#     if (-not (Test-Budget $__sw $BudgetMs)) {
#         Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
#         return
#     }

#     # 6. Core logic
    
#     # OS and Memory
#     $osInfoArr = @(Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
#     $osInfo = if ($osInfoArr.Count -gt 0) { $osInfoArr[0] } else { $null }
#     $csInfoArr = @(Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue)
#     $csInfo = if ($csInfoArr.Count -gt 0) { $csInfoArr[0] } else { $null }
    
#     $osName = $osInfo.Caption
#     $osVersion = $osInfo.Version
#     $osBuild = $osInfo.BuildNumber
#     $totalMemoryGb = [math]::Round($csInfo.TotalPhysicalMemory / 1GB, 2)

#     # CPU
#     $processors = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
#     $cpuName = ($processors | Select-Object -ExpandProperty Name -Unique) -join ", "
#     $cpuCores = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
#     $cpuLogicalProcessors = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

#     # Disks
#     $disks = @()
#     $fallback = $false
#     try {
#         # Primary path: Get-Disk
#         $busTypeDeny = if ($Parameter -and $Parameter.PSObject.Properties['bus_type_deny']) { $Parameter.bus_type_deny } else { @() }
#         $physicalDisks = Get-Disk | Where-Object { $busTypeDeny -notcontains $_.BusType }
        
#         foreach ($disk in $physicalDisks) {
#             $partitions = Get-Partition -DiskNumber $disk.DiskNumber
#             foreach ($partition in $partitions) {
#                 try {
#                     $volume = Get-Volume -Partition $partition -ErrorAction SilentlyContinue
#                     if ($volume -and $volume.DriveLetter) {
#                         $disks += @{
#                             drive_letter = "$($volume.DriveLetter):"
#                             path = $volume.Path
#                             file_system = $volume.FileSystem
#                             size_gb = [math]::Round($volume.Size / 1GB, 2)
#                             size_remaining_gb = [math]::Round($volume.SizeRemaining / 1GB, 2)
#                             is_system_disk = ($volume.Path -eq $env:SystemDrive + '\')
#                         }
#                     }
#                 } catch {
#                     # Ignore volumes that can't be read
#                 }
#             }
#         }
#         if ($disks.Count -eq 0) { throw "No disks found via Get-Disk" }
#     } catch {
#         # Fallback path: Win32_LogicalDisk
#         $fallback = $true
#         $logicalDisks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
#         foreach ($disk in $logicalDisks) {
#             $disks += @{
#                 drive_letter = $disk.DeviceID
#                 path = $disk.DeviceID + '\'
#                 file_system = $disk.FileSystem
#                 size_gb = [math]::Round($disk.Size / 1GB, 2)
#                 size_remaining_gb = [math]::Round($disk.FreeSpace / 1GB, 2)
#                 is_system_disk = ($disk.DeviceID -eq $env:SystemDrive)
#             }
#         }
#     }

#     $result = @{
#         hostname = $csInfo.Name
#         os_name = $osName
#         os_version = $osVersion
#         os_build = $osBuild
#         os_architecture = $osInfo.OSArchitecture
#         total_memory_gb = $totalMemoryGb
#         cpu_name = $cpuName
#         cpu_cores = $cpuCores
#         cpu_logical_processors = $cpuLogicalProcessors
#         disks = $disks
#     }

#     # 7. Success output
#     Emit-Success $result @{ fallback_mode = $fallback }

# } catch {
#     # 8. Unified exception handling
#     $exceptionMessage = $_.Exception.Message
#     Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
#         script_path = $MyInvocation.MyCommand.Path
#         line_number = $_.InvocationInfo.ScriptLineNumber
#     }
# }


# get_system_specs.ps1
# V1.1.1 L1 Skill - Get system static specifications (Optimized: Parallel & Flat WMI)
# expected_cost: low
# danger_level: P0_READ
# group: C01_system_specs

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Handle InputFile
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$script:SkillArgs = $null
$global:__hasEmitted = $false
$__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
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

# --- Core Logic ScriptBlock for Parallel Execution ---
$WorkerScript = {
    $res = @{}
    
    # 1. OS & Computer System (Fastest via CIM)
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object Caption, Version, BuildNumber, OSArchitecture
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object Name, TotalPhysicalMemory
        
        $res.hostname = $cs.Name
        $res.os_name = $os.Caption
        $res.os_version = $os.Version
        $res.os_build = $os.BuildNumber
        $res.os_architecture = $os.OSArchitecture
        $res.total_memory_gb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    } catch {
        $res.os_error = $_.Exception.Message
    }

    # 2. CPU Info
    try {
        $cpus = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
        # Handle multi-socket systems
        $names = @($cpus | Select-Object -ExpandProperty Name -Unique) -join ", "
        $cores = ($cpus | Measure-Object -Property NumberOfCores -Sum).Sum
        $threads = ($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        
        $res.cpu_name = $names
        $res.cpu_cores = $cores
        $res.cpu_logical_processors = $threads
    } catch {
        $res.cpu_error = $_.Exception.Message
    }

    # 3. Disk Info (Optimized: Win32_Volume instead of nested Get-Disk loop)
    # Win32_Volume is much faster as it returns all logical volumes in one query
    try {
        $sysDrive = $env:SystemDrive
        $vols = Get-CimInstance Win32_Volume -Filter "DriveType=3 AND DriveLetter != NULL" -ErrorAction SilentlyContinue
        
        $diskList = @()
        foreach ($v in $vols) {
            $diskList += @{
                drive_letter = $v.DriveLetter
                path = $v.Caption # Usually "C:\"
                file_system = $v.FileSystem
                size_gb = [math]::Round($v.Capacity / 1GB, 2)
                size_remaining_gb = [math]::Round($v.FreeSpace / 1GB, 2)
                is_system_disk = ($v.DriveLetter -eq $sysDrive)
            }
        }
        $res.disks = $diskList
    } catch {
        $res.disk_error = $_.Exception.Message
    }

    return $res
}

try {
    # 1. Parameter Parsing
    if ($InputObject) { $script:SkillArgs = $InputObject | ConvertFrom-Json }
    
    # 2. Run Parallel Job
    # Even though we are running everything in one block, wrapping it in a Runspace
    # isolates it from the main thread overhead and any profile scripts.
    # For splitting WMI queries further, we could use multiple runspaces, 
    # but grouping them usually yields good enough performance (1-2s).
    
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($WorkerScript) | Out-Null
    
    $handle = $ps.BeginInvoke()
    
    # Wait with timeout (e.g., 10 seconds total budget)
    if ($handle.AsyncWaitHandle.WaitOne(10000)) {
        $result = $ps.EndInvoke($handle)
        # Extract the hashtable from the PSObject returned
        $finalData = $result[0]
        Emit-Success $finalData
    } else {
        Emit-Error "TIMEOUT" "System specs collection timed out (10s)."
    }
    
    $ps.Dispose()
    $rs.Close()

} catch {
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $_.Exception.Message
}