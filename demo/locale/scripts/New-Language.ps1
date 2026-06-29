# Create a new language translation from the POT template.
#
# Adapted from Sic's New-Language.ps1: the PO file is named <catalog>.po (catalog
# from dub.json) and placed under locale/<language>/. Uses msginit when available
# (so the correct Plural-Forms header is generated — important for ru/uk), and
# falls back to Sic's copy-and-edit-header approach otherwise.

param(
    [Parameter(Mandatory = $true)]
    [string]$Language,
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

$LocaleDir = Join-Path $LocaleRoot $Language
$PoFile = Join-Path $LocaleDir "$catalogName.po"

Write-Host "Creating new language: $Language" -ForegroundColor Green

try {
    New-Item -ItemType Directory -Path $LocaleDir -Force | Out-Null

    if (Test-Path $PoFile) {
        Write-Warning "PO file already exists: $PoFile. Use Update-Translations.ps1 to merge new strings."
        exit 0
    }

    $msginit = Find-GettextTool -Name "msginit"
    if ($msginit) {
        & $msginit --input=$PotPath --output-file=$PoFile --locale=$Language --no-translator
        if ($LASTEXITCODE -ne 0) { throw "msginit exited with code $LASTEXITCODE" }
    } else {
        # Fallback: copy the template and stamp the language headers by hand.
        Copy-Item $PotPath $PoFile
        $content = Get-Content $PoFile -Raw
        $content = $content -replace '"Language-Team: .*\\n"', "`"Language-Team: $Language\n`""
        $content = $content -replace '"Language: .*\\n"', "`"Language: $Language\n`""
        if ($content -notmatch '"Language:') {
            $content = $content -replace '("Language-Team: .*\\n")', "`$1`"Language: $Language\n`""
        }
        Set-Content $PoFile $content -NoNewline
    }

    Write-Host "Created PO file: $PoFile" -ForegroundColor Yellow
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Edit $PoFile to add translations" -ForegroundColor Gray
    Write-Host "2. Compile-Translations.ps1 -Language $Language" -ForegroundColor Gray
} catch {
    Write-Error "Failed to create language: $_"
    exit 1
}
