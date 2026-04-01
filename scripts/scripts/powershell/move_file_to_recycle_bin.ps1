# move_file_to_recycle_bin.ps1
# V1.1.0 L1 Skill - Move to Recycle Bin

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

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
    # Support single path or multiple paths
    $paths = @()
    
    # Check for file_path (single file/folder)
    if ($Parameter -and $Parameter.PSObject.Properties['file_path']) {
        $filePath = $Parameter.file_path
        if ($filePath) {
            $paths += $filePath
        }
    }
    
    # Check for paths (multiple files/folders)
    if ($Parameter -and $Parameter.PSObject.Properties['paths']) {
        $pathsArray = $Parameter.paths
        if ($pathsArray -is [array]) {
            foreach ($p in $pathsArray) {
                if ($p) {
                    $paths += $p
                }
            }
        } else {
            if ($pathsArray) {
                $paths += $pathsArray
            }
        }
    }
    
    if ($paths.Count -eq 0) {
        Emit-Error 'INVALID_ARGUMENT' 'Parameter "file_path" or "paths" is required.'
        return
    }

    $dryRun = if ($Parameter -and $Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }
    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'; 
            would_perform_action = "Move $($paths.Count) item(s) to Recycle Bin: $($paths -join ', ')" 
        }
        return
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $results = @()
    $failedItems = @()
    
    foreach ($path in $paths) {
        if (-not $path) { continue }
        
        if (-not (Test-Budget $__sw $BudgetMs)) {
            Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget during processing." $true @{
                processed_count = $results.Count
                failed_count = $failedItems.Count
            }
            return
        }
        
        if (-not (Test-Path $path)) {
            $failedItems += @{
                path = $path
                reason = "Path not found"
            }
            continue
        }
        
        try {
            $isDirectory = Test-Path $path -PathType Container
            
            if ($isDirectory) {
                # Delete directory
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                $results += @{
                    path = $path
                    type = "directory"
                    status = "moved_to_recycle_bin"
                }
            } else {
                # Delete file
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                $results += @{
                    path = $path
                    type = "file"
                    status = "moved_to_recycle_bin"
                }
            }
        } catch {
            $failedItems += @{
                path = $path
                reason = $_.Exception.Message
            }
        }
    }
    
    # Build result
    $data = @{
        total_count = $paths.Count
        success_count = $results.Count
        failed_count = $failedItems.Count
        results = $results
    }
    
    if ($failedItems.Count -gt 0) {
        $data['failed_items'] = $failedItems
    }
    
    if ($failedItems.Count -eq $paths.Count) {
        # All failed
        Emit-Error 'SCRIPT_EXECUTION_FAILED' "Failed to move all items to Recycle Bin." $false @{
            failed_items = $failedItems
        }
    } elseif ($failedItems.Count -gt 0) {
        # Partial failure
        Emit-Success $data @{
            partial_failure = $true
        }
    } else {
        # All success
        Emit-Success $data
    }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
