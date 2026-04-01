# get_tpm_status.ps1
# V1.1.0 L1 Skill - Get TPM chip status

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
    $tpmData = $null
    $fallbackMode = $false

    try {
        # Primary path: Get-Tpm (Win8+ Cmdlet)
        $tpm = Get-Tpm -ErrorAction Stop
        
        $tpmData = @{
            tpm_present = $tpm.TpmPresent
            tpm_ready = $tpm.TpmReady
            tpm_enabled = $tpm.TpmEnabled
            tpm_activated = $tpm.TpmActivated
            tpm_owned = $tpm.TpmOwned
            manufacturer_id = $tpm.ManufacturerId
            manufacturer_id_txt = $tpm.ManufacturerIdTxt
            manufacturer_version = $tpm.ManufacturerVersion
            manufacturer_version_full = if ($tpm.PSObject.Properties['ManufacturerVersionFull20']) { $tpm.ManufacturerVersionFull20 } else { $null }
            lockout_count = $tpm.LockoutCount
            lockout_max = $tpm.LockoutMax
        }
    } catch {
        # Fallback path: WMI
        $fallbackMode = $true
        
        try {
            $wmiTpmArr = @(Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop)
            $wmiTpm = if ($wmiTpmArr.Count -gt 0) { $wmiTpmArr[0] } else { $null }
            
            if ($wmiTpm) {
                $tpmData = @{
                    tpm_present = $true
                    tpm_enabled = if ($wmiTpm.PSObject.Properties['IsEnabled_InitialValue']) { $wmiTpm.IsEnabled_InitialValue } else { $null }
                    tpm_activated = if ($wmiTpm.PSObject.Properties['IsActivated_InitialValue']) { $wmiTpm.IsActivated_InitialValue } else { $null }
                    tpm_owned = if ($wmiTpm.PSObject.Properties['IsOwned_InitialValue']) { $wmiTpm.IsOwned_InitialValue } else { $null }
                    manufacturer_id = $wmiTpm.ManufacturerId
                    manufacturer_id_txt = $wmiTpm.ManufacturerIdTxt
                    manufacturer_version = $wmiTpm.ManufacturerVersion
                    spec_version = $wmiTpm.SpecVersion
                    physical_presence_version_info = if ($wmiTpm.PSObject.Properties['PhysicalPresenceVersionInfo']) { $wmiTpm.PhysicalPresenceVersionInfo } else { $null }
                }
            } else {
                $tpmData = @{
                    tpm_present = $false
                    tpm_ready = $false
                }
            }
        } catch {
            # TPM completely unavailable
            $tpmData = @{
                tpm_present = $false
                tpm_ready = $false
                detection_error = $_.Exception.Message
            }
        }
    }

    # 5. Success output
    $extraMeta = @{}
    if ($fallbackMode) {
        $extraMeta['fallback_mode'] = $true
        $extraMeta['fallback_reason'] = 'Get-Tpm not available, using WMI'
    }
    
    # Evaluate overall ready status
    $overallReady = $false
    if ($tpmData.tpm_present) {
        if ($null -ne $tpmData.tpm_ready) {
            $overallReady = $tpmData.tpm_ready
        } elseif ($null -ne $tpmData.tpm_enabled -and $null -ne $tpmData.tpm_activated) {
            $overallReady = $tpmData.tpm_enabled -and $tpmData.tpm_activated
        }
    }
    
    Emit-Success @{
        tpm = $tpmData
        overall_ready = $overallReady
        bitlocker_compatible = $overallReady
    } $extraMeta

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
