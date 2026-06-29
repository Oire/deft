# Compile PO files to MO format for use by the application.
#
# Adapted from Sic's Compile-Translations.ps1 (catalog name from dub.json, PATH-
# aware tool discovery). Compiles each locale's <catalog>.po to <catalog>.mo with
# msgfmt; the demo loads locale/<lang>/<catalog>.mo at runtime via the mofile
# package and feeds it to Deft's setTranslator hook.

param(
    [string]$Language = ""
)

. (Join-Path $PSScriptRoot "Get-CatalogName.ps1")

$catalogName = Get-CatalogName
$LocaleRoot = Split-Path $PSScriptRoot -Parent

$msgfmt = Find-GettextTool -Name "msgfmt"
if (!$msgfmt) {
    Write-Error "msgfmt not found. Install gettext tools: winget install GnuWin32.GetText"
    exit 1
}

$languages = @()
if ($Language) {
    $languages = @($Language)
} else {
    $languages = Get-ChildItem -Directory -Path $LocaleRoot |
        Where-Object { $_.Name -match '^[a-z]{2}(-[A-Z]{2})?$' } | ForEach-Object { $_.Name }
}

if ($languages.Count -eq 0) {
    Write-Warning "No language directories found. Use New-Language.ps1 to create a language first."
    exit 0
}

Write-Host "Compiling translations for: $($languages -join ', ')" -ForegroundColor Green

$successCount = 0
$totalCount = 0

foreach ($lang in $languages) {
    $langDir = Join-Path $LocaleRoot $lang
    $poFile = Join-Path $langDir "$catalogName.po"
    $moFile = Join-Path $langDir "$catalogName.mo"

    if (!(Test-Path $poFile)) {
        Write-Warning "PO file not found: $poFile. Skipping $lang."
        continue
    }

    $totalCount++
    try {
        Write-Host "Compiling $lang..." -ForegroundColor Yellow
        & $msgfmt --check --output-file=$moFile $poFile
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Compiled $lang" -ForegroundColor Green
            $successCount++
        } else {
            Write-Warning "msgfmt failed for $lang"
        }
    } catch {
        Write-Error "Failed to compile ${lang}: $_"
    }
}

Write-Host "Compilation completed: $successCount/$totalCount languages" -ForegroundColor Cyan
