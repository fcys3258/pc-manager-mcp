# get_firewall_status.ps1
# V1.1.0 L1 Skill - Get firewall status
# expected_cost: low
# danger_level: P0_READ
# group: C07_network_config

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

try {
    # 3. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json

    # 4. Core logic - Get firewall status
    $profiles = @()
    $fallbackMode = $false

    try {
        # Primary path: Get-NetFirewallProfile (Windows 8+)
        $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
        
        foreach ($profile in $fwProfiles) {
            $profiles += @{
                name = $profile.Name
                enabled = [bool]$profile.Enabled
                default_inbound_action = $profile.DefaultInboundAction.ToString()
                default_outbound_action = $profile.DefaultOutboundAction.ToString()
                allow_inbound_rules = $profile.AllowInboundRules.ToString()
                allow_local_firewall_rules = $profile.AllowLocalFirewallRules.ToString()
                log_file_name = $profile.LogFileName
                log_allowed = [bool]$profile.LogAllowed
                log_blocked = [bool]$profile.LogBlocked
            }
        }
    } catch {
        # Fallback path: netsh (Windows 7 compatible)
        $fallbackMode = $true
        $netshOutput = netsh advfirewall show allprofiles 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            # Parse netsh output
            $currentProfile = $null
            $profileData = @{}
            
            foreach ($line in $netshOutput) {
                $line = $line.ToString().Trim()
                
                if ($line -match '^(Domain|Private|Public) Profile Settings:') {
                    if ($currentProfile -and $profileData.Count -gt 0) {
                        $profiles += $profileData
                    }
                    $currentProfile = $matches[1]
                    $profileData = @{ name = $currentProfile }
                }
                elseif ($line -match '^State\s+(\w+)') {
                    $profileData['enabled'] = ($matches[1] -eq 'ON')
                }
                elseif ($line -match '^Firewall Policy\s+(.+)') {
                    $profileData['policy'] = $matches[1]
                }
            }
            
            if ($currentProfile -and $profileData.Count -gt 0) {
                $profiles += $profileData
            }
        }
    }

    # 5. Success output
    $resultData = @{
        firewall_profiles = $profiles
        profile_count = $profiles.Count
    }
    
    $extraMeta = @{}
    if ($fallbackMode) {
        $extraMeta['fallback_mode'] = $true
        $extraMeta['fallback_reason'] = 'Get-NetFirewallProfile not available, using netsh'
    }
    
    Emit-Success $resultData $extraMeta

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
