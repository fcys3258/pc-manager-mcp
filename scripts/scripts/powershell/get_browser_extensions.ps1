# get_browser_extensions.ps1
# V1.1.0 L1 Skill - Get browser extensions list (Chrome/Edge)

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# 1. Strict mode and environment setup
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# Handle InputFile if provided
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

function Test-Budget($sw, $budget_ms) {
    if (-not $budget_ms -or $budget_ms -eq 0) { return $true }
    if ($sw.ElapsedMilliseconds -ge $budget_ms) { return $false }
    return $true
}

try {
    # 3. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $Parameter = $script:SkillArgs.parameter
    $BudgetMs = if ($script:SkillArgs.metadata -and $script:SkillArgs.metadata.PSObject.Properties['timeout_ms']) {
        $script:SkillArgs.metadata.timeout_ms
    } else { 0 }
    
    # browser parameter: chrome, edge, all
    $targetBrowser = if ($Parameter -and $Parameter.PSObject.Properties['browser']) { 
        $Parameter.browser 
    } else { 'all' }

    # 4. Core logic
    $extensions = @()
    $localAppData = $env:LOCALAPPDATA
    
    # Browser extension directory configuration
    $browserConfigs = @(
        @{
            name = 'Chrome'
            path = "$localAppData\Google\Chrome\User Data\Default\Extensions"
        },
        @{
            name = 'Edge'
            path = "$localAppData\Microsoft\Edge\User Data\Default\Extensions"
        }
    )
    
    # Filter browsers based on parameter
    if ($targetBrowser -ne 'all') {
        $browserConfigs = @($browserConfigs | Where-Object { $_.name -eq $targetBrowser })
    }
    
    foreach ($browser in $browserConfigs) {
        if (-not (Test-Budget $__sw $BudgetMs)) {
            Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded budget." $true
            return
        }
        
        if (-not (Test-Path $browser.path)) {
            continue
        }
        
        # Enumerate extension directories
        $extDirs = @(Get-ChildItem -Path $browser.path -Directory -ErrorAction SilentlyContinue)
        
        foreach ($extDir in $extDirs) {
            if (-not (Test-Budget $__sw $BudgetMs)) {
                Emit-Error 'TIME_BUDGET_EXCEEDED' "Execution exceeded budget." $true
                return
            }
            
            $extensionId = $extDir.Name
            
            # Find latest version directory
            $versionDirs = @(Get-ChildItem -Path $extDir.FullName -Directory -ErrorAction SilentlyContinue | 
                Sort-Object Name -Descending)
            
            if ($versionDirs.Count -eq 0) {
                continue
            }
            
            $latestVersion = $versionDirs[0]
            $manifestPath = Join-Path $latestVersion.FullName "manifest.json"
            
            if (-not (Test-Path $manifestPath)) {
                continue
            }
            
            try {
                $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # Get extension name
                $extName = $extensionId
                if ($manifest.PSObject.Properties['name'] -and $manifest.name) {
                    $extName = $manifest.name
                }
                
                # Get description (truncate if too long)
                $extDesc = $null
                if ($manifest.PSObject.Properties['description'] -and $manifest.description) {
                    if ($manifest.description.Length -gt 200) {
                        $extDesc = $manifest.description.Substring(0, 200) + '...'
                    } else {
                        $extDesc = $manifest.description
                    }
                }
                
                # Get permissions (limit count)
                $extPerms = @()
                if ($manifest.PSObject.Properties['permissions'] -and $manifest.permissions) {
                    $extPerms = @($manifest.permissions | Select-Object -First 10)
                }
                
                $extensions += @{
                    browser = $browser.name
                    extension_id = $extensionId
                    name = $extName
                    version = if ($manifest.PSObject.Properties['version']) { $manifest.version } else { $null }
                    description = $extDesc
                    manifest_version = if ($manifest.PSObject.Properties['manifest_version']) { $manifest.manifest_version } else { $null }
                    permissions = $extPerms
                    has_content_scripts = $manifest.PSObject.Properties['content_scripts'] -ne $null
                    has_background = $manifest.PSObject.Properties['background'] -ne $null
                }
            } catch {
                # Skip extensions that cannot be parsed
            }
        }
    }

    # 5. Success output
    $chromeCount = @($extensions | Where-Object { $_.browser -eq 'Chrome' }).Count
    $edgeCount = @($extensions | Where-Object { $_.browser -eq 'Edge' }).Count
    
    Emit-Success @{
        extensions = $extensions
        total_count = $extensions.Count
        chrome_count = $chromeCount
        edge_count = $edgeCount
        browsers_scanned = @($browserConfigs | ForEach-Object { $_.name })
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
