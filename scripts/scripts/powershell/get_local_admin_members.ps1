# get_local_admin_members.ps1
# V1.1.0 L1 Skill - Get local Administrators group members

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

    # 4. Core logic
    $members = @()
    $fallbackMode = $false

    try {
        # Primary path: Get-LocalGroupMember (PS 5.1+)
        $adminMembers = @(Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop)
        
        foreach ($member in $adminMembers) {
            $sidValue = if ($member.PSObject.Properties['SID'] -and $member.SID) { $member.SID.Value } else { $null }
            $principalSource = if ($member.PSObject.Properties['PrincipalSource']) { $member.PrincipalSource.ToString() } else { 'Unknown' }
            $objectClass = if ($member.PSObject.Properties['ObjectClass']) { $member.ObjectClass.ToString() } else { 'Unknown' }
            
            $members += @{
                name = $member.Name
                sid = $sidValue
                principal_source = $principalSource
                object_class = $objectClass
            }
        }
    } catch {
        # Fallback path: net localgroup
        $fallbackMode = $true
        
        # Handle GBK encoding for Chinese Windows
        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
        } catch { }
        
        $netOutput = net localgroup Administrators 2>&1
        [Console]::OutputEncoding = $prevEncoding
        
        $inMemberSection = $false
        foreach ($line in $netOutput) {
            $lineStr = $line.ToString().Trim()
            
            # Skip header line (dashes)
            if ($lineStr -match '^-+$') {
                $inMemberSection = $true
                continue
            }
            
            # End marker
            if ($lineStr -match 'completed successfully') {
                break
            }
            
            if ($inMemberSection -and $lineStr -ne '') {
                # Determine source
                $source = 'Local'
                if ($lineStr -match '\\') {
                    $parts = $lineStr -split '\\'
                    if ($parts[0] -eq $env:COMPUTERNAME) {
                        $source = 'Local'
                    } else {
                        $source = 'Domain'
                    }
                }
                
                $members += @{
                    name = $lineStr
                    principal_source = $source
                }
            }
        }
    }

    # 5. Classification statistics - use @() for strict mode compatibility
    $localMembers = @($members | Where-Object { $_.principal_source -eq 'Local' -or $_.principal_source -eq 'MicrosoftAccount' })
    $domainMembers = @($members | Where-Object { $_.principal_source -eq 'Domain' -or $_.principal_source -eq 'ActiveDirectory' })
    $azureMembers = @($members | Where-Object { $_.principal_source -eq 'AzureAD' })
    
    $localCount = $localMembers.Count
    $domainCount = $domainMembers.Count
    $azureCount = $azureMembers.Count
    
    # 6. Success output
    $extraMeta = @{}
    if ($fallbackMode) {
        $extraMeta['fallback_mode'] = $true
        $extraMeta['fallback_reason'] = 'Get-LocalGroupMember not available, using net localgroup'
    }
    
    Emit-Success @{
        members = $members
        member_count = $members.Count
        local_count = $localCount
        domain_count = $domainCount
        azure_count = $azureCount
        has_non_builtin_admins = $members.Count -gt 1
    } $extraMeta

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
