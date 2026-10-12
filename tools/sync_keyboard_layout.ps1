# sync_keyboard_layout.ps1
# Pure PowerShell Win32 layout synchronizer for ITGmania / Simply Love.
# Detects active Windows keyboard layout and generates Save/WindowsKeyboardLayout.lua

param(
    [string]$SaveDir = "",
    [string]$ForceLayout = "",
    [switch]$Quiet
)

$win32 = @"
using System;
using System.Runtime.InteropServices;
public class WinKeyboard {
    [DllImport("user32.dll")]
    public static extern IntPtr GetKeyboardLayout(uint idThread);
    [DllImport("user32.dll")]
    public static extern IntPtr LoadKeyboardLayoutW(string pwszKLID, uint Flags);
    [DllImport("user32.dll")]
    public static extern uint MapVirtualKeyExW(uint uCode, uint uMapType, IntPtr dwhkl);
    [DllImport("user32.dll")]
    public static extern int ToUnicodeEx(uint wVirtKey, uint wScanCode, byte[] lpKeyState, [Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags, IntPtr dwhkl);
    [DllImport("user32.dll")]
    public static extern bool GetKeyboardLayoutNameW([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pwszKLID);
}
"@

if (-not ([System.Management.Automation.PSTypeName]'WinKeyboard').Type) {
    Add-Type -TypeDefinition $win32
}

$scancodes = @{
    'DeviceButton_q' = 0x10; 'DeviceButton_w' = 0x11; 'DeviceButton_e' = 0x12; 'DeviceButton_r' = 0x13;
    'DeviceButton_t' = 0x14; 'DeviceButton_y' = 0x15; 'DeviceButton_u' = 0x16; 'DeviceButton_i' = 0x17;
    'DeviceButton_o' = 0x18; 'DeviceButton_p' = 0x19; 'DeviceButton_[' = 0x1A; 'DeviceButton_]' = 0x1B;
    'DeviceButton_left bracket' = 0x1A; 'DeviceButton_right bracket' = 0x1B;
    'DeviceButton_a' = 0x1E; 'DeviceButton_s' = 0x1F; 'DeviceButton_d' = 0x20; 'DeviceButton_f' = 0x21;
    'DeviceButton_g' = 0x22; 'DeviceButton_h' = 0x23; 'DeviceButton_j' = 0x24; 'DeviceButton_k' = 0x25;
    'DeviceButton_l' = 0x26; 'DeviceButton_colon' = 0x27; 'DeviceButton_;' = 0x27; 'DeviceButton_:' = 0x27;
    'DeviceButton_semicolon' = 0x27; 'DeviceButton_apostrophe' = 0x28; 'DeviceButton_''' = 0x28;
    'DeviceButton_quote' = 0x28; 'DeviceButton_z' = 0x2C; 'DeviceButton_x' = 0x2D; 'DeviceButton_c' = 0x2E;
    'DeviceButton_v' = 0x2F; 'DeviceButton_b' = 0x30; 'DeviceButton_n' = 0x31; 'DeviceButton_m' = 0x32;
    'DeviceButton_comma' = 0x33; 'DeviceButton_,' = 0x33; 'DeviceButton_period' = 0x34; 'DeviceButton_.' = 0x34;
    'DeviceButton_slash' = 0x35; 'DeviceButton_/' = 0x35; 'DeviceButton_minus' = 0x0C; 'DeviceButton_hyphen' = 0x0C;
    'DeviceButton_-' = 0x0C; 'DeviceButton_equals' = 0x0D; 'DeviceButton_equal' = 0x0D; 'DeviceButton_=' = 0x0D;
    'DeviceButton_`' = 0x29; 'DeviceButton_grave' = 0x29; 'DeviceButton_backslash' = 0x2B; 'DeviceButton_\' = 0x2B;
    'DeviceButton_1' = 0x02; 'DeviceButton_2' = 0x03; 'DeviceButton_3' = 0x04; 'DeviceButton_4' = 0x05;
    'DeviceButton_5' = 0x06; 'DeviceButton_6' = 0x07; 'DeviceButton_7' = 0x08; 'DeviceButton_8' = 0x09;
    'DeviceButton_9' = 0x0A; 'DeviceButton_0' = 0x0B;
}

# Determine layout code and handle
$hkl = [WinKeyboard]::GetKeyboardLayout(0)
$klidBuf = New-Object System.Text.StringBuilder 16
[void][WinKeyboard]::GetKeyboardLayoutNameW($klidBuf)
$layoutCode = $klidBuf.ToString()

if ($ForceLayout) {
    if ($ForceLayout -match '^[0-9a-fA-F]{8}$') {
        $layoutCode = $ForceLayout
    } elseif ($ForceLayout -eq 'colemak') {
        $layoutCode = '00060409'
    } elseif ($ForceLayout -eq 'qwerty') {
        $layoutCode = '00000409'
    }
    $hkl = [WinKeyboard]::LoadKeyboardLayoutW($layoutCode, 1)
}

$layoutName = "Windows ($layoutCode)"
try {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\$layoutCode"
    $regText = (Get-ItemProperty -Path $regPath -ErrorAction Stop)."Layout Text"
    if ($regText) { $layoutName = $regText }
} catch {}

if (-not $Quiet) {
    Write-Host "[WINDOWS LAYOUT] Code: $layoutCode | Name: $layoutName"
}

function Get-CharMapping([uint32]$sc, [bool]$shift) {
    $vk = [WinKeyboard]::MapVirtualKeyExW($sc, 1, $hkl)
    if ($vk -eq 0) { return $null }
    $keyState = New-Object byte[] 256
    if ($shift) { $keyState[0x10] = 0x80 }
    $sb = New-Object System.Text.StringBuilder 16
    $ret = [WinKeyboard]::ToUnicodeEx($vk, $sc, $keyState, $sb, 16, 0, $hkl)
    if ($ret -gt 0) { return $sb.ToString() }
    return $null
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("-- WindowsKeyboardLayout.lua")
$lines.Add("-- Automatically exported from active Windows keyboard layout via Win32 API")
$lines.Add("return {")
$lines.Add('    id = "windows_auto",')
$lines.Add("    name = `"Windows ($layoutName)`",")
$lines.Add("    layoutName = `"$layoutName`",")
$lines.Add("    layoutCode = `"$layoutCode`",")
$lines.Add("    map = {")

$sortedKeys = $scancodes.Keys | Sort-Object
foreach ($btn in $sortedKeys) {
    $sc = $scancodes[$btn]
    $c = Get-CharMapping $sc $false
    if ($c) {
        $escBtn = $btn.Replace('\', '\\').Replace('"', '\"')
        $esc = $c.Replace('\', '\\').Replace('"', '\"')
        $lines.Add("        [`"$escBtn`"] = `"$esc`",")
    }
}

$lines.Add("    },")
$lines.Add("    shift_map = {")

foreach ($btn in $sortedKeys) {
    $sc = $scancodes[$btn]
    $c = Get-CharMapping $sc $true
    if ($c) {
        $escBtn = $btn.Replace('\', '\\').Replace('"', '\"')
        $esc = $c.Replace('\', '\\').Replace('"', '\"')
        $lines.Add("        [`"$escBtn`"] = `"$esc`",")
    }
}

$lines.Add("    },")
$lines.Add("}")

$content = ($lines -join "`n") + "`n"

# Resolve target Save directories
$targetDirs = @()
if ($SaveDir) {
    $targetDirs += $SaveDir
} else {
    # Check parent trees for Save folder
    $possibleRoots = @(
        $PSScriptRoot,
        (Join-Path $PSScriptRoot ".."),
        (Join-Path $PSScriptRoot "..\.."),
        (Join-Path $PSScriptRoot "..\..\..")
    )
    foreach ($r in $possibleRoots) {
        $candidate = Join-Path $r "Save"
        if (Test-Path $candidate) {
            $full = (Resolve-Path $candidate).Path
            if ($targetDirs -notcontains $full) { $targetDirs += $full }
        }
    }
    # Also check AppData
    $appDataSave = Join-Path $env:APPDATA "ITGmania\Save"
    if (Test-Path $appDataSave) {
        $fullApp = (Resolve-Path $appDataSave).Path
        if ($targetDirs -notcontains $fullApp) { $targetDirs += $fullApp }
    }
}

foreach ($dir in $targetDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $outPath = Join-Path $dir "WindowsKeyboardLayout.lua"
    [System.IO.File]::WriteAllText($outPath, $content, [System.Text.Encoding]::UTF8)
    
    # Only write default KeyboardLayout.txt if it does not already exist
    $layoutTxt = Join-Path $dir "KeyboardLayout.txt"
    if (-not (Test-Path $layoutTxt)) {
        [System.IO.File]::WriteAllText($layoutTxt, "qwerty`n", [System.Text.Encoding]::UTF8)
    }
    
    if (-not $Quiet) {
        Write-Host "[EXPORTED] -> $outPath"
    }
}
