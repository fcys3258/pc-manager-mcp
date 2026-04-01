# # get_running_processes.ps1
# # V1.1.0 L1 Skill - Get high resource usage processes (Optimized)

# param(
#     [Parameter(Position=0)]
#     [string]$InputObject = "",
#     [string]$OutputFile = "",
#     [string]$InputFile = ""
# )

# # Handle InputFile (for subprocess mode)
# if ($InputFile -and (Test-Path $InputFile)) {
#     $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
# }

# # 1. Strict mode and environment settings
# Set-StrictMode -Version Latest
# $ErrorActionPreference = 'Stop'
# [Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

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
#     if (-not $script:SkillArgs) {
#         Emit-Error 'INVALID_ARGUMENT' 'Invalid or empty SkillArgs JSON payload.' $false
#         return
#     }
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
#     $limit = if ($Parameter -and $Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 20 }
#     $sortBy = if ($Parameter -and $Parameter.PSObject.Properties['sort_by']) { $Parameter.sort_by } else { 'cpu' }


#     # Primary path: use performance counters
#     try {
#         # Warm up performance counters
#         $null = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue)
#         Start-Sleep -Milliseconds 500

#         # Get accurate CPU usage
#         $perfData = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue | Where-Object {
#             $_.Name -ne '_Total' -and $_.Name -ne 'Idle'
#         })

#         # Sort
#         $sorted = switch ($sortBy) {
#             'cpu' { $perfData | Sort-Object PercentProcessorTime -Descending }
#             'memory' { $perfData | Sort-Object WorkingSetPrivate -Descending }
#             'io' { $perfData | Sort-Object IODataBytesPersec -Descending }
#             default { $perfData | Sort-Object PercentProcessorTime -Descending }
#         }

#         # Get Top-N
#         $topProcesses = $sorted | Select-Object -First $limit

#         # Build result
#         $processes = @()
#         foreach ($proc in $topProcesses) {
#             $procId = $proc.IDProcess
#             $name = $proc.Name
#             $cpuPercent = $proc.PercentProcessorTime
#             $memoryMb = [math]::Round($proc.WorkingSetPrivate / 1MB, 2)
#             $ioMbS = [math]::Round($proc.IODataBytesPersec / 1MB, 2)

#             # Get process details
#             try {
#                 $process = Get-Process -Id $procId -ErrorAction SilentlyContinue
#                 $startTime = if ($process -and $process.StartTime) { $process.StartTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { 'Unknown' }
#                 $processKey = "${procId}:${startTime}"
#             } catch {
#                 $startTime = 'Unknown'
#                 $processKey = "${procId}:Unknown"
#             }

#             # Get username (only for Top-N to avoid performance issues)
#             $username = 'Unknown'
#             try {
#                 $owner = Invoke-CimMethod -InputObject (Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue) -MethodName GetOwner -ErrorAction SilentlyContinue
#                 if ($owner -and $owner.ReturnValue -eq 0) {
#                     $username = "$($owner.Domain)\$($owner.User)"
#                 }
#             } catch {
#                 # Ignore errors
#             }

#             $processes += @{
#                 pid = $procId
#                 name = $name
#                 cpu_percent = $cpuPercent
#                 memory_mb = $memoryMb
#                 io_mb_s = $ioMbS
#                 username = $username
#                 start_time = $startTime
#                 process_key = $processKey
#             }
#         }

#         Emit-Success @{
#             processes = $processes
#             total_count = $processes.Count
#             sort_by = $sortBy
#         }

#     } catch {
#         # Fallback path: use Get-Process
#         $allProcs = Get-Process -ErrorAction SilentlyContinue
#         $processes = $allProcs | Sort-Object { 
#             if ($_.PSObject.Properties['CPU'] -and $_.CPU) { 
#                 if ($_.CPU -is [TimeSpan]) { $_.CPU.TotalSeconds } else { $_.CPU }
#             } else { 
#                 0 
#             } 
#         } -Descending | Select-Object -First $limit
        
#         $result = @()
#         foreach ($proc in $processes) {
#             try {
#                 $startTimeStr = if ($proc.StartTime) { $proc.StartTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { 'Unknown' }
#                 $result += @{
#                     pid = $proc.Id
#                     name = $proc.ProcessName
#                     cpu_percent = 0
#                     memory_mb = [math]::Round($proc.WorkingSet64 / 1MB, 2)
#                     io_mb_s = 0
#                     username = 'Unknown'
#                     start_time = $startTimeStr
#                     process_key = "$($proc.Id):$startTimeStr"
#                 }
#             } catch {
#                 # Skip inaccessible processes
#             }
#         }

#         Emit-Success @{
#             processes = $result
#             total_count = $result.Count
#             sort_by = $sortBy
#             fallback_mode = $true
#         }
#     }

# } catch {
#     # 8. Unified exception handling
#     $exceptionMessage = $_.Exception.Message
#     Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
#         script_path = $MyInvocation.MyCommand.Path
#         line_number = $_.InvocationInfo.ScriptLineNumber
#     }
# }


# get_running_processes.ps1
# V1.1.2 L1 Skill - Get high resource usage processes (Fix: Reserved Variable Name)
# expected_cost: low
# danger_level: P0_READ
# group: C04_process

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
        skill_version = "1.1.2"
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
    
    $meta = @{ exec_time_ms = $__sw.ElapsedMilliseconds; skill_version = "1.1.2" }
    $payload = @{ ok = $false; data = $null; error = @{ code = $code; message = $msg }; metadata = $meta }
    $json = $payload | ConvertTo-Json -Depth 6 -Compress
    if ($script:OutputFilePath) { [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false)) }
    else { Write-Output $json }
}

try {
    # 1. Parameter Parsing
    if ($InputObject) { $script:SkillArgs = $InputObject | ConvertFrom-Json }
    
    # Defaults
    $limit = 20
    $sortBy = 'cpu'
    $includeUsername = $false 

    # Safe Extraction
    if ($script:SkillArgs -and $script:SkillArgs.PSObject.Properties['parameter'] -and $script:SkillArgs.parameter) {
        $p = $script:SkillArgs.parameter
        if ($p.PSObject.Properties['limit']) { $limit = [int]$p.limit }
        if ($p.PSObject.Properties['sort_by']) { $sortBy = $p.sort_by }
        if ($p.PSObject.Properties['include_username']) { $includeUsername = [bool]$p.include_username }
    }

    # 2. Strategy Selection
    $usePerfCounters = ($sortBy -in @('cpu', 'io'))

    if ($usePerfCounters) {
        # Win32_PerfFormattedData strategy
        $perfData = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name != '_Total' AND Name != 'Idle'" -ErrorAction SilentlyContinue
        
        # Sort Logic
        $sorted = switch ($sortBy) {
            'cpu' { $perfData | Sort-Object PercentProcessorTime -Descending }
            'io'  { $perfData | Sort-Object IODataBytesPersec -Descending }
            default { $perfData | Sort-Object PercentProcessorTime -Descending }
        }
        
        $topItems = $sorted | Select-Object -First $limit
        
        $processes = @()
        foreach ($item in $topItems) {
            # [FIX] Changed variable name from $pid to $procId
            # $pid is a reserved automatic variable in PowerShell (Current Process ID) and implies ReadOnly
            $procId = $item.IDProcess
            
            $p = @{
                pid = $procId
                name = $item.Name
                cpu_percent = $item.PercentProcessorTime
                memory_mb = [math]::Round($item.WorkingSetPrivate / 1MB, 2)
                io_mb_s = [math]::Round($item.IODataBytesPersec / 1MB, 2)
                start_time = "Unknown"
                username = $null
            }

            try {
                $procObj = Get-Process -Id $procId -ErrorAction Stop
                if ($procObj.StartTime) {
                    $p.start_time = $procObj.StartTime.ToString('yyyy-MM-ddTHH:mm:ss')
                }
            } catch { }
            
            $p.process_key = "$($p.pid):$($p.start_time)"

            if ($includeUsername) {
                try {
                    $owner = Invoke-CimMethod -InputObject (Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue) -MethodName GetOwner -ErrorAction SilentlyContinue
                    if ($owner -and $owner.ReturnValue -eq 0) {
                        $p.username = "$($owner.Domain)\$($owner.User)"
                    }
                } catch {}
            }

            $processes += $p
        }
        
        Emit-Success @{
            processes = $processes
            total_count = $processes.Count
            sort_by = $sortBy
            source = "PerformanceCounters"
        }

    } else {
        # Get-Process strategy
        $allProcs = Get-Process -ErrorAction SilentlyContinue
        
        $sorted = switch ($sortBy) {
            'memory' { $allProcs | Sort-Object WorkingSet64 -Descending }
            default  { $allProcs | Sort-Object WorkingSet64 -Descending }
        }
        
        $topItems = $sorted | Select-Object -First $limit
        
        $processes = @()
        foreach ($proc in $topItems) {
            $p = @{
                pid = $proc.Id
                name = $proc.ProcessName
                cpu_percent = 0 
                memory_mb = [math]::Round($proc.WorkingSet64 / 1MB, 2)
                io_mb_s = 0
                start_time = "Unknown"
                username = $null
            }
            
            try {
                if ($proc.StartTime) {
                    $p.start_time = $proc.StartTime.ToString('yyyy-MM-ddTHH:mm:ss')
                }
            } catch {}
            $p.process_key = "$($p.pid):$($p.start_time)"

            if ($includeUsername) {
                try {
                    $owner = Invoke-CimMethod -InputObject (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue) -MethodName GetOwner -ErrorAction SilentlyContinue
                    if ($owner -and $owner.ReturnValue -eq 0) {
                        $p.username = "$($owner.Domain)\$($owner.User)"
                    }
                } catch {}
            }
            
            $processes += $p
        }

        Emit-Success @{
            processes = $processes
            total_count = $processes.Count
            sort_by = $sortBy
            source = "Get-Process"
        }
    }

} catch {
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $_.Exception.Message
}