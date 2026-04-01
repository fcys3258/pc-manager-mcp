# get_active_connections.ps1
# V1.1.0 L1 Skill - Get active network connections
# expected_cost: medium
# danger_level: P0_READ
# group: C08_network_probe

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
    $limit = $null
    if ($Parameter -and $Parameter.PSObject.Properties['limit']) {
        $limit = $Parameter.limit
    }
    $sortBy = if ($Parameter -and $Parameter.PSObject.Properties['sort_by']) { $Parameter.sort_by } else { 'none' }
    
    $connections = @()
    $fallback = $false
    $totalEstimated = 0
    $parseErrorCount = 0

    try {
        # Primary path: Get-NetTCPConnection
        if (-not (Test-Budget $__sw $BudgetMs)) {
            Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget before Get-NetTCPConnection." $true
            return
        }

        $tcpConnections = Get-NetTCPConnection
        $totalEstimated = $tcpConnections.Count

        # Apply Sort before Limit if needed
        if ($sortBy -eq 'local_port') { $tcpConnections = $tcpConnections | Sort-Object LocalPort }
        elseif ($sortBy -eq 'remote_port') { $tcpConnections = $tcpConnections | Sort-Object RemotePort }
        elseif ($sortBy -eq 'state') { $tcpConnections = $tcpConnections | Sort-Object State }

        if ($limit -and $limit -gt 0) {
            $tcpConnections = $tcpConnections | Select-Object -First $limit
        }
        
        foreach ($conn in $tcpConnections) {
            if (-not (Test-Budget $__sw $BudgetMs)) {
                Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget while processing connections." $true @{
                    partial_count = $connections.Count
                    total_estimated_connections = $totalEstimated
                }
                return
            }
            $connections += @{
                local_address = $conn.LocalAddress
                local_port = $conn.LocalPort
                remote_address = $conn.RemoteAddress
                remote_port = $conn.RemotePort
                state = $conn.State
                process_id = $conn.OwningProcess
            }
        }
    } catch {
        # Fallback path: netstat.exe
        $fallback = $true
        $rawOutput = netstat.exe -ano -p TCP
        $lines = $rawOutput | Select-String -Pattern "^\s*TCP"
        $totalEstimated = $lines.Count

        if ($limit -and $limit -gt 0) {
            $limitedLines = $lines | Select-Object -First $limit
        } else {
            $limitedLines = $lines
        }
        
        foreach ($line in $limitedLines) {
            if (-not (Test-Budget $__sw $BudgetMs)) {
                Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget while processing netstat output." $true @{
                    partial_count = $connections.Count
                    total_estimated_connections = $totalEstimated
                    parse_error_count = $parseErrorCount
                }
                return
            }
            $parts = $line.Line.Trim() -split '\s+'
            if ($parts.Count -ge 5) {
                $connections += @{
                    local_address = $parts[1]
                    local_port = ($parts[1] -split ':')[-1]
                    remote_address = $parts[2]
                    remote_port = ($parts[2] -split ':')[-1]
                    state = $parts[3]
                    process_id = [int]$parts[4]
                }
            } else {
                $parseErrorCount++
            }
        }
    }
    
    # 7. Success output
    $truncated = $false
    if ($limit -and $limit -gt 0 -and $totalEstimated -gt $limit) {
        $truncated = $true
    }

    Emit-Success @{ connections = $connections } @{
        fallback_mode = $fallback
        truncated = $truncated
        total_estimated_connections = $totalEstimated
        parse_error_count = $parseErrorCount
    }

} catch {
    # 8. Unified exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
