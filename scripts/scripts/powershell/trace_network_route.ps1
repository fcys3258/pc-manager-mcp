# # trace_network_route.ps1
# # V1.1.0 L1 Skill - Trace network route
# # expected_cost: high
# # danger_level: P0_READ
# # group: C08_network_probe

# param(
#     [Parameter(Position=0)]
#     [string]$InputObject = "",
#     [string]$OutputFile = "",
#     [string]$InputFile = ""
# )

# # Handle InputFile (subprocess mode)
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
#     $json = $body | ConvertTo-Json -Depth 8 -Compress
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

# # 3. Budget guard
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
#     $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
#         $script:SkillArgs.metadata.timeout_ms
#     } else { 0 }

#     # 5. Check budget
#     if (-not (Test-Budget $__sw $BudgetMs)) {
#         Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
#         return
#     }

#     # 6. Core logic
#     $target = $null
#     if ($Parameter -and $Parameter.PSObject.Properties['target']) {
#         $target = $Parameter.target
#     }
#     if (-not $target) {
#         Emit-Error 'INVALID_ARGUMENT' 'Parameter "target" is required.' $false
#         return
#     }
    
#     $maxHops = 15
#     if ($Parameter -and $Parameter.PSObject.Properties['max_hops']) {
#         $maxHops = [int]$Parameter.max_hops
#         if ($maxHops -lt 1) { $maxHops = 15 }
#         if ($maxHops -gt 30) { $maxHops = 30 }
#     }
    
#     $timeout = 500
#     if ($Parameter -and $Parameter.PSObject.Properties['timeout_ms']) {
#         $timeout = [int]$Parameter.timeout_ms
#         if ($timeout -lt 100) { $timeout = 100 }
#         if ($timeout -gt 5000) { $timeout = 5000 }
#     }
    
#     $hops = @()
    
#     # Handle GBK encoding for Chinese Windows
#     $prevEncoding = [Console]::OutputEncoding
#     try {
#         [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
#     } catch { }
    
#     $rawOutput = tracert.exe -d -h $maxHops -w $timeout $target 2>&1
#     [Console]::OutputEncoding = $prevEncoding
    
#     # Parse tracert output
#     $hopNumber = 0
#     foreach ($line in $rawOutput) {
#         $lineStr = $line.ToString().Trim()
#         # Match lines starting with hop number (e.g., "  1    <1 ms    <1 ms    <1 ms  192.168.1.1")
#         if ($lineStr -match '^\s*(\d+)\s+') {
#             $hopNumber = [int]$matches[1]
            
#             # Extract RTT values and IP address
#             $parts = $lineStr -split '\s+' | Where-Object { $_ }
            
#             # Parse RTT (skip hop number, look for ms values)
#             $rttValues = @()
#             $ipAddress = $null
            
#             for ($i = 1; $i -lt $parts.Count; $i++) {
#                 $part = $parts[$i]
#                 if ($part -match '^\d+$') {
#                     $rttValues += [int]$part
#                 } elseif ($part -match '^\d+\.\d+\.\d+\.\d+$') {
#                     $ipAddress = $part
#                 } elseif ($part -eq '*') {
#                     $rttValues += -1
#                 }
#             }
            
#             # Calculate average RTT
#             $avgRtt = -1
#             $validRtts = $rttValues | Where-Object { $_ -ge 0 }
#             if ($validRtts -and @($validRtts).Count -gt 0) {
#                 $avgRtt = [int](($validRtts | Measure-Object -Average).Average)
#             }
            
#             $hops += @{
#                 hop = $hopNumber
#                 rtt_ms = $avgRtt
#                 address = $ipAddress
#                 status = if ($avgRtt -ge 0) { 'Success' } else { 'TimedOut' }
#             }
#         }
#     }
    
#     # 7. Success output
#     Emit-Success @{ target = $target; hops = $hops; hop_count = $hops.Count }

# } catch {
#     $exceptionMessage = $_.Exception.Message
#     Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
#         script_path = $MyInvocation.MyCommand.Path
#         line_number = $_.InvocationInfo.ScriptLineNumber
#     }
# }


# trace_network_route.ps1
# V1.1.2 L1 Skill - Trace network route (Fix: IP Drift & Sorting Logic)
# expected_cost: medium
# danger_level: P0_READ
# group: C08_network_probe

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

# --- Worker: Send Single Ping with Specific TTL ---
$WorkerScript = {
    param($Target, $Ttl, $Timeout)
    
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $options = New-Object System.Net.NetworkInformation.PingOptions
        $options.Ttl = $Ttl
        $options.DontFragment = $true
        
        $buffer = [System.Text.Encoding]::ASCII.GetBytes("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        
        $reply = $ping.Send($Target, $Timeout, $buffer, $options)
        
        $statusStr = $reply.Status.ToString()
        $addr = if ($reply.Address) { $reply.Address.ToString() } else { $null }
        
        $finalStatus = "TimedOut"
        if ($reply.Status -eq 'Success') { $finalStatus = "Success" }
        elseif ($reply.Status -eq 'TtlExpired') { $finalStatus = "Transit" }
        
        return @{
            hop = $Ttl
            rtt_ms = if ($reply.Status -eq 'TimedOut') { -1 } else { $reply.RoundtripTime }
            address = $addr
            status_code = $statusStr
            final_status = $finalStatus
        }
    } catch {
        return @{
            hop = $Ttl
            rtt_ms = -1
            address = $null
            status_code = "Error"
            final_status = "Error"
            error_msg = $_.Exception.Message
        }
    }
}

try {
    # 1. Parameter Parsing
    if ($InputObject) { $script:SkillArgs = $InputObject | ConvertFrom-Json }
    
    $target = $null
    $maxHops = 15
    $timeoutMs = 1000

    if ($script:SkillArgs -and $script:SkillArgs.PSObject.Properties['parameter'] -and $script:SkillArgs.parameter) {
        $p = $script:SkillArgs.parameter
        if ($p.PSObject.Properties['target']) { $target = $p.target }
        if ($p.PSObject.Properties['max_hops']) { $maxHops = [int]$p.max_hops }
        if ($p.PSObject.Properties['timeout_ms']) { $timeoutMs = [int]$p.timeout_ms }
    }

    if (-not $target) {
        Emit-Error 'INVALID_ARGUMENT' 'Parameter "target" is required.'
        return
    }
    
    # [FIX] Smart IP Resolution
    # Don't resolve if it's already an IP, to prevent 8.8.8.8 -> 8.8.4.4 drift
    $targetIp = $target
    $isIp = [System.Net.IPAddress]::TryParse($target, [ref]$null)
    
    if (-not $isIp) {
        try {
            $ipHost = [System.Net.Dns]::GetHostEntry($target)
            $targetIp = $ipHost.AddressList[0].ToString()
        } catch {
            # DNS failed, proceed with original string (might fail later)
        }
    }

    # 2. Parallel Execution
    $poolSize = if ($maxHops -gt 20) { 20 } else { $maxHops }
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $poolSize)
    $runspacePool.Open()
    $jobs = @()

    for ($i = 1; $i -le $maxHops; $i++) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool
        $ps.AddScript($WorkerScript).AddArgument($targetIp).AddArgument($i).AddArgument($timeoutMs) | Out-Null
        
        $jobs += @{ Pipe = $ps; Handle = $ps.BeginInvoke(); TTL = $i }
    }

    # 3. Harvest Results
    $rawHops = @()
    foreach ($job in $jobs) {
        if ($job.Handle.AsyncWaitHandle.WaitOne($timeoutMs + 2000)) {
            $res = $job.Pipe.EndInvoke($job.Handle)
            $rawHops += $res
        } else {
            $rawHops += @{ hop = $job.TTL; status_code = "ThreadTimeout"; final_status = "TimedOut"; rtt_ms = -1 }
        }
        $job.Pipe.Dispose()
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()

    # 4. Post-Processing [FIXED LOGIC]
    # Explicitly cast 'hop' to int for correct sorting
    $sortedHops = $rawHops | Sort-Object { [int]$_.hop }
    
    $finalHops = @()
    
    # Find the FIRST hop that succeeded (Target Reached)
    $successHopNum = 999
    foreach ($h in $sortedHops) {
        if ($h.final_status -eq 'Success') {
            $successHopNum = $h.hop
            break # Found the first success (shortest path)
        }
    }

    # Only include hops up to the success hop
    foreach ($h in $sortedHops) {
        if ($h.hop -le $successHopNum) {
            $finalHops += @{
                hop = $h.hop
                rtt_ms = $h.rtt_ms
                address = $h.address
                status = $h.final_status
            }
        }
    }

    Emit-Success @{ 
        target = $target
        resolved_ip = $targetIp
        hops = $finalHops
        hop_count = $finalHops.Count 
    }

} catch {
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $_.Exception.Message
}