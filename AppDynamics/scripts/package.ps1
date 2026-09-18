$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $labRoot 'artifacts'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$outputArchive = Join-Path $outputDirectory 'capital-lab-source.zip'
Add-Type -AssemblyName System.IO.Compression
$outputStream = [System.IO.File]::Open($outputArchive, [System.IO.FileMode]::Create)
$zipArchive = [System.IO.Compression.ZipArchive]::new($outputStream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $sourceFiles = Get-ChildItem -LiteralPath $labRoot -Recurse -Force -File
    foreach ($sourceFile in $sourceFiles) {
        $relativeName = $sourceFile.FullName.Substring($labRoot.Length + 1).Replace('\', '/')
        if ($relativeName -match '^(artifacts|target|\.m2|\.git)/' -or
            $relativeName -match '(^|/)__pycache__/' -or
            ($relativeName -match '^agents/' -and $relativeName -notmatch '/\.gitkeep$') -or
            ($relativeName -match '^\.env' -and $relativeName -ne '.env.example') -or
            $relativeName -match '\.(log|zip)$') { continue }
        $zipEntry = $zipArchive.CreateEntry($relativeName)
        $entryStream = $zipEntry.Open()
        $sourceStream = [System.IO.File]::OpenRead($sourceFile.FullName)
        try { $sourceStream.CopyTo($entryStream) }
        finally { $sourceStream.Dispose(); $entryStream.Dispose() }
    }
} finally { $zipArchive.Dispose(); $outputStream.Dispose() }
Write-Output "Source-only archive: $outputArchive"
