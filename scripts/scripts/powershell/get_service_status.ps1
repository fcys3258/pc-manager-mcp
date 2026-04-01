# get_service_status.ps1
# V1.1.0 L1 Skill - Get service status

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

# Strict mode and environment setup
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# Handle InputFile
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

# Unified JSON output functions
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
    # Parse input arguments
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    if (-not $script:SkillArgs) {
        Emit-Error 'INVALID_ARGUMENT' 'Invalid or empty SkillArgs JSON payload.' $false
        return
    }
    $Parameter = $script:SkillArgs.parameter

    # Core logic
    $serviceNames = if ($Parameter.PSObject.Properties['service_names']) { $Parameter.service_names } else { @() }
    if ($serviceNames -isnot [array]) { $serviceNames = @($serviceNames) }
    $limit = if ($Parameter.PSObject.Properties['limit']) { $Parameter.limit } else { 50 }
    $sortBy = if ($Parameter.PSObject.Properties['sort_by']) { $Parameter.sort_by } else { 'name' }
    
    $targetServices = @()
    
    if ($serviceNames.Count -gt 0) {
        foreach ($name in $serviceNames) {
            $s = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($s) { $targetServices += $s }
        }
    } else {
        $targetServices = @(Get-Service)
    }

    # Sort
    $sortedServices = switch ($sortBy) {
        'status' { $targetServices | Sort-Object Status }
        'display_name' { $targetServices | Sort-Object DisplayName }
        default { $targetServices | Sort-Object Name }
    }

    # Limit
    $limitedServices = $sortedServices | Select-Object -First $limit
    
    $resultServices = @()
    foreach ($service in $limitedServices) {
        $resultServices += @{
            name = $service.Name
            display_name = $service.DisplayName
            status = $service.Status.ToString()
            start_type = $service.StartType.ToString()
        }
    }

    Emit-Success @{ 
        services = $resultServices
        total_found = $targetServices.Count
        returned_count = $resultServices.Count
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
