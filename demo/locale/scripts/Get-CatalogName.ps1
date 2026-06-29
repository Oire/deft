# Shared helpers for the localization scripts.
#
# Adapted from the Sic project's Get-CatalogName.ps1: instead of reading an
# AssemblyName from a .csproj, the catalog name comes from the dub package name
# in dub.json (or dub.sdl). The .mo files are named <catalog>.mo, so the demo
# loads `locale/<lang>/<catalog>.mo` at runtime.

function Get-CatalogName {
    param(
        [string]$ProjectPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "..")
    )

    # dub.json (JSON "name" field).
    $dubJson = Join-Path $ProjectPath "dub.json"
    if (Test-Path $dubJson) {
        $name = (Get-Content $dubJson -Raw | ConvertFrom-Json).name
        if ($name) {
            Write-Host "Catalog name from dub.json: $name" -ForegroundColor Gray
            return $name
        }
    }

    # dub.sdl (SDL `name "..."` line).
    $dubSdl = Join-Path $ProjectPath "dub.sdl"
    if (Test-Path $dubSdl) {
        $line = Select-String -Path $dubSdl -Pattern '^\s*name\s+"([^"]+)"' | Select-Object -First 1
        if ($line) {
            $name = $line.Matches[0].Groups[1].Value
            Write-Host "Catalog name from dub.sdl: $name" -ForegroundColor Gray
            return $name
        }
    }

    throw "Unable to determine catalog name. Run from a project directory with a dub.json/dub.sdl that declares a package name."
}

# Locate a GNU gettext tool (xgettext/msgfmt/msgmerge/msginit): PATH first, then
# the common GnuWin32 install locations. Returns the full path or $null.
function Find-GettextTool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $cmd = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($p in @(
            "C:\Program Files (x86)\GnuWin32\bin\$Name.exe",
            "C:\Program Files\GnuWin32\bin\$Name.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}
