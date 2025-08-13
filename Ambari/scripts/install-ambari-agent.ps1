$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---- Config ----
$Instances = @('bigtop-hostname0','bigtop-hostname1','bigtop-hostname2','bigtop-hostname3')

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

# ---- Install ambari agent ----
foreach ($i in $Instances) {
    Exec "docker compose cp install-ambari-agent-script.sh ${i}:/root/install-ambari-agent-script.sh"
    Exec "docker compose exec -it ${i} /bin/bash /root/install-ambari-agent-script.sh"
}