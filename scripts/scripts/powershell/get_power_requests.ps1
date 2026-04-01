# get_power_requests.ps1
# V1.1.0 L1 Skill - Get power requests (processes blocking sleep/display)
# expected_cost: 'low'
# danger_level: 'P0_READ'
# group: C12 (Power Temperature)
# Note: Requires administrator privileges for powercfg /requests

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. UAC elevation (required for powercfg /requests)
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
                $errBody = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Elevated process did not generate output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $errBody
            }
        }
        exit $process.ExitCode
    } catch {
        $errBody = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Failed to elevate privileges: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
        Write-Output $errBody
        exit 1
    }
}

# Handle InputFile (for elevated subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# 1. Strict mode and environment setup
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
    if ($script:SkillArgs -and $script:SkillArgs.PSObject.Properties['metadata'] -and $script:SkillArgs.metadata) {
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
    if ($script:SkillArgs -and $script:SkillArgs.PSObject.Properties['metadata'] -and $script:SkillArgs.metadata) {
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
        $script:SkillArgs = @{ parameter = @{}; metadata = @{} }
    }

    # 4. Core logic - Get power requests via powercfg
    
    # Handle GBK encoding for Chinese Windows
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
    } catch { }
    
    $powercfgOutput = & powercfg /requests 2>&1
    [Console]::OutputEncoding = $prevEncoding
    
    # Parse output by category
    $categories = @{
        'DISPLAY' = @()
        'SYSTEM' = @()
        'AWAYMODE' = @()
        'EXECUTION' = @()
        'PERFBOOST' = @()
        'ACTIVELOCKSCREEN' = @()
    }
    
    $currentCategory = $null
    
    foreach ($line in $powercfgOutput) {
        $lineStr = $line.ToString().Trim()
        
        # Detect category headers (English)
        if ($lineStr -match '^(DISPLAY|SYSTEM|AWAYMODE|EXECUTION|PERFBOOST|ACTIVELOCKSCREEN):?\s*$') {
            $currentCategory = $Matches[1]
            continue
        }
        
        # Detect category headers (Chinese Windows)
        $chineseMapping = @{
            'DISPLAY' = 'DISPLAY'
            'SYSTEM' = 'SYSTEM'
            'AWAYMODE' = 'AWAYMODE'
            'EXECUTION' = 'EXECUTION'
            'PERFBOOST' = 'PERFBOOST'
            'ACTIVELOCKSCREEN' = 'ACTIVELOCKSCREEN'
        }
        if ($lineStr -match '^DISPLAY:' -or $lineStr -match '^SYSTEM:' -or $lineStr -match '^AWAYMODE:' -or $lineStr -match '^EXECUTION:' -or $lineStr -match '^PERFBOOST:' -or $lineStr -match '^ACTIVELOCKSCREEN:') {
            $currentCategory = ($lineStr -split ':')[0].Trim().ToUpper()
            continue
        }
        
        # Skip empty lines and "None" lines (English and Chinese)
        if ([string]::IsNullOrWhiteSpace($lineStr)) { continue }
        if ($lineStr -eq 'None.' -or $lineStr -match '^None\.?\s*$') { continue }
        # Skip Chinese "None" equivalents
        if ($lineStr -match '^\s*$') { continue }
        # Skip lines that are just category names or "None" in any language
        if ($lineStr -match '^(DISPLAY|SYSTEM|AWAYMODE|EXECUTION|PERFBOOST|ACTIVELOCKSCREEN)') { continue }
        
        # Collect requestor information - only if it looks like a real request
        if ($currentCategory -and $categories.ContainsKey($currentCategory)) {
            # Only process lines that look like actual requests (contain [PROCESS], [DRIVER], [SERVICE] or a path)
            if ($lineStr -match '^\[(PROCESS|DRIVER|SERVICE)\]\s*(.+)') {
                $requestType = $Matches[1]
                $requestor = $Matches[2]
                
                # Extract process name from path
                $processName = $null
                if ($requestor -match '\\([^\\]+\.exe)') {
                    $processName = $Matches[1]
                } elseif ($requestor -match '([^\\]+\.exe)') {
                    $processName = $Matches[1]
                }
                
                $categories[$currentCategory] += @{
                    type = $requestType
                    requestor = $requestor
                    process_name = $processName
                }
            }
            # Also handle Chinese format [process] [driver] [service]
            elseif ($lineStr -match '^\[.+\]\s*.+\.exe') {
                $requestType = 'PROCESS'
                $requestor = $lineStr
                
                $processName = $null
                if ($requestor -match '\\([^\\]+\.exe)') {
                    $processName = $Matches[1]
                } elseif ($requestor -match '([^\\]+\.exe)') {
                    $processName = $Matches[1]
                }
                
                $categories[$currentCategory] += @{
                    type = $requestType
                    requestor = $requestor
                    process_name = $processName
                }
            }
        }
    }
    
    # Calculate statistics
    $totalRequests = 0
    foreach ($cat in $categories.Keys) {
        $totalRequests += $categories[$cat].Count
    }
    
    $blockingSleep = ($categories['SYSTEM'].Count -gt 0) -or ($categories['EXECUTION'].Count -gt 0)
    $blockingDisplay = $categories['DISPLAY'].Count -gt 0
    
    # Generate recommendations
    $issues = @()
    $recommendations = @()
    
    if ($blockingSleep) {
        $issues += 'System sleep is being blocked'
        $blockers = @()
        $blockers += $categories['SYSTEM'] | ForEach-Object { $_.process_name }
        $blockers += $categories['EXECUTION'] | ForEach-Object { $_.process_name }
        $blockers = @($blockers | Where-Object { $_ } | Select-Object -Unique)
        if ($blockers.Count -gt 0) {
            $recommendations += "Close or check these applications: $($blockers -join ', ')"
        }
    }
    
    if ($blockingDisplay) {
        $issues += 'Display power-off is being blocked'
        $displayBlockers = @($categories['DISPLAY'] | ForEach-Object { $_.process_name } | Where-Object { $_ } | Select-Object -Unique)
        if ($displayBlockers.Count -gt 0) {
            $recommendations += "Display blocked by: $($displayBlockers -join ', ')"
        }
    }

    # 5. Output result
    Emit-Success @{
        display_requests = $categories['DISPLAY']
        system_requests = $categories['SYSTEM']
        awaymode_requests = $categories['AWAYMODE']
        execution_requests = $categories['EXECUTION']
        perfboost_requests = $categories['PERFBOOST']
        activelockscreen_requests = $categories['ACTIVELOCKSCREEN']
        total_requests = $totalRequests
        blocking_sleep = $blockingSleep
        blocking_display = $blockingDisplay
        has_power_requests = $totalRequests -gt 0
        issues = $issues
        recommendations = $recommendations
        status = if ($blockingSleep) { 'warning' } elseif ($totalRequests -gt 0) { 'info' } else { 'ok' }
        diagnosis = if ($blockingSleep) {
            "System cannot enter sleep mode due to active power requests"
        } elseif ($blockingDisplay) {
            "Display cannot turn off due to active power requests"
        } else {
            "No active power requests blocking sleep or display"
        }
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
