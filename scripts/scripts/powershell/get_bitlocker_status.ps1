# get_bitlocker_status.ps1
# V1.1.0 L1 Skill - Get BitLocker encryption status

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. Auto-elevate (using InputFile to avoid command line escaping issues)
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
        $err = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Elevation failed: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
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

try {
    # 3. Parameter injection
    if ($InputObject) {
        $script:SkillArgs = $InputObject | ConvertFrom-Json
    } else {
        $script:SkillArgs = @{ metadata = @{} }
    }

    # 4. Core logic
    $volumes = @()
    $fallbackMode = $false

    try {
        # Primary path: Get-BitLockerVolume (requires BitLocker module)
        $blVolumes = @(Get-BitLockerVolume -ErrorAction Stop)
        
        foreach ($vol in $blVolumes) {
            $keyProtectorTypes = @()
            if ($vol.KeyProtector) {
                $keyProtectorTypes = @($vol.KeyProtector | ForEach-Object { $_.KeyProtectorType.ToString() })
            }
            $volumes += @{
                volume = $vol.VolumeType.ToString()
                mount_point = $vol.MountPoint
                protection_status = $vol.ProtectionStatus.ToString()
                encryption_percentage = $vol.EncryptionPercentage
                lock_status = $vol.LockStatus.ToString()
                volume_status = $vol.VolumeStatus.ToString()
                key_protector_types = $keyProtectorTypes
            }
        }
    } catch {
        # Fallback path: manage-bde.exe
        $fallbackMode = $true
        
        # Handle GBK encoding for Chinese Windows
        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
        } catch { }
        
        # Get all fixed disks
        $drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DeviceID)
        
        foreach ($drive in $drives) {
            $bdeOutput = manage-bde.exe -status $drive 2>&1
            
            $protectionStatus = "Unknown"
            $encryptionPercentage = 0
            $lockStatus = "Unknown"
            
            foreach ($line in $bdeOutput) {
                $lineStr = $line.ToString()
                if ($lineStr -match 'Protection Status[:\s]+(\w+)') {
                    $protectionStatus = $Matches[1].Trim()
                }
                if ($lineStr -match 'Percentage Encrypted[:\s]+([\d\.]+)') {
                    $encryptionPercentage = [double]$Matches[1]
                }
                if ($lineStr -match 'Lock Status[:\s]+(\w+)') {
                    $lockStatus = $Matches[1].Trim()
                }
            }
            
            $volumes += @{
                mount_point = $drive
                protection_status = $protectionStatus
                encryption_percentage = $encryptionPercentage
                lock_status = $lockStatus
            }
        }
        
        [Console]::OutputEncoding = $prevEncoding
    }

    # 5. Success output
    $extraMeta = @{}
    if ($fallbackMode) {
        $extraMeta['fallback_mode'] = $true
        $extraMeta['fallback_reason'] = 'BitLocker module not available, using manage-bde.exe'
    }
    
    $protectedVolumes = @($volumes | Where-Object { $_.protection_status -eq 'On' -or $_.protection_status -eq 'FullyEncrypted' })
    
    Emit-Success @{
        volumes = $volumes
        volume_count = $volumes.Count
        all_protected = $protectedVolumes.Count -eq $volumes.Count
    } $extraMeta

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
