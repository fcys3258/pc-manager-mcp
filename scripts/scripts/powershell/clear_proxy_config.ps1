# clear_proxy_config.ps1
# V1.1.0 L1 Skill - Clear System Proxy Configuration

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Handle InputFile (child process mode)
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
    # 3. Parse input parameters
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $Parameter = $script:SkillArgs.parameter

    # dry_run check
    $dryRun = if ($Parameter -and $Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }
    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'
            would_perform_action = "Clear system proxy configuration (HKCU Internet Settings)"
        }
        return
    }

    # 4. Core logic - Clear proxy configuration
    $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

    # Backup current configuration
    $currentSettings = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
    $backup = @{
        ProxyEnable = $currentSettings.ProxyEnable
        ProxyServer = $currentSettings.ProxyServer
        ProxyOverride = $currentSettings.ProxyOverride
        AutoConfigURL = $currentSettings.AutoConfigURL
    }

    # Clear proxy settings
    Set-ItemProperty $regPath -Name ProxyEnable -Value 0 -ErrorAction Stop
    Remove-ItemProperty $regPath -Name ProxyServer -ErrorAction SilentlyContinue
    Remove-ItemProperty $regPath -Name AutoConfigURL -ErrorAction SilentlyContinue

    # Refresh system settings - notify system that proxy settings have changed
    $signature = @"
[DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
"@
    
    try {
        $type = Add-Type -MemberDefinition $signature -Name WinInet -Namespace Proxy -PassThru -ErrorAction SilentlyContinue
        if ($type) {
            # INTERNET_OPTION_SETTINGS_CHANGED = 39
            # INTERNET_OPTION_REFRESH = 37
            [void]$type::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
            [void]$type::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
        }
    } catch {
        # Refresh failure does not affect main functionality
    }

    # 5. Success output
    Emit-Success @{
        action = "clear_proxy"
        previous_settings = $backup
        current_proxy_enabled = $false
        message = "System proxy configuration cleared successfully"
    } @{ reversible = $true }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
