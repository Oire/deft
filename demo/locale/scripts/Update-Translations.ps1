# Update existing PO files with new strings from the POT template.
#
# Adapted from Sic's Update-Translations.ps1 (catalog name from dub.json, PATH-
# aware tool discovery). Merges messages.pot into each locale's <catalog>.po with
# msgmerge, keeping existing translations and flagging fuzzy/obsolete entries.

param(
    [string]$Language = "",
    [string]$PotFile = "../messages.pot"
)

. (Join-Path $PSScriptRoot "Get-CatalogName.ps1")

$catalogName = Get-CatalogName
$PotPath = Join-Path $PSScriptRoot $PotFile
$LocaleRoot = Split-Path $PSScriptRoot -Parent

if (!(Test-Path $PotPath)) {
    Write-Error "POT file not found: $PotPath. Run Extract-Strings.ps1 first."
    exit 1
}

$msgmerge = Find-GettextTool -Name "msgmerge"
if (!$msgmerge) {
    Write-Error "msgmerge not found. Install gettext tools: winget install GnuWin32.GetText"
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

Write-Host "Updating translations for: $($languages -join ', ')" -ForegroundColor Green

foreach ($lang in $languages) {
    $langDir = Join-Path $LocaleRoot $lang
    $poFile = Join-Path $langDir "$catalogName.po"

    if (!(Test-Path $poFile)) {
        Write-Warning "PO file not found: $poFile. Skipping $lang."
        continue
    }

    $backupFile = "$poFile.bak"
    try {
        Write-Host "Updating $lang..." -ForegroundColor Yellow
        Copy-Item $poFile $backupFile
        & $msgmerge --update --backup=off $poFile $PotPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Updated $lang" -ForegroundColor Green
            Remove-Item $backupFile -ErrorAction SilentlyContinue
        } else {
            Write-Warning "msgmerge failed for $lang. Restoring backup."
            Move-Item $backupFile $poFile -Force
        }
    } catch {
        Write-Error "Failed to update ${lang}: $_"
        if (Test-Path $backupFile) { Move-Item $backupFile $poFile -Force }
    }
}

Write-Host "Update completed. Next: Compile-Translations.ps1" -ForegroundColor Cyan
