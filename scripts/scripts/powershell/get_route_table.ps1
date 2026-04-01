# get_route_table.ps1
# V1.1.0 L1 Skill - Get system route table
# expected_cost: low
# danger_level: P0_READ
# group: C07_network_config

param(
    [Parameter(Position=0)]
    [string]$InputObject = "",
    [string]$OutputFile = "",
    [string]$InputFile = ""
)

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
    $script:SkillArgs = $InputObject | ConvertFrom-Json

    # 4. Core logic - Get route table
    $routes = @()
    $fallbackMode = $false

    try {
        # Primary path: Get-NetRoute (Windows 8+)
        $netRoutes = Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop | 
            Where-Object { $_.NextHop -ne '0.0.0.0' }
        
        foreach ($route in $netRoutes) {
            $routes += @{
                destination = $route.DestinationPrefix
                gateway = $route.NextHop
                metric = $route.RouteMetric
                interface_index = $route.InterfaceIndex
                interface_alias = $route.InterfaceAlias
                address_family = "IPv4"
                route_type = $route.TypeOfRoute.ToString()
            }
        }
        
        # Also get IPv6 routes (optional)
        $ipv6Routes = Get-NetRoute -AddressFamily IPv6 -ErrorAction SilentlyContinue | 
            Where-Object { $_.NextHop -ne '::' } |
            Select-Object -First 20  # Limit count to avoid large output
        
        foreach ($route in $ipv6Routes) {
            $routes += @{
                destination = $route.DestinationPrefix
                gateway = $route.NextHop
                metric = $route.RouteMetric
                interface_index = $route.InterfaceIndex
                interface_alias = $route.InterfaceAlias
                address_family = "IPv6"
                route_type = $route.TypeOfRoute.ToString()
            }
        }
    } catch {
        # Fallback path: route print (Windows 7 compatible)
        $fallbackMode = $true
        # Handle GBK encoding for Chinese Windows
        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding('gbk')
        } catch {
            # If GBK encoding not available, keep original
        }
        $routeOutput = route print 2>&1
        [Console]::OutputEncoding = $prevEncoding
        
        if ($LASTEXITCODE -eq 0) {
            $inIPv4Section = $false
            
            foreach ($line in $routeOutput) {
                $line = $line.ToString().Trim()
                
                if ($line -match 'IPv4 Route Table') {
                    $inIPv4Section = $true
                    continue
                }
                
                if ($line -match 'IPv6 Route Table') {
                    $inIPv4Section = $false
                    continue
                }
                
                # Parse IPv4 route line (format: Network Destination  Netmask  Gateway  Interface  Metric)
                if ($inIPv4Section -and $line -match '^\d+\.\d+\.\d+\.\d+') {
                    $parts = $line -split '\s+' | Where-Object { $_ }
                    if ($parts.Count -ge 5) {
                        $routes += @{
                            destination = "$($parts[0])/$($parts[1])"
                            gateway = $parts[2]
                            interface_ip = $parts[3]
                            metric = [int]$parts[4]
                            address_family = "IPv4"
                        }
                    }
                }
            }
        }
    }

    # 5. Success output
    $resultData = @{
        routes = $routes
        route_count = $routes.Count
    }
    
    $extraMeta = @{}
    if ($fallbackMode) {
        $extraMeta['fallback_mode'] = $true
        $extraMeta['fallback_reason'] = 'Get-NetRoute not available, using route print'
    }
    
    Emit-Success $resultData $extraMeta

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
