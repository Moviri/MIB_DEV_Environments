# setup-bigtop.ps1
# Requires: PowerShell 5+ (or pwsh), Docker Desktop with "docker compose"
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---- Config ----
$Instances = @('bigtop-hostname0','bigtop-hostname1','bigtop-hostname2','bigtop-hostname3')
$InstancesWithout0 = @('bigtop-hostname1','bigtop-hostname2','bigtop-hostname3')

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

# Run directly inside container without extra shell
function Dcx($instance, $inner) {
    Exec "docker compose exec -T $instance $inner"
}

# ---- Validate containers exist ----
$psAll = Exec "docker compose ps" -CaptureOutput
foreach ($i in $Instances) {
    if (-not ($psAll | Select-String -SimpleMatch $i)) {
        Write-Error "Can't find docker container: $i"
        exit 1
    }
}

# ---- Install packages / enable repos / update ----
foreach ($i in $Instances) {
    Dcx $i 'dnf install -y sudo openssh-server openssh-clients which iproute net-tools less vim-enhanced telnet lsof wget curl'
    Dcx $i 'dnf install -y initscripts wget curl tar unzip git'
    Dcx $i 'dnf install -y dnf-plugins-core'
    Dcx $i 'dnf config-manager --set-enabled powertools'
    try {
        Dcx $i 'dnf update -y'
    } catch {
        Write-Warning "Update failed on $i, continuing"
    }
}

# ---- SSH keys + start sshd ----
foreach ($i in $Instances) {
    # Use bash -c to avoid sh -lc nested quoting issues on Windows
    $cmd = "rm -f /root/.ssh/id_rsa /root/.ssh/id_rsa.pub && ssh-keygen -t rsa -N '' -b 2048 -m PEM -f /root/.ssh/id_rsa"
    Exec "docker compose exec -T $i bash -c `"$cmd`""

    Dcx $i 'systemctl enable sshd'
    Dcx $i 'systemctl start sshd'
}

# ---- SELinux & repo tweak ----
foreach ($i in $Instances) {
    Dcx $i 'setenforce 0 || echo "selinux is disabled"'
    Dcx $i 'sed -i "s/enabled=0/enabled=1/g" /etc/yum.repos.d/Rocky-Devel.repo'
}

# ---- Authorize bigtop-hostname0's pubkey everywhere ----
Exec 'docker compose cp bigtop-hostname0:/root/.ssh/id_rsa.pub bigtop-hostname0.pub'

foreach ($i in $Instances) {
    Exec "docker compose cp bigtop-hostname0.pub ${i}:/root/.ssh/authorized_keys"
    Dcx $i 'chown root:root /root/.ssh/authorized_keys'
    Dcx $i 'chmod 600 /root/.ssh/authorized_keys'
    $sshTestCmd = "ssh -o StrictHostKeyChecking=no $i echo 'Connection successful'"
    Exec "docker compose exec -T bigtop-hostname0 bash -c `"$sshTestCmd`""
}

Remove-Item -Force .\bigtop-hostname0.pub -ErrorAction SilentlyContinue

Write-Host "Done."
