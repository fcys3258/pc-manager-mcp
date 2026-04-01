# uninstall_software.ps1
# V1.1.0 L1 Skill - Uninstall software

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 0. UAC elevation with output return support
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $outputFile = Join-Path $env:TEMP "ps_output_$([guid]::NewGuid()).json"
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
        $argList += $outputFile
        
        $process = Start-Process powershell -Verb RunAs -ArgumentList $argList -PassThru -Wait
        
        if ($inputFileTemp -and (Test-Path $inputFileTemp)) {
            Remove-Item $inputFileTemp -Force -ErrorAction SilentlyContinue
        }
        
        $timeout = 100
        $elapsed = 0
        while (-not (Test-Path $outputFile) -and $elapsed -lt $timeout) {
            Start-Sleep -Milliseconds 100
            $elapsed++
        }
        if (Test-Path $outputFile) {
            $output = Get-Content $outputFile -Raw -Encoding UTF8
            Write-Output $output
            Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        } else {
            $errorJson = @{
                ok = $false
                data = $null
                error = @{ code = "ELEVATION_OUTPUT_MISSING"; message = "Admin process did not generate output file"; retriable = $false }
                metadata = @{ exec_time_ms = 0; skill_version = "1.1.0" }
            } | ConvertTo-Json -Compress
            Write-Output $errorJson
        }
        exit $process.ExitCode
    } catch {
        $errorJson = @{
            ok = $false
            data = $null
            error = @{ code = "ELEVATION_FAILED"; message = "Elevation failed: $_"; retriable = $false }
            metadata = @{ exec_time_ms = 0; skill_version = "1.1.0" }
        } | ConvertTo-Json -Compress
        Write-Output $errorJson
        exit 1
    }
}

# 1. Strict mode and environment setup
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# Handle InputFile if provided (elevated process)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# 2. JSON output functions
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
    $Parameter = $script:SkillArgs.parameter
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }

    # 5. Budget check
    if (-not (Test-Budget $__sw $BudgetMs)) {
        Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded $($BudgetMs)ms budget." $true
        return
    }

    # 6. Core logic - Support search by name and silent uninstall
    
    # Helper function to parse command line (handle quotes and spaces correctly)
    function Parse-CommandLine($cmdLine) {
        $cmdLine = $cmdLine.Trim()
        
        # Case 1: Command starts with quote, standard parsing
        if ($cmdLine.StartsWith('"')) {
            $tokens = @()
            $current = ''
            $inQuotes = $false
            
            for ($i = 0; $i -lt $cmdLine.Length; $i++) {
                $char = $cmdLine[$i]
                
                if ($char -eq '"') {
                    $inQuotes = -not $inQuotes
                    continue
                }
                
                if ($char -eq ' ' -and -not $inQuotes) {
                    if ($current) {
                        $tokens += $current
                        $current = ''
                    }
                } else {
                    $current += $char
                }
            }
            
            if ($current) { $tokens += $current }
            return $tokens
        }
        
        # Case 2: No leading quote, try to detect executable path intelligently
        $parts = $cmdLine -split '\s+'
        $exePath = $null
        $argsStartIndex = 0
        
        # Common executable extensions
        $exeExtensions = @('.exe', '.msi', '.cmd', '.bat', '.com')
        
        for ($i = 0; $i -lt $parts.Count; $i++) {
            $candidatePath = ($parts[0..$i]) -join ' '
            
            # Check if path ends with executable extension
            $isValidExe = $false
            foreach ($ext in $exeExtensions) {
                if ($candidatePath.ToLower().EndsWith($ext)) {
                    $isValidExe = $true
                    break
                }
            }
            
            if ($isValidExe) {
                # Prefer existing file
                if (Test-Path $candidatePath -ErrorAction SilentlyContinue) {
                    $exePath = $candidatePath
                    $argsStartIndex = $i + 1
                    break
                }
                # Accept path that looks complete (ends with extension)
                $exePath = $candidatePath
                $argsStartIndex = $i + 1
            }
        }
        
        # Fallback to first token if no valid path found
        if (-not $exePath) {
            $exePath = $parts[0]
            $argsStartIndex = 1
        }
        
        # Build result
        $tokens = @($exePath)
        if ($argsStartIndex -lt $parts.Count) {
            $tokens += $parts[$argsStartIndex..($parts.Count - 1)]
        }
        
        return $tokens
    }
    
    # Helper function to search software in registry
    function Find-SoftwareInRegistry($name) {
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        
        foreach ($regPath in $regPaths) {
            $items = @(Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
                Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like "*$name*" })
            
            foreach ($item in $items) {
                $dispName = if ($item.PSObject.Properties['DisplayName']) { $item.DisplayName } else { $null }
                $quietStr = if ($item.PSObject.Properties['QuietUninstallString']) { $item.QuietUninstallString } else { $null }
                $uninstStr = if ($item.PSObject.Properties['UninstallString']) { $item.UninstallString } else { $null }
                $instLoc = if ($item.PSObject.Properties['InstallLocation']) { $item.InstallLocation } else { $null }
                
                return @{
                    DisplayName = $dispName
                    QuietUninstallString = $quietStr
                    UninstallString = $uninstStr
                    InstallLocation = $instLoc
                }
            }
        }
        return $null
    }
    
    $uninstallString = $null
    $softwareName = $null
    $displayName = $null
    $cmdType = "direct"
    $forceQuiet = if ($Parameter -and $Parameter.PSObject.Properties['force_quiet']) { $Parameter.force_quiet } else { $false }
    
    # Support two modes: provide uninstall_string directly or search by name
    if ($Parameter -and $Parameter.PSObject.Properties['uninstall_string']) {
        $uninstallString = $Parameter.uninstall_string.Trim('" ')
    }
    
    if ($Parameter -and $Parameter.PSObject.Properties['name']) {
        $softwareName = $Parameter.name
    }
    
    # If name provided, search registry
    if ($softwareName -and -not $uninstallString) {
        $found = Find-SoftwareInRegistry $softwareName
        if (-not $found) {
            Emit-Error 'SOFTWARE_NOT_FOUND' "Software not found: $softwareName" $false
            return
        }
        
        $displayName = $found.DisplayName
        
        # Prefer QuietUninstallString
        if ($found.QuietUninstallString) {
            $uninstallString = $found.QuietUninstallString
            $cmdType = "QuietUninstallString"
        } elseif ($found.UninstallString) {
            $uninstallString = $found.UninstallString
            $cmdType = "UninstallString"
        } else {
            Emit-Error 'NO_UNINSTALL_CMD' "No uninstall command found for: $displayName" $false
            return
        }
    }
    
    if (-not $uninstallString) {
        Emit-Error 'INVALID_ARGUMENT' 'Parameter "uninstall_string" or "name" is required.' $false
        return
    }
    
    # Parse command line
    $tokens = @(Parse-CommandLine $uninstallString)
    if ($tokens.Count -eq 0) {
        Emit-Error 'INVALID_UNINSTALL_CMD' "Invalid uninstall command: $uninstallString" $false
        return
    }
    
    $exe = $tokens[0]
    $myArgs = if ($tokens.Count -gt 1) { $tokens[1..($tokens.Count-1)] -join ' ' } else { '' }
    
    # Add MSI silent parameters if needed
    if ($forceQuiet -and $cmdType -eq "UninstallString") {
        if ($uninstallString -like '*msiexec*' -and $uninstallString -notmatch '/quiet|/q\b') {
            $myArgs += ' /quiet /norestart'
        }
    }
    
    # Detect if user interaction is required
    $silentArgs = @('/S', '/s', '/q', '/Q', '/quiet', '/silent', '/verysilent', '/suppressmsbrestarts', '/norestart', '-silent', '-quiet')
    $userInteractionRequired = $true
    foreach ($arg in $myArgs.Split(' ')) {
        if ($silentArgs -contains $arg) {
            $userInteractionRequired = $false
            break
        }
    }
    
    $dryRun = if ($Parameter -and $Parameter.PSObject.Properties['dry_run']) { $Parameter.dry_run } else { $false }
    if ($dryRun) {
        Emit-Success @{ 
            result = 'dry_run'
            software_name = if ($displayName) { $displayName } else { $softwareName }
            would_perform_action = "Start uninstaller: $exe $myArgs"
            command_type = $cmdType
            user_interaction_required = $userInteractionRequired
        }
        return
    }

    try {
        # Start uninstall process
        if ($myArgs) {
            Start-Process -FilePath $exe -ArgumentList $myArgs
        } else {
            Start-Process -FilePath $exe
        }
        
        Emit-Success @{ 
            result = 'uninstaller_started'
            software_name = if ($displayName) { $displayName } else { $softwareName }
            uninstall_command = "$exe $myArgs"
            command_type = $cmdType
            reason = "Uninstaller process started."
        } @{ user_interaction_required = $userInteractionRequired }
    } catch {
        Emit-Error 'ACTION_FAILED' "Failed to start uninstaller. Reason: $($_.Exception.Message)" $false
    }

} catch {
    # 8. Exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
