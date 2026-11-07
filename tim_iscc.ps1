# tim_iscc.ps1 - locate the Inno Setup 6 compiler (ISCC.exe) wherever it lives.
# Prints exactly one line: the full path, or nothing when not found.
# Search order: standard folders -> Uninstall registry -> App Paths ->
# last resort: scan every local drive (accepts only FileVersion 6.x, so an
# Inno Setup 5 compiler is never mistaken for a usable one).

$candidates = @()
try { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe') } catch {}
try { $candidates += (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe') } catch {}
try { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe') } catch {}
foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { Write-Output $c; exit 0 }
}

# Registry: Uninstall entries (machine, WOW64, per-user)
$roots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
try {
    $apps = Get-ItemProperty $roots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Inno Setup version 6*' -and $_.InstallLocation }
    foreach ($a in $apps) {
        $cand = Join-Path $a.InstallLocation 'ISCC.exe'
        if (Test-Path $cand) { Write-Output $cand; exit 0 }
    }
} catch {}

# Registry: App Paths for the Inno IDE (ISCC.exe sits in the same folder)
try {
    $ide = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Compil32.exe' -ErrorAction Stop).'(default)'
    if ($ide) {
        $cand = Join-Path (Split-Path $ide) 'ISCC.exe'
        if (Test-Path $cand) { Write-Output $cand; exit 0 }
    }
} catch {}

# Last resort: scan every filesystem drive for ISCC.exe with FileVersion 6.x
try {
    $driveRoots = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root }
    foreach ($r in $driveRoots) {
        $hit = Get-ChildItem -Path $r -Recurse -Filter 'ISCC.exe' -ErrorAction SilentlyContinue |
            Where-Object { $_.VersionInfo.FileVersion -like '6.*' } |
            Select-Object -First 1
        if ($hit) { Write-Output $hit.FullName; exit 0 }
    }
} catch {}

exit 0
