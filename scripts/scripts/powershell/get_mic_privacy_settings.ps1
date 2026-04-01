# get_mic_privacy_settings.ps1
# V1.1.0 L1 Skill - Get microphone privacy settings

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
    
    # Check user-level microphone permission
    $userMicPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
    $systemMicPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
    
    $userMicAllowed = $null
    $systemMicAllowed = $null
    $appPermissions = @()
    
    # User-level settings
    try {
        $userMicReg = Get-ItemProperty -Path $userMicPath -ErrorAction Stop
        if ($userMicReg.PSObject.Properties['Value']) {
            $userMicAllowed = $userMicReg.Value -eq 'Allow'
        }
    } catch {
        # Key may not exist
    }
    
    # System-level settings (Group Policy may override)
    try {
        $systemMicReg = Get-ItemProperty -Path $systemMicPath -ErrorAction Stop
        if ($systemMicReg.PSObject.Properties['Value']) {
            $systemMicAllowed = $systemMicReg.Value -eq 'Allow'
        }
    } catch { }
    
    # Scan user-level app permissions
    try {
        $appSubkeys = @(Get-ChildItem -Path $userMicPath -ErrorAction SilentlyContinue)
        foreach ($app in $appSubkeys) {
            $appName = $app.PSChildName
            try {
                $appReg = Get-ItemProperty -Path $app.PSPath -ErrorAction SilentlyContinue
                $allowed = $null
                if ($appReg -and $appReg.PSObject.Properties['Value']) {
                    $allowed = $appReg.Value -eq 'Allow'
                }
                
                # Get last used time if available
                $lastUsed = $null
                if ($appReg -and $appReg.PSObject.Properties['LastUsedTimeStart']) {
                    try {
                        $lastUsed = [DateTime]::FromFileTime($appReg.LastUsedTimeStart).ToString('o')
                    } catch { }
                }
                
                $appPermissions += @{
                    app_id = $appName
                    allowed = $allowed
                    last_used = $lastUsed
                }
            } catch { }
        }
    } catch { }
    
    # Also check camera permission (related)
    $userCameraPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'
    $userCameraAllowed = $null
    try {
        $userCamReg = Get-ItemProperty -Path $userCameraPath -ErrorAction Stop
        if ($userCamReg.PSObject.Properties['Value']) {
            $userCameraAllowed = $userCamReg.Value -eq 'Allow'
        }
    } catch { }

    # 5. Evaluate overall status
    $overallMicAllowed = $true
    $issues = @()
    
    if ($systemMicAllowed -eq $false) {
        $overallMicAllowed = $false
        $issues += "System-level microphone access is disabled (may be controlled by Group Policy)"
    }
    if ($userMicAllowed -eq $false) {
        $overallMicAllowed = $false
        $issues += "User-level microphone access is disabled"
    }
    
    $recommendation = $null
    if (-not $overallMicAllowed) {
        $recommendation = "Open Settings > Privacy > Microphone to enable microphone access"
    }
    
    Emit-Success @{
        microphone = @{
            user_level_allowed = $userMicAllowed
            system_level_allowed = $systemMicAllowed
            overall_allowed = $overallMicAllowed
        }
        camera = @{
            user_level_allowed = $userCameraAllowed
        }
        app_permissions = $appPermissions
        app_count = $appPermissions.Count
        issues = $issues
        recommendation = $recommendation
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
