# run-all.ps1
# PowerShell 7+ recommended

# Stop on first error (like `set -e`)
$ErrorActionPreference = 'Stop'

# Resolve ./scripts relative to this file
$scriptsDir = if ($PSScriptRoot) {
    Join-Path $PSScriptRoot 'scripts'
} else {
    Join-Path (Get-Location) 'scripts'
}

# Original .ps1 list, converted to .ps1 names
$scriptNames = @'
setup-ambari-repo.ps1
setup.ps1
install-ambari-server.ps1
install-ambari-agent.ps1
'@ -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

# Change into ./scripts for the duration of the loop
Push-Location $scriptsDir
try {
    foreach ($shName in $scriptNames) {
        $ps1Name = [System.IO.Path]::ChangeExtension($shName, '.ps1')
        $scriptPath = Join-Path $scriptsDir $ps1Name

        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Script not found: $scriptPath"
        }

        Write-Host ""
        Write-Host "===================================================================================="
        Write-Host "============================ $ps1Name"
        Write-Host "===================================================================================="

        # Run with ./scripts as CWD
        & $scriptPath
    }
}
finally {
    Pop-Location
}
