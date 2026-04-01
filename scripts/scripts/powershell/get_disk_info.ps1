# get_disk_info.ps1
# V1.1.0 L1 Skill - Get disk space information

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
    # Get optional drive_letter parameter
    $driveLetter = $null
    if ($Parameter -and $Parameter.PSObject.Properties['drive_letter']) {
        $driveLetter = $Parameter.drive_letter.ToUpper()
        # Validate drive_letter format
        if ($driveLetter -notmatch '^[A-Z]$') {
            Emit-Error 'INVALID_ARGUMENT' "Invalid drive_letter: $driveLetter. Must be a single letter A-Z."
            return
        }
    }

    $disks = @()
    $fallback = $false
    try {
        # Primary path: Get-Volume
        Get-Volume | ForEach-Object {
            if ($_.DriveLetter) {
                # If drive_letter specified, only return matching
                if ($driveLetter -and $_.DriveLetter -ne $driveLetter) {
                    return
                }
                $disks += @{
                    drive_letter = $_.DriveLetter
                    file_system = $_.FileSystem
                    size_gb = [math]::Round($_.Size / 1GB, 2)
                    size_remaining_gb = [math]::Round($_.SizeRemaining / 1GB, 2)
                }
            }
        }
    } catch {
        # Fallback path: Win32_LogicalDisk
        $fallback = $true
        $filter = "DriveType=3"
        if ($driveLetter) {
            $deviceID = "$driveLetter" + ":"
            $filter = "DriveType=3 AND DeviceID='$deviceID'"
        }
        Get-CimInstance Win32_LogicalDisk -Filter $filter | ForEach-Object {
            $disks += @{
                drive_letter = $_.DeviceID.Substring(0,1)
                file_system = $_.FileSystem
                size_gb = [math]::Round($_.Size / 1GB, 2)
                size_remaining_gb = [math]::Round($_.FreeSpace / 1GB, 2)
            }
        }
    }
    
    # 7. Success output
    Emit-Success @{ disks = $disks } @{ fallback_mode = $fallback }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
