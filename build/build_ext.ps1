$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$sourceDir = Split-Path -Parent $scriptDir
if (-not $sourceDir) { $sourceDir = (Get-Item -Path ".").FullName }
$stagingDir = "$sourceDir\build\out\staging"
$outputZip = "$sourceDir\build\out\UndeadFortitude.zip"
$localExt = "$sourceDir\build\out\UndeadFortitude.ext"
$fguExtensionsDir = Join-Path $env:APPDATA "SmiteWorks\Fantasy Grounds\extensions"
$fgcExtensionsDir = Join-Path $env:APPDATA "Fantasy Grounds\extensions"

# Clean up any existing staging/outputs
if (Test-Path $stagingDir) { Remove-Item -Recurse -Force $stagingDir }
if (Test-Path $outputZip) { Remove-Item -Force $outputZip }
$null = New-Item -ItemType Directory -Path $stagingDir -ErrorAction SilentlyContinue

# Copy extension files preserving structure
Copy-Item "$sourceDir\extension.xml" -Destination "$stagingDir\"
if (Test-Path "$sourceDir\Open Gaming License v1.0a.txt") {
    Copy-Item "$sourceDir\Open Gaming License v1.0a.txt" -Destination "$stagingDir\"
}
if (Test-Path "$sourceDir\readme.txt") {
    Copy-Item "$sourceDir\readme.txt" -Destination "$stagingDir\"
}

if (Test-Path "$sourceDir\campaign") {
    $null = New-Item -ItemType Directory -Path "$stagingDir\campaign" -ErrorAction SilentlyContinue
    Copy-Item "$sourceDir\campaign\*" -Destination "$stagingDir\campaign\"
}

$null = New-Item -ItemType Directory -Path "$stagingDir\graphics\icons" -ErrorAction SilentlyContinue
Copy-Item "$sourceDir\graphics\icons\*" -Destination "$stagingDir\graphics\icons\"

$null = New-Item -ItemType Directory -Path "$stagingDir\scripts" -ErrorAction SilentlyContinue
# Only copy .lua files (do not bundle any binaries)
Copy-Item "$sourceDir\scripts\*.lua" -Destination "$stagingDir\scripts\"

# Compress staging directory contents to zip
Write-Host "Compressing extension files..."
Compress-Archive -Path "$stagingDir\*" -DestinationPath $outputZip -Force

# Copy to build/out/UndeadFortitude.ext
Copy-Item $outputZip $localExt -Force

# Install to FGU extensions directory
if (Test-Path $fguExtensionsDir) {
    Write-Host "Installing UndeadFortitude.ext to FGU ($fguExtensionsDir)..."
    Copy-Item $localExt (Join-Path $fguExtensionsDir "UndeadFortitude.ext") -Force
}

# Install to FGC extensions directory
if (Test-Path $fgcExtensionsDir) {
    Write-Host "Installing UndeadFortitude.ext to FGC ($fgcExtensionsDir)..."
    Copy-Item $localExt (Join-Path $fgcExtensionsDir "UndeadFortitude.ext") -Force
}

# Clean up staging and temporary zip
Remove-Item -Recurse -Force $stagingDir
if (Test-Path $outputZip) { Remove-Item -Force $outputZip }

Write-Host "Build and Install completed successfully!"
