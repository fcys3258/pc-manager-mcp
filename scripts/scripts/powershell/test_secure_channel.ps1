# test_secure_channel.ps1
# V1.1.0 L1 Skill - Test domain trust relationship

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. Auto-elevate (using InputFile to avoid command line escaping issues)
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
                $err = @{ok=$false;data=$null;error=@{code="ELEVATION_OUTPUT_MISSING";message="Admin process did not generate output file";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
                Write-Output $err
            }
        }
        exit $process.ExitCode
    } catch {
        $err = @{ok=$false;data=$null;error=@{code="ELEVATION_FAILED";message="Elevation failed: $_";retriable=$false};metadata=@{exec_time_ms=0;skill_version="1.1.0"}} | ConvertTo-Json -Compress
        Write-Output $err
        exit 1
    }
}

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
    if ($InputObject) {
        $script:SkillArgs = $InputObject | ConvertFrom-Json
    } else {
        $script:SkillArgs = @{ metadata = @{} }
    }

    # 4. Core logic
    
    # First check if joined to domain
    $csArr = @(Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue)
    $cs = if ($csArr.Count -gt 0) { $csArr[0] } else { $null }
    $partOfDomain = if ($cs -and $cs.PSObject.Properties['PartOfDomain']) { $cs.PartOfDomain } else { $false }
    
    if (-not $partOfDomain) {
        Emit-Success @{
            is_domain_joined = $false
            secure_channel_valid = $null
            message = "Computer is not joined to a domain"
            domain_name = $null
        }
        return
    }
    
    $domainName = $cs.Domain
    $verboseMessages = @()
    $secureChannelValid = $false
    $errorDetails = $null
    
    try {
        # Capture Verbose stream
        $result = Test-ComputerSecureChannel -Verbose 4>&1
        
        foreach ($item in $result) {
            if ($item -is [System.Management.Automation.VerboseRecord]) {
                $verboseMessages += $item.Message
            } elseif ($item -is [bool]) {
                $secureChannelValid = $item
            }
        }
    } catch {
        $secureChannelValid = $false
        $errorDetails = $_.Exception.Message
    }
    
    # Get additional domain info
    $dcInfo = $null
    try {
        # Use nltest to get DC info
        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
        } catch { }
        
        $nltestOutput = nltest /dsgetdc:$domainName 2>&1
        [Console]::OutputEncoding = $prevEncoding
        
        $dcName = $null
        $dcAddress = $null
        foreach ($line in $nltestOutput) {
            $lineStr = $line.ToString()
            if ($lineStr -match 'DC:\s*\\\\(.+)') {
                $dcName = $Matches[1]
            }
            if ($lineStr -match 'Address:\s*\\\\([^\s]+)') {
                $dcAddress = $Matches[1]
            }
        }
        
        if ($dcName) {
            $dcInfo = @{
                dc_name = $dcName
                dc_address = $dcAddress
            }
        }
    } catch { }

    # 5. Success output
    $recommendation = $null
    if (-not $secureChannelValid) {
        $recommendation = "Trust relationship is broken. Consider running: Test-ComputerSecureChannel -Repair or rejoin the domain."
    }
    
    Emit-Success @{
        is_domain_joined = $true
        domain_name = $domainName
        secure_channel_valid = $secureChannelValid
        verbose_messages = $verboseMessages
        error_details = $errorDetails
        dc_info = $dcInfo
        recommendation = $recommendation
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
