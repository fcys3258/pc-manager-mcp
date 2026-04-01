# check_root_certificate.ps1
# V1.1.0 L1 Skill - Check root certificates

param(
    [Parameter(Position=0)]
    [string]$InputObject = '{
    "parameter": {
        "common_name": "Microsoft", 
        "store": "Root",
        "location": "LocalMachine"
    },
    "metadata": {
        "timeout_ms": 10000
    }
}',
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
    
    # Parameters: common_name or thumbprint
    $commonName = if ($Parameter -and $Parameter.PSObject.Properties['common_name']) { 
        $Parameter.common_name 
    } else { $null }
    
    $thumbprint = if ($Parameter -and $Parameter.PSObject.Properties['thumbprint']) { 
        $Parameter.thumbprint 
    } else { $null }
    
    # store parameter: Root, CA, My, TrustedPublisher
    $store = if ($Parameter -and $Parameter.PSObject.Properties['store']) { 
        $Parameter.store 
    } else { 'Root' }
    
    # location parameter: LocalMachine, CurrentUser
    $location = if ($Parameter -and $Parameter.PSObject.Properties['location']) { 
        $Parameter.location 
    } else { 'LocalMachine' }

    # 4. Core logic
    $certPath = "Cert:\$location\$store"
    
    $matchedCerts = @()
    $allCerts = @()
    
    try {
        $certs = @(Get-ChildItem -Path $certPath -ErrorAction Stop)
        
        foreach ($cert in $certs) {
            $certInfo = @{
                thumbprint = $cert.Thumbprint
                subject = $cert.Subject
                issuer = $cert.Issuer
                not_before = $cert.NotBefore.ToString('o')
                not_after = $cert.NotAfter.ToString('o')
                is_expired = $cert.NotAfter -lt (Get-Date)
                is_not_yet_valid = $cert.NotBefore -gt (Get-Date)
                friendly_name = $cert.FriendlyName
                serial_number = $cert.SerialNumber
                has_private_key = $cert.HasPrivateKey
            }
            
            # Extract CN
            $cn = $null
            if ($cert.Subject -match 'CN=([^,]+)') {
                $cn = $Matches[1]
            }
            $certInfo['common_name'] = $cn
            
            # Check if matches search criteria
            $isMatch = $false
            if ($commonName -and $cn -and $cn -like "*$commonName*") {
                $isMatch = $true
            }
            if ($thumbprint -and $cert.Thumbprint -eq $thumbprint) {
                $isMatch = $true
            }
            
            if ($isMatch) {
                $matchedCerts += $certInfo
            }
            
            # If no search criteria, collect all certificate summaries
            if (-not $commonName -and -not $thumbprint) {
                $allCerts += @{
                    thumbprint = $cert.Thumbprint
                    common_name = $cn
                    is_expired = $cert.NotAfter -lt (Get-Date)
                    not_after = $cert.NotAfter.ToString('o')
                }
            }
        }
    } catch {
        Emit-Error 'CERT_STORE_ACCESS_FAILED' "Failed to access certificate store: $($_.Exception.Message)" $false
        return
    }

    # 5. Success output
    if ($commonName -or $thumbprint) {
        # Search mode
        Emit-Success @{
            search_mode = $true
            search_criteria = @{
                common_name = $commonName
                thumbprint = $thumbprint
                store = $store
                location = $location
            }
            found = $matchedCerts.Count -gt 0
            match_count = $matchedCerts.Count
            matched_certificates = $matchedCerts
        }
    } else {
        # List mode
        $expiredCerts = @($allCerts | Where-Object { $_.is_expired })
        $limitedCerts = @($allCerts | Select-Object -First 50)
        
        Emit-Success @{
            search_mode = $false
            store = $store
            location = $location
            total_count = $allCerts.Count
            expired_count = $expiredCerts.Count
            certificates = $limitedCerts
            truncated = $allCerts.Count -gt 50
        }
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
