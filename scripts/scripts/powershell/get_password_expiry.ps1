# get_password_expiry.ps1
# V1.1.0 L1 Skill - Get password expiry information

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
    $username = $env:USERNAME
    $userdomain = $env:USERDOMAIN
    $passwordExpires = $null
    $passwordLastSet = $null
    $passwordNeverExpires = $false
    $daysUntilExpiry = $null
    $detectionMethod = $null
    
    # Check if domain user
    $csArr = @(Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue)
    $cs = if ($csArr.Count -gt 0) { $csArr[0] } else { $null }
    $partOfDomain = if ($cs -and $cs.PSObject.Properties['PartOfDomain']) { $cs.PartOfDomain } else { $false }
    $isDomainUser = $partOfDomain -and ($userdomain -ne $env:COMPUTERNAME)
    
    if ($isDomainUser) {
        # Domain user: use net user /domain
        $detectionMethod = 'net_user_domain'
        
        # Handle GBK encoding for Chinese Windows
        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
        } catch { }
        
        $netOutput = net user $username /domain 2>&1
        [Console]::OutputEncoding = $prevEncoding
        
        $success = $true
        foreach ($line in $netOutput) {
            $lineStr = $line.ToString()
            
            # Check for errors
            if ($lineStr -match 'System error') {
                $success = $false
                break
            }
            
            # Parse password expiry
            if ($lineStr -match 'Password expires\s+(.+)') {
                $expiryStr = $Matches[1].Trim()
                if ($expiryStr -match 'Never') {
                    $passwordNeverExpires = $true
                } else {
                    try {
                        $passwordExpires = [DateTime]::Parse($expiryStr).ToString('o')
                        $daysUntilExpiry = ([DateTime]::Parse($expiryStr) - [DateTime]::Now).Days
                    } catch { }
                }
            }
            
            # Parse password last set
            if ($lineStr -match 'Password last set\s+(.+)') {
                $lastSetStr = $Matches[1].Trim()
                try {
                    $passwordLastSet = [DateTime]::Parse($lastSetStr).ToString('o')
                } catch { }
            }
        }
        
        if (-not $success) {
            $detectionMethod = 'detection_failed'
        }
    } else {
        # Local user: use net user (local)
        $detectionMethod = 'net_user_local'
        
        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
        } catch { }
        
        $netOutput = net user $username 2>&1
        [Console]::OutputEncoding = $prevEncoding
        
        foreach ($line in $netOutput) {
            $lineStr = $line.ToString()
            
            if ($lineStr -match 'Password expires\s+(.+)') {
                $expiryStr = $Matches[1].Trim()
                if ($expiryStr -match 'Never') {
                    $passwordNeverExpires = $true
                } else {
                    try {
                        $passwordExpires = [DateTime]::Parse($expiryStr).ToString('o')
                        $daysUntilExpiry = ([DateTime]::Parse($expiryStr) - [DateTime]::Now).Days
                    } catch { }
                }
            }
            
            if ($lineStr -match 'Password last set\s+(.+)') {
                $lastSetStr = $Matches[1].Trim()
                try {
                    $passwordLastSet = [DateTime]::Parse($lastSetStr).ToString('o')
                } catch { }
            }
        }
    }

    # 5. Determine status
    $status = 'ok'
    if ($detectionMethod -eq 'detection_failed') {
        $status = 'detection_failed'
    } elseif ($passwordNeverExpires) {
        $status = 'never_expires'
    } elseif ($null -ne $daysUntilExpiry) {
        if ($daysUntilExpiry -lt 0) {
            $status = 'expired'
        } elseif ($daysUntilExpiry -le 7) {
            $status = 'expiring_soon'
        }
    }
    
    # 6. Success output
    Emit-Success @{
        username = $username
        domain = $userdomain
        is_domain_user = $isDomainUser
        password_expires = $passwordExpires
        password_last_set = $passwordLastSet
        password_never_expires = $passwordNeverExpires
        days_until_expiry = $daysUntilExpiry
        status = $status
        detection_method = $detectionMethod
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
