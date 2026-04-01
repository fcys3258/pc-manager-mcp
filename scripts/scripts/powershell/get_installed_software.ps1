# get_installed_software.ps1
# V1.1.0 L1 Skill - Get installed software list from registry

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
    $json = $body | ConvertTo-Json -Depth 8 -Compress
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

    # 6. Core logic
    $limit = if ($Parameter -and $Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 50 }
    $sortBy = if ($Parameter -and $Parameter.PSObject.Properties['sort_by']) { $Parameter.sort_by } else { 'name' }
    $nameFilter = if ($Parameter -and $Parameter.PSObject.Properties['name_filter']) { $Parameter.name_filter } else { $null }

    $regPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    $softwareList = @()
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            $softwareList += @(Get-ItemProperty $path -ErrorAction SilentlyContinue)
        }
    }

    # Filtering and Deduplication
    $filteredSoftware = @($softwareList | Where-Object {
        $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -and 
        (-not $_.PSObject.Properties['SystemComponent'] -or $_.SystemComponent -ne 1) -and
        (-not $_.PSObject.Properties['ReleaseType'] -or -not ($_.ReleaseType -in @('Security Update', 'Update', 'Hotfix'))) -and
        (-not $_.PSObject.Properties['ParentKeyName'] -or $_.ParentKeyName -ne 'OperatingSystem') -and
        $_.DisplayName -notmatch '^(Security Update|Microsoft Visual C\+\+|Microsoft\.NET|KB\d+)' -and
        (-not $nameFilter -or $_.DisplayName -like "*$nameFilter*")
    } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString | Group-Object -Property DisplayName, DisplayVersion, Publisher | ForEach-Object { 
        if ($_.Group -and $_.Group.Count -gt 0) { $_.Group[0] } 
    })

    # Sort
    $sortedSoftware = switch ($sortBy) {
        'install_date' { $filteredSoftware | Sort-Object InstallDate -Descending }
        'publisher' { $filteredSoftware | Sort-Object Publisher }
        default { $filteredSoftware | Sort-Object DisplayName }
    }

    # Limit
    $limitedSoftware = @($sortedSoftware | Select-Object -First $limit)

    $result = @()
    foreach($item in $limitedSoftware) {
        $result += @{
            name = $item.DisplayName
            version = $item.DisplayVersion
            publisher = $item.Publisher
            install_date = $item.InstallDate
            uninstall_string = $item.UninstallString
        }
    }

    # 7. Success output
    Emit-Success @{ 
        installed_software = $result 
        total_found = $filteredSoftware.Count
        returned_count = $result.Count
    }

} catch {
    # 8. Exception handling
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
