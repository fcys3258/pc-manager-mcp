# get_top_window.ps1
# V1.1.0 L1 Skill - Get foreground window information

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

    # Core logic - Use .NET Interop to call user32.dll
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    
    public class Win32Window {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        
        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
        
        [DllImport("user32.dll")]
        public static extern int GetWindowTextLength(IntPtr hWnd);
        
        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        
        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);
        
        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);
        
        [DllImport("user32.dll")]
        public static extern bool IsZoomed(IntPtr hWnd);
        
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsHungAppWindow(IntPtr hWnd);
        
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
        
        public static string GetWindowTitle(IntPtr hWnd) {
            int length = GetWindowTextLength(hWnd);
            if (length == 0) return string.Empty;
            
            StringBuilder sb = new StringBuilder(length + 1);
            GetWindowText(hWnd, sb, sb.Capacity);
            return sb.ToString();
        }
    }
"@

    # Get foreground window handle
    $hwnd = [Win32Window]::GetForegroundWindow()
    
    if ($hwnd -eq [IntPtr]::Zero) {
        Emit-Success @{
            has_foreground_window = $false
            message = "No foreground window detected"
        }
        return
    }
    
    # Get window title
    $windowTitle = [Win32Window]::GetWindowTitle($hwnd)
    
    # Get process ID
    $processId = [uint32]0
    [Win32Window]::GetWindowThreadProcessId($hwnd, [ref]$processId) | Out-Null
    
    # Get process information
    $processName = $null
    $processPath = $null
    $processDescription = $null
    try {
        $process = Get-Process -Id $processId -ErrorAction Stop
        $processName = $process.ProcessName
        $processPath = $process.Path
        $processDescription = $process.Description
    } catch { }
    
    # Get window state
    $isVisible = [Win32Window]::IsWindowVisible($hwnd)
    $isMinimized = [Win32Window]::IsIconic($hwnd)
    $isMaximized = [Win32Window]::IsZoomed($hwnd)
    $isHung = [Win32Window]::IsHungAppWindow($hwnd)
    
    # Get window position and size
    $rect = New-Object Win32Window+RECT
    $gotRect = [Win32Window]::GetWindowRect($hwnd, [ref]$rect)
    
    $windowRect = $null
    if ($gotRect) {
        $windowRect = @{
            left = $rect.Left
            top = $rect.Top
            right = $rect.Right
            bottom = $rect.Bottom
            width = $rect.Right - $rect.Left
            height = $rect.Bottom - $rect.Top
        }
    }

    Emit-Success @{
        has_foreground_window = $true
        window_handle = $hwnd.ToInt64()
        window_title = $windowTitle
        process_id = $processId
        process_name = $processName
        process_path = $processPath
        process_description = $processDescription
        is_visible = $isVisible
        is_minimized = $isMinimized
        is_maximized = $isMaximized
        is_hung = $isHung
        window_rect = $windowRect
        status = if ($isHung) { 'not_responding' } else { 'responding' }
    }

} catch {
    $exceptionMessage = $_.Exception.Message
    Emit-Error 'SCRIPT_EXECUTION_FAILED' $exceptionMessage $false @{
        script_path = $MyInvocation.MyCommand.Path
        line_number = $_.InvocationInfo.ScriptLineNumber
    }
}
