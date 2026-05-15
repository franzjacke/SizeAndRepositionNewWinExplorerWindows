#Requires -Version 5.1
<#
.SYNOPSIS
    Positions each new File Explorer window in a rotating 6-quadrant layout.

.DESCRIPTION
    Screen: 3440x1440  |  Window: 1/6 screen (1147x720)
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
$ErrorActionPreference = 'Stop'

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
}
"@

[ExplorerQuadrantWin32]::SetProcessDPIAware() | Out-Null

# ── Layout constants ──────────────────────────────────────────────────────────
$SCREEN_W  = 3440
$SCREEN_H  = 1440
$WIN_W     = [int]($SCREEN_W / 3)   # 1146
$WIN_H     = [int]($SCREEN_H / 2)   #  720

# Quadrant sequence: 3 columns × 2 rows
$QUADRANTS = @(
    [PSCustomObject]@{ Name = 'Left-Top';      X = 0;           Y = 0       }
    [PSCustomObject]@{ Name = 'Left-Bottom';   X = 0;           Y = $WIN_H  }
    [PSCustomObject]@{ Name = 'Middle-Top';    X = $WIN_W;      Y = 0       }
    [PSCustomObject]@{ Name = 'Middle-Bottom'; X = $WIN_W;      Y = $WIN_H  }
    [PSCustomObject]@{ Name = 'Right-Top';     X = $WIN_W * 2;  Y = 0       }
    [PSCustomObject]@{ Name = 'Right-Bottom';  X = $WIN_W * 2;  Y = $WIN_H  }
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
            try { $_.Name -match 'Explorer|File Explorer' } catch { $false }
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
Write-Host "  Window size : ${WIN_W} x ${WIN_H}"
Write-Host "  Next slot   : $($QUADRANTS[$index].Name)"
Write-Host "  State file  : $STATE_FILE"
Write-Host "  Press Ctrl+C to stop.`n"

# Seed known handles with windows already open at startup
$knownHandles = @{}
Get-ExplorerWindows | ForEach-Object { $knownHandles[[IntPtr]$_.HWND] = $true }

while ($true) {
    $currentHandles = @{}

    Get-ExplorerWindows | ForEach-Object {
        $hwnd = [IntPtr]$_.HWND
        $currentHandles[$hwnd] = $true

        if (-not $knownHandles.ContainsKey($hwnd)) {
            # New Explorer window — give it a moment to finish drawing
            Start-Sleep -Milliseconds 400

            if ([ExplorerQuadrantWin32]::IsWindow($hwnd)) {
                $q   = $QUADRANTS[$index]
                $ok  = Set-WindowPosition $hwnd $q

                $status = if ($ok) { 'OK' } else { 'FAILED' }
                Write-Host ("[{0}]  HWND={1}  Slot={2}  Pos=({3},{4})  [{5}]" -f
                    (Get-Date -Format 'HH:mm:ss'), $hwnd, $q.Name, $q.X, $q.Y, $status)

                $index = ($index + 1) % $QUADRANTS.Count
                Save-QuadrantIndex $index
            }

            $knownHandles[$hwnd] = $true
        }
    }

    # Prune closed windows so new windows at the same HWND are treated as new
    $knownHandles = $currentHandles

    Start-Sleep -Milliseconds 500
}
