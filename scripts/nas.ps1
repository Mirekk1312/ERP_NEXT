<#
.SYNOPSIS
  Správa ERPNext stacku na NAS cez SSH + docker compose.

.EXAMPLE
  .\scripts\nas.ps1 info              # architektúra, RAM, verzia Dockeru/compose, voľný port
  .\scripts\nas.ps1 deploy            # nahrá compose.yaml + .env na NAS a spustí docker compose up -d
  .\scripts\nas.ps1 status            # stav kontajnerov stacku
  .\scripts\nas.ps1 logs create-site  # posledné riadky logu služby
  .\scripts\nas.ps1 exec backend "bench --site erp.local list-apps"
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('info', 'deploy', 'status', 'logs', 'exec')]
    [string]$Action,
    [Parameter(Position = 1)] [string]$Service,
    [Parameter(Position = 2)] [string]$Command,
    [int]$Tail = 100
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent

function Read-DotEnv([string]$Path) {
    $vars = [ordered]@{}
    if (-not (Test-Path $Path)) { throw "Chýba $Path (skopíruj deploy/.env.example a doplň hodnoty)." }
    foreach ($line in Get-Content $Path -Encoding UTF8) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { $vars[$Matches[1]] = $Matches[2].Trim() }
    }
    return $vars
}

$Cfg = Read-DotEnv (Join-Path $Root '.env')
foreach ($n in 'NAS_HOST', 'NAS_USER', 'NAS_STACK_DIR') {
    if (-not $Cfg[$n]) { throw "V .env chýba hodnota $n." }
}
$Port = if ($Cfg['NAS_SSH_PORT']) { $Cfg['NAS_SSH_PORT'] } else { '22' }
$Docker = if ($Cfg['NAS_DOCKER']) { $Cfg['NAS_DOCKER'] } else { 'docker' }
$Dir = $Cfg['NAS_STACK_DIR']
$ComposeCmd = "$Docker compose -p erpnext"

# Premenné, ktoré idú do .env stacku na NAS (docker compose ich dosadí do compose.yaml).
$StackVarNames = 'ERPNEXT_VERSION', 'SITE_NAME', 'HTTP_PORT', 'DB_ROOT_PASSWORD', 'ADMIN_PASSWORD'

function ConvertTo-B64([string]$Text) {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Text -replace "`r`n", "`n")))
}

# Spustí skript v bash na NAS. Skript ide ako base64 v argumente, aby sa vyhlo problémom
# s úvodzovkami a kódovaním stdin vo Windows PowerShell 5.1.
function Invoke-Nas([string]$Script) {
    $full = "export PATH=`$PATH:/usr/local/bin:/usr/bin; set -e; cd '$Dir' 2>/dev/null || true`n$Script"
    $remote = "echo $(ConvertTo-B64 $full) | base64 -d | bash"
    # docker compose píše priebeh na stderr; vo Windows PowerShell 5.1 by to pri presmerovaní
    # 2>&1 a ErrorActionPreference=Stop ukončilo skript, o chybe rozhoduje len exit kód.
    $ErrorActionPreference = 'Continue'
    & ssh -p $Port -o ConnectTimeout=10 "$($Cfg['NAS_USER'])@$($Cfg['NAS_HOST'])" $remote 2>&1 |
        ForEach-Object { "$_" } |
        Where-Object { $_ -notmatch 'post-quantum key exchange|store now, decrypt later|openssh\.com/pq\.html' }
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw "Príkaz na NAS skončil s kódom $LASTEXITCODE." }
}

switch ($Action) {
    'info' {
        Invoke-Nas @"
echo "Host:     `$(hostname)"
echo "Arch:     `$(uname -m)"
echo "DSM:      `$(grep -E '^productversion' /etc.defaults/VERSION 2>/dev/null | cut -d'"' -f2)"
echo "RAM:      `$(free -m | awk '/^Mem:/ {print `$2 " MB spolu, " `$7 " MB dostupné"}')"
echo "Disk:     `$(df -h /volume1 | awk 'NR==2 {print `$4 " voľné z " `$2}')"
echo "Docker:   `$($Docker version --format '{{.Server.Version}}' 2>&1)"
echo "Compose:  `$($Docker compose version --short 2>&1)"
if netstat -tln 2>/dev/null | grep -q ':$($Cfg['HTTP_PORT']) '; then
  echo "Port $($Cfg['HTTP_PORT']): OBSADENÝ"
else
  echo "Port $($Cfg['HTTP_PORT']): voľný"
fi
"@
    }
    'deploy' {
        $composeYaml = Get-Content (Join-Path $Root 'deploy\compose.yaml') -Raw -Encoding UTF8
        $stackEnv = ($StackVarNames | ForEach-Object {
                if (-not $Cfg[$_]) { throw "V .env chýba hodnota $_." }
                "$_=$($Cfg[$_])"
            }) -join "`n"
        Invoke-Nas @"
mkdir -p '$Dir' && cd '$Dir'
echo $(ConvertTo-B64 $composeYaml) | base64 -d > compose.yaml
umask 077
echo $(ConvertTo-B64 "$stackEnv`n") | base64 -d > .env
chmod 600 .env
$ComposeCmd up -d --pull always --remove-orphans
$ComposeCmd ps -a
"@
    }
    'status' {
        Invoke-Nas "$ComposeCmd ps -a"
    }
    'logs' {
        if (-not $Service) { throw 'Zadaj názov služby, napr. create-site.' }
        Invoke-Nas "$ComposeCmd logs --no-color --tail $Tail $Service"
    }
    'exec' {
        if (-not $Service -or -not $Command) { throw 'Použitie: exec <služba> "<príkaz>"' }
        Invoke-Nas "echo $(ConvertTo-B64 $Command) | base64 -d | $ComposeCmd exec -T $Service bash"
    }
}
