# get_printer_config.ps1
# V1.1.0 L1 Skill - Get printer configuration

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

# Handle InputFile (for subprocess mode)
if ($InputFile -and (Test-Path $InputFile)) {
    $InputObject = Get-Content $InputFile -Raw -Encoding UTF8
}

try {
    # 3. Parameter injection
    $script:SkillArgs = $InputObject | ConvertFrom-Json
    $Parameter = $script:SkillArgs.parameter

    # Get printer name (optional, defaults to default printer)
    $printerName = if ($Parameter -and $Parameter.PSObject.Properties['name']) { $Parameter.name } else { $null }

    # 4. Core logic - Get printer configuration
    if (-not $printerName) {
        # Get default printer
        $defaultPrinterArr = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue | 
            Where-Object { $_.Default })
        $defaultPrinter = if ($defaultPrinterArr.Count -gt 0) { $defaultPrinterArr[0] } else { $null }
        
        if ($defaultPrinter) {
            $printerName = $defaultPrinter.Name
        } else {
            Emit-Error 'NO_DEFAULT_PRINTER' "No default printer found and no printer name specified." $false
            return
        }
    }

    try {
        $config = Get-PrintConfiguration -PrinterName $printerName -ErrorAction Stop
        
        # Safe property access for strict mode compatibility
        $paperSize = if ($config.PSObject.Properties['PaperSize']) { $config.PaperSize.ToString() } else { "Unknown" }
        $colorEnabled = if ($config.PSObject.Properties['Color']) { [bool]$config.Color } else { $false }
        $duplexMode = if ($config.PSObject.Properties['DuplexingMode']) { $config.DuplexingMode.ToString() } else { "Unknown" }
        $collateEnabled = if ($config.PSObject.Properties['Collate']) { [bool]$config.Collate } else { $false }
        $copiesCount = if ($config.PSObject.Properties['Copies']) { $config.Copies } else { 1 }
        
        Emit-Success @{
            printer_name = $printerName
            paper_size = $paperSize
            color = $colorEnabled
            duplex_mode = $duplexMode
            collate = $collateEnabled
            copies = $copiesCount
        }
    } catch {
        Emit-Error 'CONFIG_FAILED' "Failed to get printer configuration: $($_.Exception.Message)" $false
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
