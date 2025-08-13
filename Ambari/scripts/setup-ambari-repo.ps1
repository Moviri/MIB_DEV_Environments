$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Exec($cmd, [switch]$CaptureOutput) {
    Write-Host ">> $cmd"
    if ($CaptureOutput) {
        $out = & cmd /c $cmd 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): `n$cmd`n$out" }
        return $out
    } else {
        & cmd /c $cmd
        if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): `n$cmd" }
    }
}

Exec "docker compose cp setup-ambari-repo-script.sh bigtop-hostname0:/root/setup-ambari-repo-script.sh"
Exec "docker compose exec -it bigtop-hostname0 /bin/bash /root/setup-ambari-repo-script.sh"
