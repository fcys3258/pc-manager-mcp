# scan_cleanup_items.ps1
# V1.1.0 L1 Skill - Scan cleanup items

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. Auto-elevate privileges (required for accurate system directory scanning)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
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

function Get-DirectorySize($path) {
    $size = 0
    try {
        if (Test-Path $path) {
            $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }
    } catch {}
    return $size
}

try {
    # 4. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }

    # 5. Check budget
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # 6. Core logic
    $cleanupItems = @()
    
    # System Temp
    $sysTempPath = $env:windir + "\Temp"
    $cleanupItems += @{
        cleanup_id = "SYSTEM_TEMP"
        description = "Windows system temporary files"
        path = $sysTempPath
        size_mb = [math]::Round((Get-DirectorySize $sysTempPath) / 1MB, 2)
    }
    if (-not (Test-Budget $__sw $BudgetMs)) { Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded after scanning System Temp." $true; return }

    # User Temp
    $userTempPath = $env:TEMP
    $cleanupItems += @{
        cleanup_id = "USER_TEMP"
        description = "User temporary files"
        path = $userTempPath
        size_mb = [math]::Round((Get-DirectorySize $userTempPath) / 1MB, 2)
    }
    if (-not (Test-Budget $__sw $BudgetMs)) { Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded after scanning User Temp." $true; return }

    # Recycle Bin
    $shell = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.NameSpace(10)
        $size = ($recycleBin.Items() | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum
        $cleanupItems += @{
            cleanup_id = "RECYCLE_BIN"
            description = "Files in Recycle Bin"
            path = "Recycle Bin"
            size_mb = [math]::Round($size / 1MB, 2)
        }
    } catch {
        $cleanupItems += @{ cleanup_id = "RECYCLE_BIN"; description = "Files in Recycle Bin"; path = "Recycle Bin"; size_mb = 0 }
    } finally {
        if ($shell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }
    if (-not (Test-Budget $__sw $BudgetMs)) { Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded after scanning Recycle Bin." $true; return }

    # Crash Dumps
    $minidumpPath = $env:windir + "\Minidump"
    $cleanupItems += @{
        cleanup_id = "CRASH_DUMPS"
        description = "System crash dumps"
        path = $minidumpPath
        size_mb = [math]::Round((Get-DirectorySize $minidumpPath) / 1MB, 2)
    }
    if (-not (Test-Budget $__sw $BudgetMs)) { Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded after scanning Crash Dumps." $true; return }


    # Get user documents path (compatible with non-standard configurations)
    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    
    # WeChat Cache
    $wechatPaths = @("$myDocs\WeChat Files", "$myDocs\xwechat_files")
    $wechatExclusions = @('All Users', 'all_users')
    $wechatSize = 0
    foreach ($wpath in $wechatPaths) {
        if (Test-Path $wpath) {
            Get-ChildItem -Path $wpath -Directory -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -notin $wechatExclusions } |
                ForEach-Object { $wechatSize += (Get-DirectorySize $_.FullName) }
        }
    }
    $cleanupItems += @{
        cleanup_id = "WECHAT_CACHE"
        description = "WeChat cache (Warning: Permanently deletes chat history and files!)"
        path = $wechatPaths -join "; "
        size_mb = [math]::Round($wechatSize / 1MB, 2)
        warning = "Permanently deletes chat history and files, cannot be recovered!"
    }
    if (-not (Test-Budget $__sw $BudgetMs)) { Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded after scanning WeChat cache." $true; return }

    # WXWork Cache (WeCom)
    $wxworkPath = "$myDocs\WXWork"
    $wxworkExclusions = @('Global', 'Profiles', 'WeDrive')
    $wxworkSize = 0
    if (Test-Path $wxworkPath) {
        Get-ChildItem -Path $wxworkPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $wxworkExclusions } |
            ForEach-Object { $wxworkSize += (Get-DirectorySize $_.FullName) }
    }
    $cleanupItems += @{
        cleanup_id = "WXWORK_CACHE"
        description = "WeCom/WXWork cache (Warning: Permanently deletes chat history and files!)"
        path = $wxworkPath
        size_mb = [math]::Round($wxworkSize / 1MB, 2)
        warning = "Permanently deletes chat history and files, cannot be recovered!"
    }
    if (-not (Test-Budget $__sw $BudgetMs)) { Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded after scanning WXWork cache." $true; return }

    # Browser Cache
    $userProfile = $env:USERPROFILE
    $browserCachePaths = @(
        "$userProfile\AppData\Local\Google\Chrome\User Data\Default\Cache",
        "$userProfile\AppData\Local\Google\Chrome\User Data\Default\Code Cache",
        "$userProfile\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
        "$userProfile\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache"
    )
    $browserCacheSize = 0
    foreach ($bcPath in $browserCachePaths) {
        if (Test-Path $bcPath) {
            $browserCacheSize += (Get-DirectorySize $bcPath)
        }
    }
    $cleanupItems += @{
        cleanup_id = "BROWSER_CACHE"
        description = "Browser cache (Chrome/Edge)"
        path = "Chrome/Edge Cache directories"
        size_mb = [math]::Round($browserCacheSize / 1MB, 2)
    }
    if (-not (Test-Budget $__sw $BudgetMs)) { Emit-Error 'TIME_BUDGET_EXCEEDED' "Budget exceeded after scanning Browser cache." $true; return }

    # Windows Update Cache
    $wuCachePath = "$env:windir\SoftwareDistribution\Download"
    $cleanupItems += @{
        cleanup_id = "WINDOWS_UPDATE_CACHE"
        description = "Windows Update download cache"
        path = $wuCachePath
        size_mb = [math]::Round((Get-DirectorySize $wuCachePath) / 1MB, 2)
    }
    
    # 7. Success output
    Emit-Success @{ cleanup_items = $cleanupItems }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
