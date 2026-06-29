# Extract translatable strings from the D source into a POT template.
#
# Adapted from Sic's Extract-Strings.ps1: instead of the GetText.NET extractor
# (which understands C#), this uses GNU xgettext over the D sources. xgettext has
# no native D mode, but D's string literals and call syntax are close enough to
# C/C++ that `--language=C++` extracts `tr("...")` calls reliably.
#
# Marked strings use Deft's localization seam: tr("..."). Add more keywords below
# if the project grows context/plural helpers (e.g. trc, trn).

param(
    [string]$SourcePath = "",
    [string]$OutputFile = ""
)

. (Join-Path $PSScriptRoot "Get-CatalogName.ps1")

$LocaleRoot = Split-Path $PSScriptRoot -Parent
$ProjectRoot = Join-Path $LocaleRoot ".."

if (!$SourcePath) { $SourcePath = Join-Path $ProjectRoot "source" }
if (!$OutputFile) { $OutputFile = Join-Path $LocaleRoot "messages.pot" }

$xgettext = Find-GettextTool -Name "xgettext"
if (!$xgettext) {
    Write-Error "xgettext not found. Install gettext tools: winget install GnuWin32.GetText"
    exit 1
}

$catalogName = Get-CatalogName

Write-Host "Extracting translatable strings..." -ForegroundColor Green
Write-Host "Source: $SourcePath" -ForegroundColor Gray
Write-Host "Output: $OutputFile" -ForegroundColor Gray

$files = Get-ChildItem -Path $SourcePath -Recurse -Filter *.d | ForEach-Object { $_.FullName }
if ($files.Count -eq 0) {
    Write-Warning "No .d source files found under $SourcePath."
    exit 0
}

try {
    # Conservative option set: works with the older GnuWin32 xgettext too. D has
    # no native xgettext mode, so --language=C++ parses its C-like string/call
    # syntax. --keyword=tr marks Deft's localization seam.
    & $xgettext `
        --language=C++ `
        --from-code=UTF-8 `
        --keyword=tr `
        --add-comments=TRANSLATORS `
        --sort-output `
        --output=$OutputFile `
        $files

    if ($LASTEXITCODE -ne 0) { throw "xgettext exited with code $LASTEXITCODE" }

    Write-Host "String extraction completed. Template: $OutputFile" -ForegroundColor Green
    Write-Host "Next: New-Language.ps1 -Language <code>  (or Update-Translations.ps1)" -ForegroundColor Gray
} catch {
    Write-Error "String extraction failed: $_"
    exit 1
}
