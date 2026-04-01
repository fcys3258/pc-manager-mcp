# # get_os_update_status.ps1
# # V1.1.0 L1 Skill - Get Windows Update status

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

# # 2. Unified JSON output functions
# $script:SkillArgs = $null
# $global:__hasEmitted = $false
# $__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
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

# try {
#     # 3. Parameter injection - support InputFile
#     if ($InputFile -and (Test-Path $InputFile)) {
#         $InputObject = Get-Content -Path $InputFile -Raw -Encoding UTF8
#     }
#     $script:SkillArgs = $InputObject | ConvertFrom-Json

#     # 4. Core logic
    
#     # a. Check for pending reboot
#     $rebootRequired = $false
#     $rebootPaths = @(
#         "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
#         "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
#     )
#     foreach ($path in $rebootPaths) {
#         if (Test-Path $path) {
#             $rebootRequired = $true
#             break
#         }
#     }

#     # b. Check if disabled by policy
#     $isDisabledByPolicy = $false
#     try {
#         $auPolicy = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
#         if ($auPolicy -and $auPolicy.PSObject.Properties['NoAutoUpdate'] -and $auPolicy.NoAutoUpdate -eq 1) {
#             $isDisabledByPolicy = $true
#         }
#     } catch { }

#     # c. Get last update check time from registry
#     $lastCheckTime = $null
#     try {
#         $auState = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect" -ErrorAction SilentlyContinue
#         if ($auState -and $auState.PSObject.Properties['LastSuccessTime']) {
#             $lastCheckTime = $auState.LastSuccessTime
#         }
#     } catch { }

#     # d. Get last install time
#     $lastInstallTime = $null
#     try {
#         $installState = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install" -ErrorAction SilentlyContinue
#         if ($installState -and $installState.PSObject.Properties['LastSuccessTime']) {
#             $lastInstallTime = $installState.LastSuccessTime
#         }
#     } catch { }

#     # e. Get Windows Update service status
#     $wuServiceStatus = 'Unknown'
#     try {
#         $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
#         if ($wuService) {
#             $wuServiceStatus = $wuService.Status.ToString()
#         }
#     } catch { }

#     # f. Check for available updates using COM (may require admin for full results)
#     $availableUpdatesCount = 0
#     $pendingUpdates = @()
#     $comError = $null
    
#     try {
#         $updateSession = New-Object -ComObject "Microsoft.Update.Session"
#         $updateSearcher = $updateSession.CreateUpdateSearcher()
        
#         # Search for pending updates (IsInstalled=0)
#         $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
#         $availableUpdatesCount = $searchResult.Updates.Count
        
#         # Get first 10 pending updates info
#         $maxUpdates = [Math]::Min($searchResult.Updates.Count, 10)
#         for ($i = 0; $i -lt $maxUpdates; $i++) {
#             $update = $searchResult.Updates.Item($i)
#             $pendingUpdates += @{
#                 title = $update.Title
#                 kb_article_ids = @($update.KBArticleIDs | ForEach-Object { "KB$_" })
#                 is_mandatory = $update.IsMandatory
#                 severity = if ($update.PSObject.Properties['MsrcSeverity']) { $update.MsrcSeverity } else { $null }
#             }
#         }
#     } catch {
#         $comError = $_.Exception.Message
#     }

#     # g. Get recent update history
#     $recentHistory = @()
#     try {
#         $updateSession = New-Object -ComObject "Microsoft.Update.Session"
#         $updateSearcher = $updateSession.CreateUpdateSearcher()
#         $historyCount = $updateSearcher.GetTotalHistoryCount()
        
#         if ($historyCount -gt 0) {
#             $maxHistory = [Math]::Min($historyCount, 5)
#             $history = $updateSearcher.QueryHistory(0, $maxHistory)
            
#             for ($i = 0; $i -lt $history.Count; $i++) {
#                 $entry = $history.Item($i)
#                 $recentHistory += @{
#                     title = $entry.Title
#                     date = if ($entry.Date) { $entry.Date.ToString('o') } else { $null }
#                     result_code = switch ($entry.ResultCode) {
#                         0 { 'NotStarted' }
#                         1 { 'InProgress' }
#                         2 { 'Succeeded' }
#                         3 { 'SucceededWithErrors' }
#                         4 { 'Failed' }
#                         5 { 'Aborted' }
#                         default { "Unknown($($entry.ResultCode))" }
#                     }
#                 }
#             }
#         }
#     } catch { }

#     $result = @{
#         reboot_required = $rebootRequired
#         is_disabled_by_policy = $isDisabledByPolicy
#         available_updates_count = $availableUpdatesCount
#         pending_updates = $pendingUpdates
#         recent_history = $recentHistory
#         last_check_time = $lastCheckTime
#         last_install_time = $lastInstallTime
#         wu_service_status = $wuServiceStatus
#     }
    
#     # 5. Success output
#     $extraMeta = @{}
#     if ($comError) {
#         $extraMeta['com_error'] = $comError
#     }
#     Emit-Success $result $extraMeta

# } catch {
#     $exceptionMessage = $_.Exception.Message
#     Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
#         script_path = $MyInvocation.MyCommand.Path
#         line_number = $_.InvocationInfo.ScriptLineNumber
#     }
# }

# get_os_update_status.ps1
# V1.1.2 L1 Skill - Get Windows Update status (Ultra Fast Mode)

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
$script:SkillArgs = $null
$global:__hasEmitted = $false
$__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
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
    $finalMetadata['skill_version'] = "1.1.2"

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
    
    $finalMetadata = @{
        exec_time_ms = $__sw.ElapsedMilliseconds
        skill_version = "1.1.2"
    }

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
    if ($InputFile -and (Test-Path $InputFile)) {
        $InputObject = Get-Content -Path $InputFile -Raw -Encoding UTF8
    }
    if ($InputObject) {
        $script:SkillArgs = $InputObject | ConvertFrom-Json
    }

    # --- Core Logic ---

    # 1. Pending Reboot (Registry - Ultra Fast)
    $rebootRequired = $false
    $rebootPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    )
    foreach ($path in $rebootPaths) {
        if (Test-Path $path) { $rebootRequired = $true; break }
    }

    # 2. Service Status (Fast)
    $wuServiceStatus = 'Unknown'
    $isServiceRunning = $false
    try {
        $svc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($svc) {
            $wuServiceStatus = $svc.Status.ToString()
            if ($svc.Status -eq 'Running') { $isServiceRunning = $true }
        }
    } catch {}

    # 3. Policy & Timestamps (Registry - Fast)
    $isDisabledByPolicy = $false
    $lastCheckTime = $null
    $lastInstallTime = $null
    
    try {
        $auPolicy = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
        if ($auPolicy.NoAutoUpdate -eq 1) { $isDisabledByPolicy = $true }
        
        $detectState = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect" -ErrorAction SilentlyContinue
        if ($detectState.LastSuccessTime) { $lastCheckTime = $detectState.LastSuccessTime }

        $installState = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install" -ErrorAction SilentlyContinue
        if ($installState.LastSuccessTime) { $lastInstallTime = $installState.LastSuccessTime }
    } catch {}

    # 4. Updates & History (COM - The Slow Part)
    $availableUpdatesCount = 0
    $pendingUpdates = @()
    $recentHistory = @()
    $scanMode = "Skipped (Service Stopped)" # Default if we skip

    if ($isServiceRunning) {
        $scanMode = "Offline/Cache"
        try {
            $updateSession = New-Object -ComObject "Microsoft.Update.Session"
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $updateSearcher.Online = $false # Offline only

            # 4a. Search Pending
            $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
            $availableUpdatesCount = $searchResult.Updates.Count
            
            # Optimized loop (avoid pipeline overhead)
            $count = $searchResult.Updates.Count
            if ($count -gt 0) {
                $limit = if ($count -lt 10) { $count } else { 10 }
                for ($i = 0; $i -lt $limit; $i++) {
                    $u = $searchResult.Updates.Item($i)
                    # Extract KB explicitly to avoid COM overhead in loop
                    $kbs = $u.KBArticleIDs
                    $kbStr = @()
                    foreach ($k in $kbs) { $kbStr += "KB$k" }
                    
                    $pendingUpdates += @{
                        title = $u.Title
                        kb_article_ids = $kbStr
                        is_mandatory = $u.IsMandatory
                    }
                }
            }

            # 4b. History
            $histCount = $updateSearcher.GetTotalHistoryCount()
            if ($histCount -gt 0) {
                $limit = if ($histCount -lt 5) { $histCount } else { 5 }
                $historyParams = $updateSearcher.QueryHistory(0, $limit)
                for ($i = 0; $i -lt $historyParams.Count; $i++) {
                    $h = $historyParams.Item($i)
                    # Map result code manually for speed
                    $rc = "Unknown"
                    switch ($h.ResultCode) {
                        2 { $rc = 'Succeeded' }
                        4 { $rc = 'Failed' }
                        default { $rc = $h.ResultCode.ToString() }
                    }
                    $recentHistory += @{
                        title = $h.Title
                        date = $h.Date.ToString('o')
                        result_code = $rc
                    }
                }
            }
        } catch {
            $scanMode = "Failed: $($_.Exception.Message)"
        }
    }

    $result = @{
        reboot_required = $rebootRequired
        is_disabled_by_policy = $isDisabledByPolicy
        available_updates_count = $availableUpdatesCount
        pending_updates = $pendingUpdates
        recent_history = $recentHistory
        last_check_time = $lastCheckTime
        last_install_time = $lastInstallTime
        wu_service_status = $wuServiceStatus
        scan_mode = $scanMode
    }
    
    Emit-Success $result

} catch {
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $_.Exception.Message
}