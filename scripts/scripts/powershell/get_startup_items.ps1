# get_startup_items.ps1
# V1.1.0 L1 Skill - Get startup items list

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 1. Strict mode and environment setup
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# Handle InputFile (for subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# 2. Unified JSON output functions
$global:__hasEmitted = $false
$__sw = New-Object System.Diagnostics.Stopwatch; $__sw.Start()
$script:SkillArgs = $null
$script:OutputFilePath = $OutputFile

function Emit-Success($data, $extraMeta = @{}) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true

    # Merge with metadata passed from host
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
    $json = $body | ConvertTo-Json -Depth 8 -Compress
    if ($script:OutputFilePath) {
        [System.IO.File]::WriteAllText($script:OutputFilePath, $json, [System.Text.UTF8Encoding]::new($false))
    } else {
        Write-Output $json
    }
}

function Emit-Error($code, $message, $retriable = $false, $extraMeta = @{}) {
    if ($global:__hasEmitted) { return }
    $global:__hasEmitted = $true

    # Merge with metadata passed from host
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

# 3. Lightweight budget guard
function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

# Helper function to get publisher from a file path
function Get-Publisher($path) {
    try {
        $publisher = (Get-AuthenticodeSignature -FilePath $path -ErrorAction SilentlyContinue).SignerCertificate.SubjectName.Name
        if ($publisher) {
            return $publisher.Split(',') | Where-Object { $_.Trim().StartsWith('O=') } | ForEach-Object { $_.Split('=')[1].Trim() } | Select-Object -First 1
        }
    } catch {}
    return "Unknown"
}

try {
    # 4. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    if (-not $script:SkillArgs) {
        Emit-Error 'INVALID_ARGUMENT' 'Invalid or empty SkillArgs JSON payload.' $false
        return
    }
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
    $limit = if ($Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 50 }
    $sortBy = if ($Parameter.PSObject.Properties['sort_by']) { $Parameter.sort_by } else { 'name' }

    $startupItems = @()

    # a. Registry
    $regPaths = @{
        "Registry_HKCU" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";
        "Registry_HKLM" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
        "Registry_HKLM_Wow64" = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";
    }
    foreach ($source in $regPaths.Keys) {
        $path = $regPaths[$source]
        if (Test-Path $path) {
            $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                    $name = $_.Name
                    $command = $_.Value
                    if ($command -and $name) {
                        $startupItems += @{
                            name = $name
                            command = $command
                            source = $source
                            publisher = Get-Publisher ($command.Split(' ')[0].Trim('"'))
                            is_enabled = $true
                            startup_id = "REGISTRY::$($path)::$($name)"
                        }
                    }
                }
            }
        }
    }

    # b. Startup Folders
    $folderPaths = @{
        "StartupFolder_User" = [Environment]::GetFolderPath('Startup');
        "StartupFolder_Common" = [Environment]::GetFolderPath('CommonStartup');
    }
    foreach ($source in $folderPaths.Keys) {
        $path = $folderPaths[$source]
        if (Test-Path $path) {
            Get-ChildItem -Path $path | Where-Object { !$_.PSIsContainer } | ForEach-Object {
                $startupItems += @{
                    name = $_.Name
                    command = $_.FullName
                    source = $source
                    publisher = Get-Publisher $_.FullName
                    is_enabled = $true
                    startup_id = "FOLDER::$($_.FullName)"
                }
            }
        }
    }

    # c. Scheduled Tasks
    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
            $triggers = $_.Triggers
            if ($triggers) {
                ($triggers | Where-Object { 
                    $_.PSObject.Properties['Enabled'] -and $_.Enabled -and 
                    $_.PSObject.Properties['TriggerType'] -and $_.TriggerType -eq 'Logon' 
                }).Count -gt 0
            } else {
                $false
            }
        } | ForEach-Object {
            $task = $_
            $action = if ($task.Actions -and $task.Actions.Count -gt 0) { $task.Actions[0] } else { $null }
            $command = if ($action -and $action.PSObject.Properties['Execute'] -and $action.Execute) { 
                $exec = $action.Execute
                $args = if ($action.PSObject.Properties['Arguments']) { $action.Arguments } else { "" }
                "$exec $args"
            } else { 
                "N/A" 
            }
            
            $isEnabled = $true
            if ($task.PSObject.Properties['State']) {
                $isEnabled = $task.State -ne 'Disabled'
            }
            
            $startupItems += @{
                name = $task.TaskName
                command = $command.Trim()
                source = "TaskScheduler"
                publisher = if ($action -and $action.PSObject.Properties['Execute'] -and $action.Execute) { 
                    Get-Publisher ($action.Execute.Trim('"')) 
                } else { 
                    "Unknown" 
                }
                is_enabled = $isEnabled
                startup_id = "TASK::$($task.TaskPath)::$($task.TaskName)"
            }
        }
    } catch {
        # Ignore if can't get scheduled tasks
    }
    
    # Sort
    $sortedItems = switch ($sortBy) {
        'publisher' { $startupItems | Sort-Object publisher }
        'source' { $startupItems | Sort-Object source }
        default { $startupItems | Sort-Object name }
    }

    # Limit
    $limitedItems = $sortedItems | Select-Object -First $limit

    # 7. Success output
    Emit-Success @{ 
        startup_items = $limitedItems 
        total_found = $startupItems.Count
        returned_count = $limitedItems.Count
    }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
