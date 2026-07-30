param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
$RootDirectory = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RootDirectory "dist\cli"
}

$VersionLine = Get-Content (Join-Path $RootDirectory "version.env") |
    Where-Object { $_ -match '^VERSION=' } |
    Select-Object -First 1
$Version = $VersionLine -replace '^VERSION=', ''
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid VERSION '$Version'"
}

Push-Location $RootDirectory
try {
    swift build -c $Configuration --product quotawake
    $BinDirectory = swift build -c $Configuration --show-bin-path
    $ArgumentParserLicense = Join-Path $RootDirectory ".build\checkouts\swift-argument-parser\LICENSE.txt"
    if (-not (Test-Path $ArgumentParserLicense -PathType Leaf)) {
        throw "Missing swift-argument-parser license: $ArgumentParserLicense"
    }
    $Architecture = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x86_64" }
    $ArchiveBase = "quotawake-$Version-windows-$Architecture"
    $StageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("QuotaWake-" + [guid]::NewGuid())
    $StageDirectory = Join-Path $StageRoot $ArchiveBase
    New-Item -ItemType Directory -Path $StageDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    Copy-Item (Join-Path $BinDirectory "quotawake.exe") $StageDirectory
    Copy-Item (Join-Path $RootDirectory "LICENSE") $StageDirectory
    Copy-Item (Join-Path $RootDirectory "README.md") $StageDirectory
    Copy-Item (Join-Path $RootDirectory "Resources\THIRD_PARTY_NOTICES.md") $StageDirectory
    Copy-Item $ArgumentParserLicense (Join-Path $StageDirectory "swift-argument-parser-LICENSE.txt")
    $ArchivePath = Join-Path $OutputDirectory "$ArchiveBase.zip"
    Compress-Archive -Path $StageDirectory -DestinationPath $ArchivePath -Force
    $Hash = (Get-FileHash -Algorithm SHA256 $ArchivePath).Hash.ToLowerInvariant()
    Set-Content -Path "$ArchivePath.sha256" -Value "$Hash  $ArchiveBase.zip"
    Remove-Item -Recurse -Force $StageRoot
    Write-Output "Created $ArchivePath"
}
finally {
    Pop-Location
}
