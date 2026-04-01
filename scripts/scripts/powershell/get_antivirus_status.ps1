# get_antivirus_status.ps1
# V1.1.0 L1 Skill - Get antivirus software status

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

# Parse productState bitmask
function Parse-ProductState($state) {
    $hex = '{0:X6}' -f $state
    $signatureByte = [int]('0x' + $hex.Substring(2, 2))
    $productByte = [int]('0x' + $hex.Substring(4, 2))
    
    $enabled = ($productByte -band 0x10) -ne 0
    $upToDate = ($signatureByte -band 0x10) -eq 0
    
    return @{
        enabled = $enabled
        up_to_date = $upToDate
        raw_state = $state
    }
}

try {
    # 3. Parameter injection - support InputFile
    if ($InputFile -and (Test-Path $InputFile)) {
        $InputObject = Get-Content -Path $InputFile -Raw -Encoding UTF8
    }
    $script:SkillArgs = $InputObject | ConvertFrom-Json

    # 4. Core logic
    $antivirusProducts = @()
    $defenderStatus = $null
    
    # Query SecurityCenter2 (Windows Vista+)
    try {
        $avProducts = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue)
        
        foreach ($av in $avProducts) {
            $stateInfo = Parse-ProductState $av.productState
            $antivirusProducts += @{
                display_name = $av.displayName
                instance_guid = $av.instanceGuid
                path_to_signed_product_exe = $av.pathToSignedProductExe
                path_to_signed_reporting_exe = $av.pathToSignedReportingExe
                enabled = $stateInfo.enabled
                up_to_date = $stateInfo.up_to_date
                product_state_raw = $stateInfo.raw_state
            }
        }
    } catch {
        # SecurityCenter2 may not be available on server editions
    }
    
    # Additional Windows Defender status check (more detailed)
    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop
        $defenderStatus = @{
            antivirus_enabled = $mpStatus.AntivirusEnabled
            antispyware_enabled = $mpStatus.AntispywareEnabled
            real_time_protection_enabled = $mpStatus.RealTimeProtectionEnabled
            behavior_monitor_enabled = $mpStatus.BehaviorMonitorEnabled
            ioav_protection_enabled = $mpStatus.IoavProtectionEnabled
            nis_enabled = $mpStatus.NISEnabled
            on_access_protection_enabled = $mpStatus.OnAccessProtectionEnabled
            antivirus_signature_age = $mpStatus.AntivirusSignatureAge
            antispyware_signature_age = $mpStatus.AntispywareSignatureAge
            antivirus_signature_last_updated = if ($mpStatus.AntivirusSignatureLastUpdated) { $mpStatus.AntivirusSignatureLastUpdated.ToString('o') } else { $null }
            full_scan_age = $mpStatus.FullScanAge
            quick_scan_age = $mpStatus.QuickScanAge
            computer_state = $mpStatus.ComputerState
        }
    } catch {
        # Get-MpComputerStatus may not be available
    }

    # 5. Success output
    $enabledProducts = @($antivirusProducts | Where-Object { $_.enabled })
    $outdatedProducts = @($antivirusProducts | Where-Object { -not $_.up_to_date })
    
    $anyEnabled = $enabledProducts.Count -gt 0
    $allUpToDate = $outdatedProducts.Count -eq 0
    
    Emit-Success @{
        antivirus_products = $antivirusProducts
        product_count = $antivirusProducts.Count
        any_enabled = $anyEnabled
        all_up_to_date = $allUpToDate
        windows_defender_detail = $defenderStatus
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
