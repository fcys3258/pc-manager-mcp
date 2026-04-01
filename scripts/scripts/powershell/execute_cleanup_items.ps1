# execute_cleanup_items.ps1
# V1.1.0 L1 Skill - Execute disk cleanup (Optimized)

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# IDs that require admin privileges (system directories)
$script:SystemCleanupIds = @('SYSTEM_TEMP', 'CRASH_DUMPS', 'WINDOWS_UPDATE_CACHE')

# Helper: Check if cleanup_ids contain system items requiring elevation
function Test-NeedsElevation($cleanupIds) {
    foreach ($id in $cleanupIds) {
        if ($id -in $script:SystemCleanupIds) {
            return $true
        }
    }
    return $false
}

# Extract cleanup_ids from input for elevation check
$checkCleanupIds = @()
if ($InputFile -and (Test-Path $InputFile)) {
    try {
        $tempInput = Get-Content $InputFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($tempInput.parameter -and $tempInput.parameter.PSObject.Properties['cleanup_ids']) {
            $checkCleanupIds = $tempInput.parameter.cleanup_ids
        }
    } catch {}
} elseif ($InputObject) {
    try {
        $tempInput = $InputObject | ConvertFrom-Json
        if ($tempInput.parameter -and $tempInput.parameter.PSObject.Properties['cleanup_ids']) {
            $checkCleanupIds = $tempInput.parameter.cleanup_ids
        }
    } catch {}
}

# 0. Conditional auto-elevate (only for system cleanup items)
$needsElevation = Test-NeedsElevation $checkCleanupIds
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($needsElevation -and -not $isAdmin) {
    try {
        $outputFileParam = if ($OutputFile) { $OutputFile } else { Join-Path $env:TEMP "ps_output_$([guid]::NewGuid()).json" }
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
        
        $inputFileTemp = $null
        if ($InputObject) {
            $inputFileTemp = Join-Path $env:TEMP "ps_input_$([guid]::NewGuid()).json"
            [System.IO.File]::WriteAllText($inputFileTemp, $InputObject, [System.Text.UTF8Encoding]::new($false))
            $argList += "-InputFile"
            $argList += $inputFileTemp
        } elseif ($InputFile -and (Test-Path $InputFile)) {
            $argList += "-InputFile"
            $argList += $InputFile
        }
        
        $argList += "-OutputFile"
        $argList += $outputFileParam
        
        $process = Start-Process powershell -Verb RunAs -ArgumentList $argList -PassThru -Wait
        
        if ($inputFileTemp -and (Test-Path $inputFileTemp)) {
            Remove-Item $inputFileTemp -Force -ErrorAction SilentlyContinue
        }
        
        if (-not $OutputFile) {
            $timeout = 100
            $elapsed = 0
            while (-not (Test-Path $outputFileParam) -and $elapsed -lt $timeout) {
                Start-Sleep -Milliseconds 100
                $elapsed++
            }
            if (Test-Path $outputFileParam) {
                $output = Get-Content $outputFileParam -Raw -Encoding UTF8
                Write-Output $output
                Remove-Item $outputFileParam -Force -ErrorAction SilentlyContinue
            } else {
                $err = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Admin process did not generate output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $err
            }
        }
        exit $process.ExitCode
    } catch {
        $err = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Privilege elevation failed: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
        Write-Output $err
        exit 1
    }
}

# Handle InputFile (subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

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

# 3. Budget guard
function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

function Clear-Folder($path) {
    if (Test-Path $path) {
        # Use Get-ChildItem -Force to enumerate all files (including hidden/system) then delete, only clear folder contents without deleting root directory itself
        Get-ChildItem -Path $path -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    # 4. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $Parameter = $script:SkillArgs.parameter
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }

    # 5. Check budget
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # 6. Core logic
    # Safe access to cleanup_ids parameter
    $cleanupIds = @()
    if ($Parameter -and $Parameter.PSObject.Properties['cleanup_ids']) {
        $cleanupIds = $Parameter.cleanup_ids
    }
    
    if (-not $cleanupIds -or $cleanupIds.Count -eq 0) {
        Emit-Error 'INVALID_ARGUMENT' 'Parameter "cleanup_ids" is required and must be a non-empty array.' $false
        return
    }

    $dryRun = if ($Parameter -and $Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }

    if ($dryRun) {
        $actions = @()
        foreach ($id in $cleanupIds) {
            switch ($id) {
                "SYSTEM_TEMP" { $actions += "Clear System Temp ($($env:windir + '\Temp'))" }
                "USER_TEMP" { $actions += "Clear User Temp ($env:TEMP)" }
                "RECYCLE_BIN" { $actions += "Empty Recycle Bin" }
                "CRASH_DUMPS" { $actions += "Clear Crash Dumps ($($env:windir + '\Minidump'))" }
                "WECHAT_CACHE" { $actions += "Clear WeChat Cache (WARNING: Deletes chat history!)" }
                "WXWORK_CACHE" { $actions += "Clear WXWork Cache (WARNING: Deletes chat history!)" }
                "BROWSER_CACHE" { $actions += "Clear Browser Cache (Chrome/Edge)" }
                "WINDOWS_UPDATE_CACHE" { $actions += "Clear Windows Update Cache" }
                default { $actions += "Unknown ID: $id" }
            }
        }
        Emit-Success @{ 
            result = 'dry_run'
            would_perform_action = "Cleanup items: $($actions -join ', ')"
            cleanup_ids = $cleanupIds
        }
        return
    }
    
    $results = @()
    
    # Get user documents path (compatible with non-standard configurations)
    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $userProfile = $env:USERPROFILE
    
    # Helper function to safely terminate processes
    function Stop-ProcessSafely($processNames) {
        $killed = @()
        foreach ($name in $processNames) {
            $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
            if ($procs) {
                $procs | Stop-Process -Force -ErrorAction SilentlyContinue
                $killed += $name
            }
        }
        return $killed
    }
    
    # Clear folder contents with exclusions
    function Clear-FolderWithExclusions($path, $exclusions) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin $exclusions } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($id in $cleanupIds) {
        $res = @{ id = $id; status = "failed"; reason = "Unknown ID" }
        try {
            switch ($id) {
                "SYSTEM_TEMP" {
                    Clear-Folder ($env:windir + "\Temp")
                    $res.status = "completed"
                    $res.reason = "System temporary files cleared."
                }
                "USER_TEMP" {
                    Clear-Folder ($env:TEMP)
                    $res.status = "completed"
                    $res.reason = "User temporary files cleared."
                }
                "RECYCLE_BIN" {
                    $shell = New-Object -ComObject Shell.Application
                    try {
                        $recycleBin = $shell.NameSpace(10)
                        $recycleBin.Items() | ForEach-Object { Remove-Item -Path $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
                        $res.status = "completed"
                        $res.reason = "Recycle Bin emptied."
                    } finally {
                        # Release COM object
                        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
                        [System.GC]::Collect()
                        [System.GC]::WaitForPendingFinalizers()
                    }
                }
                "CRASH_DUMPS" {
                    Clear-Folder ($env:windir + "\Minidump")
                    # Also clear user-level crash dumps
                    Clear-Folder "$env:LOCALAPPDATA\CrashDumps"
                    $res.status = "completed"
                    $res.reason = "Crash dumps cleared."
                }
                "WECHAT_CACHE" {
                    # Terminate WeChat processes
                    $killed = Stop-ProcessSafely @('WeChat', 'Weixin')
                    $wechatPaths = @("$myDocs\WeChat Files", "$myDocs\xwechat_files")
                    $wechatExclusions = @('All Users', 'all_users')
                    foreach ($wpath in $wechatPaths) {
                        Clear-FolderWithExclusions $wpath $wechatExclusions
                    }
                    $res.status = "completed"
                    $res.reason = "WeChat cache cleared. Processes killed: $($killed -join ', ')"
                }
                "WXWORK_CACHE" {
                    # Terminate WXWork processes
                    $killed = Stop-ProcessSafely @('WXWork')
                    $wxworkPath = "$myDocs\WXWork"
                    $wxworkExclusions = @('Global', 'Profiles', 'WeDrive')
                    Clear-FolderWithExclusions $wxworkPath $wxworkExclusions
                    $res.status = "completed"
                    $res.reason = "WXWork cache cleared. Processes killed: $($killed -join ', ')"
                }
                "BROWSER_CACHE" {
                    # Terminate browser processes
                    $killed = Stop-ProcessSafely @('chrome', 'msedge')
                    $browserCachePaths = @(
                        "$userProfile\AppData\Local\Google\Chrome\User Data\Default\Cache",
                        "$userProfile\AppData\Local\Google\Chrome\User Data\Default\Code Cache",
                        "$userProfile\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
                        "$userProfile\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache"
                    )
                    foreach ($bcPath in $browserCachePaths) {
                        Clear-Folder $bcPath
                    }
                    $res.status = "completed"
                    $res.reason = "Browser cache cleared. Processes killed: $($killed -join ', ')"
                }
                "WINDOWS_UPDATE_CACHE" {
                    Clear-Folder "$env:windir\SoftwareDistribution\Download"
                    $res.status = "completed"
                    $res.reason = "Windows Update cache cleared."
                }
            }
        } catch {
            $res.status = "failed"
            $res.reason = $_.Exception.Message
        }
        $results += $res
    }
    
    # 7. Success output - add partial_success summary statistics
    $totalItems = $results.Count
    $completedItems = ($results | Where-Object { $_.status -eq 'completed' }).Count
    $failedItems = $totalItems - $completedItems
    
    $summaryStatus = if ($failedItems -eq 0) {
        'all_success'
    } elseif ($completedItems -eq 0) {
        'all_failed'
    } else {
        'partial_success'
    }
    
    Emit-Success @{ 
        cleanup_results = $results
        summary = @{
            total_items = $totalItems
            completed = $completedItems
            failed = $failedItems
            status = $summaryStatus
        }
    }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
