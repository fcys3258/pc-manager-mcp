# # test_connectivity.ps1
# # V1.1.0 L1 Skill - Test network connectivity
# # expected_cost: medium
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
#     $mode = if ($Parameter -and $Parameter.PSObject.Properties['mode']) { $Parameter.mode } else { 'internet' }
#     $target = if ($Parameter -and $Parameter.PSObject.Properties['target']) { $Parameter.target } else { $null }
#     $port = if ($Parameter -and $Parameter.PSObject.Properties['port']) { $Parameter.port } else { $null }
#     $pingTimeout = if ($Parameter -and $Parameter.PSObject.Properties['ping_timeout_ms']) { $Parameter.ping_timeout_ms } else { 1000 }
#     $dnsServer = if ($Parameter -and $Parameter.PSObject.Properties['dns_server']) { $Parameter.dns_server } else { $null }

#     $targets = @()
#     switch ($mode) {
#         "internet" { $targets = @("8.8.8.8", "www.bing.com") }
#         "intranet" { 
#             $gw = (Get-NetIPConfiguration | Select-Object -ExpandProperty IPv4DefaultGateway -ErrorAction SilentlyContinue)
#             if ($gw) { $targets = @($gw.NextHop) }
#         }
#         "custom" { 
#             if (-not $target) { Emit-Error 'INVALID_ARGUMENT' "Target must be provided for custom mode."; return }
#             $targets = @($target)
#         }
#         default { Emit-Error 'INVALID_ARGUMENT' "Unknown mode '$mode'."; return }
#     }

#     if ($targets.Count -eq 0) {
#         Emit-Error 'NO_TARGETS_FOUND' "No targets found for mode '$mode' (e.g., no default gateway)."
#         return
#     }

#     $results = @()
#     foreach ($t in $targets) {
#         $res = @{ target = $t }
        
#         # DNS resolution
#         try {
#             $dnsResult = $null
#             if ($dnsServer) {
#                 $dnsResult = Resolve-DnsName -Name $t -Server $dnsServer -ErrorAction SilentlyContinue
#                 $res.dns_server_used = $dnsServer
#             } else {
#                 $dnsResult = Resolve-DnsName -Name $t -ErrorAction SilentlyContinue
#                 $res.dns_server_used = "system_default"
#             }
            
#             if ($dnsResult) {
#                 $ipAddresses = @($dnsResult | Where-Object { $_.PSObject.Properties['IPAddress'] } | Select-Object -ExpandProperty IPAddress)
#                 $res.dns_resolved = ($ipAddresses.Count -gt 0)
#                 $res.dns_addresses = $ipAddresses
#             } else {
#                 $res.dns_resolved = $false
#                 $res.dns_addresses = @()
#             }
#         } catch { 
#             $res.dns_resolved = $false
#             $res.dns_addresses = @()
#             $res.dns_error = $_.Exception.Message
#         }

#         # Ping test using .NET Ping
#         try {
#             $ping = New-Object System.Net.NetworkInformation.Ping
#             $reply = $ping.Send($t, $pingTimeout)
#             if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
#                 $res.ping_successful = $true
#                 $res.ping_rtt_ms = $reply.RoundtripTime
#             } else {
#                 $res.ping_successful = $false
#                 $res.ping_rtt_ms = -1
#             }
#         } catch {
#             $res.ping_successful = $false
#             $res.ping_rtt_ms = -1
#         }

#         # Port test (optional)
#         if ($port) {
#             try {
#                 $portResult = Test-NetConnection -ComputerName $t -Port $port -InformationLevel Quiet -ErrorAction SilentlyContinue
#                 $res.port_test_successful = $portResult
#             } catch { $res.port_test_successful = $false }
#         }
#         $results += $res
#     }
    
#     Emit-Success @{ connectivity_results = $results }

# } catch {
#     $exceptionMessage = $_.Exception.Message
#     Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
#         script_path = $MyInvocation.MyCommand.Path
#         line_number = $_.InvocationInfo.ScriptLineNumber
#     }
# }

# test_connectivity.ps1
# V1.1.2 L1 Skill - Test network connectivity (Fix: StrictMode Property Access)
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

# --- Core Logic: Worker ScriptBlock for Parallel Execution ---
$WorkerScript = {
    param($Target, $Port, $PingTimeout, $DnsServer)
    
    $res = @{ target = $Target }
    
    # 1. DNS Resolution (Skip if target is already an IP)
    $isIp = [System.Net.IPAddress]::TryParse($Target, [ref]$null)
    
    if (-not $isIp) {
        try {
            $dnsParams = @{ Name = $Target; ErrorAction = 'Stop' }
            if ($DnsServer) { $dnsParams['Server'] = $DnsServer }
            
            $dnsResult = Resolve-DnsName @dnsParams
            
            if ($dnsResult) {
                $ips = @($dnsResult | Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress)
                $res.dns_resolved = ($ips.Count -gt 0)
                $res.dns_addresses = $ips
                $res.dns_server_used = if ($DnsServer) { $DnsServer } else { "system_default" }
            }
        } catch {
            $res.dns_resolved = $false
            $res.dns_error = $_.Exception.Message
        }
    } else {
        $res.dns_resolved = $null 
        $res.dns_note = "Target is IP, skipped DNS"
    }

    # 2. Ping Test (.NET Ping)
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($Target, $PingTimeout)
        if ($reply.Status -eq 'Success') {
            $res.ping_successful = $true
            $res.ping_rtt_ms = $reply.RoundtripTime
        } else {
            $res.ping_successful = $false
            $res.ping_error = $reply.Status.ToString()
        }
    } catch {
        $res.ping_successful = $false
        $res.ping_error = $_.Exception.Message
    }

    # 3. TCP Port Test (.NET TcpClient - Fast Timeout)
    if ($Port) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connectResult = $tcp.BeginConnect($Target, $Port, $null, $null)
            $success = $connectResult.AsyncWaitHandle.WaitOne(1500, $false) # 1.5s Timeout
            
            if ($success) {
                try {
                    $tcp.EndConnect($connectResult)
                    $res.port_test_successful = $true
                } catch {
                    $res.port_test_successful = $false
                }
            } else {
                $res.port_test_successful = $false 
            }
            $tcp.Close()
            $tcp.Dispose()
        } catch {
            $res.port_test_successful = $false
        }
    }

    return $res
}

try {
    # [FIX] Safe Parameter Parsing for StrictMode
    if ($InputObject) { $script:SkillArgs = $InputObject | ConvertFrom-Json }
    
    # Default values
    $mode = 'internet'
    $port = $null
    $pingTimeout = 800
    $dnsServer = $null
    $targetParam = $null

    # Safely extract values if 'parameter' object exists
    if ($script:SkillArgs -and $script:SkillArgs.PSObject.Properties['parameter'] -and $script:SkillArgs.parameter) {
        $p = $script:SkillArgs.parameter
        # Use PSObject.Properties to check existence before access
        if ($p.PSObject.Properties['mode']) { $mode = $p.mode }
        if ($p.PSObject.Properties['port']) { $port = [int]$p.port }
        if ($p.PSObject.Properties['ping_timeout_ms']) { $pingTimeout = $p.ping_timeout_ms }
        if ($p.PSObject.Properties['dns_server']) { $dnsServer = $p.dns_server }
        if ($p.PSObject.Properties['target']) { $targetParam = $p.target }
    }

    # Determine Targets
    $targetList = @()
    switch ($mode) {
        "internet" { 
            $targetList = @("8.8.8.8", "www.bing.com") 
        }
        "intranet" {
            $gw = (Get-NetIPConfiguration | Select-Object -ExpandProperty IPv4DefaultGateway -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($gw) { $targetList = @($gw.NextHop) }
        }
        "custom" {
            if (-not $targetParam) { Emit-Error 'INVALID_ARGUMENT' "Target required for custom mode"; return }
            $targetList = @($targetParam)
        }
        default { Emit-Error 'INVALID_ARGUMENT' "Unknown mode '$mode'"; return }
    }

    if ($targetList.Count -eq 0) {
        Emit-Error 'NO_TARGETS_FOUND' "No targets found for mode '$mode'"
        return
    }

    # --- Parallel Execution Setup ---
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Math]::Max($targetList.Count, 1))
    $runspacePool.Open()
    $jobs = @()

    foreach ($t in $targetList) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool
        $ps.AddScript($WorkerScript).AddArgument($t).AddArgument($port).AddArgument($pingTimeout).AddArgument($dnsServer) | Out-Null
        
        $jobs += @{
            Pipe = $ps
            Handle = $ps.BeginInvoke()
            Target = $t
        }
    }

    # Wait for completion
    $results = @()
    foreach ($job in $jobs) {
        if ($job.Handle.AsyncWaitHandle.WaitOne(8000)) { 
            $res = $job.Pipe.EndInvoke($job.Handle)
            $results += $res
        } else {
            $results += @{ target = $job.Target; error = "Global execution timeout" }
        }
        $job.Pipe.Dispose()
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    Emit-Success @{ connectivity_results = $results }

} catch {
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $_.Exception.Message
}