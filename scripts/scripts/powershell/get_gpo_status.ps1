# get_gpo_status.ps1
# V1.1.0 L1 Skill - Get Group Policy application status

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
    $Parameter = $script:SkillArgs.parameter
    
    # scope parameter: user or computer
    $scope = if ($Parameter -and $Parameter.PSObject.Properties['scope']) { $Parameter.scope } else { 'user' }

    # 4. Core logic
    
    # Handle GBK encoding for Chinese Windows
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
    } catch { }
    
    $gpresultOutput = gpresult /r /scope $scope 2>&1
    [Console]::OutputEncoding = $prevEncoding
    
    $lastApplied = $null
    $appliedFrom = $null
    $appliedGpos = @()
    $deniedGpos = @()
    $securityGroups = @()
    
    $inAppliedSection = $false
    $inDeniedSection = $false
    $inSecuritySection = $false
    
    foreach ($line in $gpresultOutput) {
        $lineStr = $line.ToString().Trim()
        
        # Parse last applied time
        if ($lineStr -match 'Last time Group Policy was applied[:\s]+(.+)') {
            $lastApplied = $Matches[1].Trim()
        }
        
        # Parse source DC
        if ($lineStr -match 'Group Policy was applied from[:\s]+(.+)') {
            $appliedFrom = $Matches[1].Trim()
        }
        
        # Detect Applied GPOs section
        if ($lineStr -match 'Applied Group Policy Objects') {
            $inAppliedSection = $true
            $inDeniedSection = $false
            $inSecuritySection = $false
            continue
        }
        
        # Detect Denied GPOs section
        if ($lineStr -match 'The following GPOs were not applied') {
            $inAppliedSection = $false
            $inDeniedSection = $true
            $inSecuritySection = $false
            continue
        }
        
        # Detect Security Groups section
        if ($lineStr -match 'security groups') {
            $inAppliedSection = $false
            $inDeniedSection = $false
            $inSecuritySection = $true
            continue
        }
        
        # Empty line or new section ends current section
        if ($lineStr -eq '' -or ($lineStr -match '^[A-Z]' -and $lineStr -notmatch 'GPO|Policy|security')) {
            $inAppliedSection = $false
            $inDeniedSection = $false
            $inSecuritySection = $false
        }
        
        # Collect data
        if ($inAppliedSection -and $lineStr -ne '' -and $lineStr -notmatch '^-+$') {
            $appliedGpos += $lineStr
        }
        if ($inDeniedSection -and $lineStr -ne '' -and $lineStr -notmatch '^-+$') {
            $deniedGpos += $lineStr
        }
        if ($inSecuritySection -and $lineStr -ne '' -and $lineStr -notmatch '^-+$') {
            $securityGroups += $lineStr
        }
    }
    
    # Clean collected data
    $appliedGpos = @($appliedGpos | Where-Object { $_ -and $_.Trim() -ne '' })
    $deniedGpos = @($deniedGpos | Where-Object { $_ -and $_.Trim() -ne '' })
    $securityGroups = @($securityGroups | Where-Object { $_ -and $_.Trim() -ne '' })
    
    # 5. Success output
    Emit-Success @{
        scope = $scope
        last_applied = $lastApplied
        applied_from = $appliedFrom
        applied_gpos = $appliedGpos
        applied_gpo_count = $appliedGpos.Count
        denied_gpos = $deniedGpos
        denied_gpo_count = $deniedGpos.Count
        has_denied_gpos = $deniedGpos.Count -gt 0
        security_groups = $securityGroups
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
