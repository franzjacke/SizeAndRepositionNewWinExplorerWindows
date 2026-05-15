#Requires -Version 5.1
<#
.SYNOPSIS
    Positions each new File Explorer window in a rotating 6-quadrant layout.

.DESCRIPTION
    Detects the usable work area (screen minus taskbar) at runtime via
    SystemParametersInfo SPI_GETWORKAREA, so window positions are always
    correct regardless of taskbar size or docking edge.

    Window size = 1/6 of the work area (3 columns x 2 rows).
    Quadrant order: Left-Top → Left-Bottom → Middle-Top → Middle-Bottom → Right-Top → Right-Bottom → (repeat)

    Polls Shell.Application COM every 500ms for new Explorer windows.
    State (next quadrant index) persists in %APPDATA%\ExplorerQuadrantState.txt.

.PARAMETER Reset
    Reset the quadrant index back to 0 (Left-Top) before starting.
#>
param(
    [switch]$Reset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Win32 API ────────────────────────────────────────────────────────────────
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ExplorerQuadrantWin32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    // Mark this process DPI-aware so MoveWindow coordinates are physical pixels,
    // not DPI-scaled logical pixels (fixes wrong size/position on scaled displays).
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    // SPI_GETWORKAREA (0x30): returns usable screen area excluding taskbars.
    [DllImport("user32.dll")]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref RECT pvParam, uint fWinIni);
}
"@

[ExplorerQuadrantWin32]::SetProcessDPIAware() | Out-Null

# ── Work area (screen minus taskbar, in physical pixels) ──────────────────────
$wa = New-Object ExplorerQuadrantWin32+RECT
[ExplorerQuadrantWin32]::SystemParametersInfo(0x30, 0, [ref]$wa, 0) | Out-Null

$WORK_X = $wa.Left
$WORK_Y = $wa.Top
$WORK_W = $wa.Right  - $wa.Left
$WORK_H = $wa.Bottom - $wa.Top

$WIN_W  = [int]($WORK_W / 3)
$WIN_H  = [int]($WORK_H / 2)

# Quadrant sequence: 3 columns × 2 rows, origin at work-area top-left
$QUADRANTS = @(
    [PSCustomObject]@{ Name = 'Left-Top';      X = $WORK_X;              Y = $WORK_Y           }
    [PSCustomObject]@{ Name = 'Left-Bottom';   X = $WORK_X;              Y = $WORK_Y + $WIN_H  }
    [PSCustomObject]@{ Name = 'Middle-Top';    X = $WORK_X + $WIN_W;     Y = $WORK_Y           }
    [PSCustomObject]@{ Name = 'Middle-Bottom'; X = $WORK_X + $WIN_W;     Y = $WORK_Y + $WIN_H  }
    [PSCustomObject]@{ Name = 'Right-Top';     X = $WORK_X + $WIN_W * 2; Y = $WORK_Y           }
    [PSCustomObject]@{ Name = 'Right-Bottom';  X = $WORK_X + $WIN_W * 2; Y = $WORK_Y + $WIN_H  }
)

# ── State ─────────────────────────────────────────────────────────────────────
$STATE_FILE = Join-Path $env:APPDATA 'ExplorerQuadrantState.txt'

function Get-QuadrantIndex {
    if ((Test-Path $STATE_FILE) -and -not $Reset) {
        $val = (Get-Content $STATE_FILE -Raw).Trim()
        if ($val -match '^\d+$') { return [int]$val % $QUADRANTS.Count }
    }
    return 0
}

function Save-QuadrantIndex([int]$index) {
    $index | Set-Content -Path $STATE_FILE -Encoding UTF8
}

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-ExplorerWindows {
    try {
        $shell = New-Object -ComObject Shell.Application
        return @($shell.Windows() | Where-Object {
            try { $_.HWND -and $_.Name -match 'Explorer|File Explorer' } catch { $false }
        })
    } catch { return @() }
}

function Set-WindowPosition([IntPtr]$hwnd, [PSCustomObject]$q) {
    # SW_SHOWNORMAL = 1  (restore if minimised before moving)
    [ExplorerQuadrantWin32]::ShowWindow($hwnd, 1) | Out-Null
    Start-Sleep -Milliseconds 150
    $ok = [ExplorerQuadrantWin32]::MoveWindow($hwnd, $q.X, $q.Y, $WIN_W, $WIN_H, $true)
    return $ok
}

# ── Main loop ─────────────────────────────────────────────────────────────────
$index = Get-QuadrantIndex
if ($Reset) { Save-QuadrantIndex 0; $index = 0 }

Write-Host "ExplorerQuadrant monitor started"
Write-Host "  Work area   : ${WORK_W} x ${WORK_H} at ($WORK_X, $WORK_Y)  [taskbar excluded]"
Write-Host "  Window size : ${WIN_W} x ${WIN_H}"
Write-Host "  Next slot   : $($QUADRANTS[$index].Name)"
Write-Host "  State file  : $STATE_FILE"
Write-Host "  Press Ctrl+C to stop.`n"

# Seed known handles with windows already open at startup
$knownHandles = @{}
Get-ExplorerWindows | ForEach-Object { $knownHandles[[IntPtr]$_.HWND] = $true }

while ($true) {
    try {
        $currentHandles = @{}

        Get-ExplorerWindows | ForEach-Object {
            $rawHwnd = $_.HWND
            if ($null -eq $rawHwnd) { return }
            $hwnd = [IntPtr][int64]$rawHwnd
            $currentHandles[$hwnd] = $true

            if (-not $knownHandles.ContainsKey($hwnd)) {
                # New Explorer window — give it a moment to finish drawing
                Start-Sleep -Milliseconds 400

                if ([ExplorerQuadrantWin32]::IsWindow($hwnd)) {
                    $q      = $QUADRANTS[$index]
                    $ok     = Set-WindowPosition $hwnd $q
                    $status = if ($ok) { 'OK' } else { 'FAILED' }
                    Write-Host ("[{0}]  HWND={1}  Slot={2}  Pos=({3},{4})  [{5}]" -f
                        (Get-Date -Format 'HH:mm:ss'), $hwnd, $q.Name, $q.X, $q.Y, $status)

                    $index = ($index + 1) % $QUADRANTS.Count
                    Save-QuadrantIndex $index
                }

                $knownHandles[$hwnd] = $true
            }
        }

        # Prune closed windows so recycled HWNDs are treated as new next time
        $knownHandles = $currentHandles
    } catch {
        Write-Host ("[{0}]  WARNING: {1}" -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message)
    }

    Start-Sleep -Milliseconds 500
}
