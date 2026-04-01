# get_pagefile_status.ps1
# V1.1.0 L1 Skill - Get pagefile status

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

try {
    # 3. Parameter injection - support InputFile
    if ($InputFile -and (Test-Path $InputFile)) {
        $InputObject = Get-Content -Path $InputFile -Raw -Encoding UTF8
    }
    $script:SkillArgs = $InputObject | ConvertFrom-Json

    # 4. Core logic - Get pagefile status
    $result = @{
        automatic_managed = $null
        page_files = @()
        current_usage_mb = $null
        peak_usage_mb = $null
        allocated_size_mb = $null
    }
    $fallbackMode = $false
    $cimSuccess = $false

    # Primary path: CIM (Windows 8+)
    try {
        $csArr = @(Get-CimInstance Win32_ComputerSystem -ErrorAction Stop)
        if ($csArr.Count -gt 0) {
            $cs = $csArr[0]
            $result.automatic_managed = [bool]$cs.AutomaticManagedPagefile
            $cimSuccess = $true
        }
    } catch {
        $fallbackMode = $true
    }

    if ($cimSuccess) {
        # Get pagefile settings (only available when not automatic managed)
        $pageFileSettings = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
        foreach ($pf in $pageFileSettings) {
            $result.page_files += @{
                path = $pf.Name
                initial_size_mb = $pf.InitialSize
                maximum_size_mb = $pf.MaximumSize
                source = 'setting'
            }
        }

        # Get current usage (always available, shows actual pagefile)
        $usage = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
        if ($usage.Count -gt 0) {
            $firstUsage = $usage[0]
            $result.current_usage_mb = $firstUsage.CurrentUsage
            $result.peak_usage_mb = $firstUsage.PeakUsage
            $result.allocated_size_mb = $firstUsage.AllocatedBaseSize
            
            # If automatic managed, add pagefile info from usage
            if ($result.automatic_managed -and $result.page_files.Count -eq 0) {
                foreach ($pfu in $usage) {
                    $result.page_files += @{
                        path = $pfu.Name
                        current_size_mb = $pfu.AllocatedBaseSize
                        source = 'usage'
                    }
                }
            }
        }

        # Get virtual memory info
        $osArr = @(Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
        if ($osArr.Count -gt 0) {
            $os = $osArr[0]
            $result['total_virtual_memory_mb'] = [math]::Round($os.TotalVirtualMemorySize / 1024, 2)
            $result['free_virtual_memory_mb'] = [math]::Round($os.FreeVirtualMemory / 1024, 2)
        }
    } else {
        # Fallback path: WMI (Windows 7 compatible)
        try {
            $csArr = @(Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue)
            if ($csArr.Count -gt 0) {
                $cs = $csArr[0]
                $result.automatic_managed = [bool]$cs.AutomaticManagedPagefile
            }
            
            $pfUsage = @(Get-WmiObject Win32_PageFileUsage -ErrorAction SilentlyContinue)
            if ($pfUsage.Count -gt 0) {
                $firstUsage = $pfUsage[0]
                $result.current_usage_mb = $firstUsage.CurrentUsage
                $result.peak_usage_mb = $firstUsage.PeakUsage
                $result.allocated_size_mb = $firstUsage.AllocatedBaseSize
            }
        } catch {
            # WMI also failed, continue with partial data
        }
    }

    # 5. Success output
    $extraMeta = @{}
    if ($fallbackMode) {
        $extraMeta['fallback_mode'] = $true
    }
    
    Emit-Success $result $extraMeta

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
