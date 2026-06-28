# Regenerates app.res from app.rc (manifest + version info) when the Windows SDK
# is available. Invoked by dub as a preGenerate step. app.res is also committed,
# so the build still works on machines without the SDK (this script then no-ops).

$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$rc  = Join-Path $dir 'app.rc'
$res = Join-Path $dir 'app.res'

function Find-Rc {
    # 1) Already on PATH?
    $cmd = Get-Command rc.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # 2) Newest rc.exe under the Windows 10/11 SDK (prefer x64).
    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "${env:ProgramFiles}\Windows Kits\10\bin"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $found = Get-ChildItem $root -Recurse -Filter rc.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*\x64\*' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

# Skip if app.res is already newer than its inputs.
if (Test-Path $res) {
    $resTime = (Get-Item $res).LastWriteTimeUtc
    $inputs  = @($rc, (Join-Path $dir 'app.manifest')) | Where-Object { Test-Path $_ }
    $stale   = $inputs | Where-Object { (Get-Item $_).LastWriteTimeUtc -gt $resTime }
    if (-not $stale) { return }
}

$rcExe = Find-Rc
if (-not $rcExe) {
    if (Test-Path $res) {
        Write-Host 'make-res: rc.exe not found; using committed app.res.'
        return
    }
    Write-Warning 'make-res: rc.exe not found and app.res missing; manifest/version info will be absent.'
    return
}

Write-Host "make-res: compiling app.res with $rcExe"
& $rcExe /nologo /fo $res $rc
$code = $LASTEXITCODE

# rc.exe leaves RC<hex> temp files in the working directory if it fails; clean them up.
Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^RC[0-9A-Fa-f]+$' } |
    Remove-Item -Force -ErrorAction SilentlyContinue

if ($code -ne 0) { Write-Warning "make-res: rc.exe failed with exit code $code" }
