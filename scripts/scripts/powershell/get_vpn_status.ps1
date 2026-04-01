# # get_vpn_status.ps1
# # V1.1.0 L1 Skill - Get VPN status
# # expected_cost: low
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
#     $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
#         $script:SkillArgs.metadata.timeout_ms
#     } else { 0 }

#     # 5. Check budget
#     if (-not (Test-Budget $__sw $BudgetMs)) {
#         Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
#         return
#     }

#     # 6. Core logic
#     $vpnConnections = @()
#     $fallback = $false

#     try {
#         # Primary path: Get-VpnConnection
#         $vpnConns = Get-VpnConnection -ErrorAction SilentlyContinue
#         if ($vpnConns) {
#             foreach ($conn in $vpnConns) {
#                 $name = if ($conn.PSObject.Properties['Name']) { $conn.Name } else { "Unknown" }
#                 $serverAddr = if ($conn.PSObject.Properties['ServerAddress']) { $conn.ServerAddress } else { $null }
#                 $connStatus = if ($conn.PSObject.Properties['ConnectionStatus']) { $conn.ConnectionStatus } else { "Unknown" }
                
#                 $vpnConnections += @{
#                     name = $name
#                     server_address = $serverAddr
#                     connection_status = $connStatus
#                     source = "Built-in"
#                 }
#             }
#         }
#     } catch {
#         # Ignore if Get-VpnConnection is not available
#     }

#     # Fallback/supplement path: Check virtual adapters
#     try {
#         $fallback = $true
#         $vpnKeywords = @(
#             '*VPN*', '*Tunnel*', '*TUN*', '*TAP*',
#             '*Fortinet*', '*Palo Alto*', '*Cisco*', '*Juniper*',
#             '*Pulse*', '*SonicWall*', '*Check Point*', '*WireGuard*',
#             '*OpenVPN*', '*Clash*', '*v2ray*', '*Shadowsocks*',
#             '*Trojan*', '*Hysteria*'
#         )
#         $virtualAdapters = Get-NetAdapter | Where-Object {
#             $desc = $_.InterfaceDescription
#             foreach ($keyword in $vpnKeywords) {
#                 if ($desc -like $keyword) { return $true }
#             }
#             return $false
#         }

#         foreach ($adapter in $virtualAdapters) {
#             $adapterName = if ($adapter.PSObject.Properties['Name']) { $adapter.Name } else { "Unknown" }
#             $adapterStatus = if ($adapter.PSObject.Properties['Status']) { $adapter.Status } else { "Unknown" }
            
#             # Avoid duplicates
#             if (-not ($vpnConnections | Where-Object { $_.name -eq $adapterName })) {
#                 $vpnConnections += @{
#                     name = $adapterName
#                     server_address = $null
#                     connection_status = $adapterStatus
#                     source = "VirtualAdapter"
#                 }
#             }
#         }
#     } catch {
#         # Ignore if Get-NetAdapter fails
#     }
    
#     # 7. Success output
#     Emit-Success @{ vpn_connections = $vpnConnections } @{ fallback_mode = $fallback }

# } catch {
#     # 8. Unified exception handling
#     $exceptionMessage = $_.Exception.Message
#     Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
#         script_path = $MyInvocation.MyCommand.Path
#         line_number = $_.InvocationInfo.ScriptLineNumber
#     }
# }


# get_vpn_status.ps1
# V1.1.2 L1 Skill - Get VPN status (Fix: STA Thread Support)
# expected_cost: low
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

# --- Parallel Worker Scripts ---

# Task 1: Built-in Windows VPN (Get-VpnConnection)
$Script_BuiltIn = {
    $results = @()
    try {
        $vpnConns = Get-VpnConnection -ErrorAction SilentlyContinue
        if ($vpnConns) {
            foreach ($conn in $vpnConns) {
                $name = if ($conn.PSObject.Properties['Name']) { $conn.Name } else { "Unknown" }
                $server = if ($conn.PSObject.Properties['ServerAddress']) { $conn.ServerAddress } else { $null }
                $status = if ($conn.PSObject.Properties['ConnectionStatus']) { $conn.ConnectionStatus } else { "Unknown" }
                
                $results += @{
                    name = $name
                    server_address = $server
                    connection_status = $status
                    source = "Built-in"
                }
            }
        }
    } catch {}
    return $results
}

# Task 2: 3rd Party VPN Adapters (CIM/WMI)
$Script_Adapters = {
    $results = @()
    try {
        $vpnRegex = '(?i)(VPN|Tunnel|TUN|TAP|Fortinet|Palo Alto|Cisco|Juniper|Pulse|SonicWall|Check Point|WireGuard|OpenVPN|Clash|v2ray|Shadowsocks|Trojan|Hysteria)'
        
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object { 
            ($_.Name -match $vpnRegex) -or ($_.Description -match $vpnRegex)
        }

        foreach ($adapter in $adapters) {
            $statusStr = "Unknown"
            switch ($adapter.NetConnectionStatus) {
                2 { $statusStr = "Connected" }
                7 { $statusStr = "Disconnected" }
                0 { $statusStr = "Disconnected" }
                default { 
                    if ($adapter.NetConnectionStatus) { 
                        $statusStr = "State:$($adapter.NetConnectionStatus)" 
                    } else {
                        $statusStr = "Disabled/NotPresent" 
                    }
                }
            }

            $results += @{
                name = if ($adapter.Name) { $adapter.Name } else { "Unknown" }
                server_address = $null
                connection_status = $statusStr
                source = "VirtualAdapter"
            }
        }
    } catch {}
    return $results
}

try {
    if ($InputObject) { $script:SkillArgs = $InputObject | ConvertFrom-Json }

    # Setup Parallel Execution
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, 2)
    $runspacePool.Open()
    
    $ps1 = [powershell]::Create()
    $ps1.RunspacePool = $runspacePool
    $ps1.AddScript($Script_BuiltIn) | Out-Null
    
    $ps2 = [powershell]::Create()
    $ps2.RunspacePool = $runspacePool
    $ps2.AddScript($Script_Adapters) | Out-Null

    # Start Async
    $handle1 = $ps1.BeginInvoke()
    $handle2 = $ps2.BeginInvoke()

    # [FIX] Replace WaitAll with sequential WaitOne to support STA threads
    # Logic: Wait for Task1. If it finishes early, we immediately wait for Task2.
    # Task2 has been running in background all this time, so we are not blocking it.
    
    $maxWait = 5000
    $startWait = $__sw.ElapsedMilliseconds
    
    # Wait for Task 1
    $w1 = $handle1.AsyncWaitHandle.WaitOne($maxWait, $false)
    
    # Calculate remaining time for Task 2
    $spent = $__sw.ElapsedMilliseconds - $startWait
    $remain = [Math]::Max(0, ($maxWait - $spent))
    
    # Wait for Task 2
    $w2 = $handle2.AsyncWaitHandle.WaitOne($remain, $false)

    $finalList = @()
    $seenNames = @{} 

    # Process Built-in Results
    if ($handle1.IsCompleted) {
        $res1 = $ps1.EndInvoke($handle1)
        foreach ($r in $res1) {
            $finalList += $r
            $seenNames[$r.name] = $true
        }
    }
    
    # Process Adapter Results
    if ($handle2.IsCompleted) {
        $res2 = $ps2.EndInvoke($handle2)
        foreach ($r in $res2) {
            if (-not $seenNames.ContainsKey($r.name)) {
                $finalList += $r
            }
        }
    }

    # Cleanup
    $ps1.Dispose()
    $ps2.Dispose()
    $runspacePool.Close()
    $runspacePool.Dispose()

    Emit-Success @{ vpn_connections = $finalList }

} catch {
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $_.Exception.Message
}