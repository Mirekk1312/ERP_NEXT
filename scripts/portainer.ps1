<#
.SYNOPSIS
  Správa ERPNext stacku na NAS cez Portainer API.

.EXAMPLE
  .\scripts\portainer.ps1 info              # verzia Portainera, endpoint, architektúra, RAM
  .\scripts\portainer.ps1 deploy            # vytvorí alebo aktualizuje stack z deploy/compose.yaml
  .\scripts\portainer.ps1 status            # stav kontajnerov stacku
  .\scripts\portainer.ps1 logs create-site  # posledné riadky logu služby
  .\scripts\portainer.ps1 exec backend "bench --site erp.local list-apps"
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('info', 'deploy', 'status', 'logs', 'exec')]
    [string]$Action,
    [Parameter(Position = 1)] [string]$Service,
    [Parameter(Position = 2)] [string]$Command,
    [string]$StackName = 'erpnext',
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
$BaseUrl = $Cfg['PORTAINER_URL'].TrimEnd('/')
$EndpointId = $Cfg['PORTAINER_ENDPOINT_ID']
$Headers = @{ 'X-API-Key' = $Cfg['PORTAINER_TOKEN'] }
$DockerApi = "$BaseUrl/api/endpoints/$EndpointId/docker"

# Premenné, ktoré sa posielajú do stacku (Portainer ich dosadí do compose.yaml).
$StackVarNames = 'ERPNEXT_VERSION', 'SITE_NAME', 'HTTP_PORT', 'DB_ROOT_PASSWORD', 'ADMIN_PASSWORD'

function Invoke-Api([string]$Method, [string]$Url, $Body = $null) {
    $params = @{ Method = $Method; Uri = $Url; Headers = $Headers; TimeoutSec = 600 }
    if ($null -ne $Body) {
        $params.ContentType = 'application/json; charset=utf-8'
        $params.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10))
    }
    Invoke-RestMethod @params
}

function Get-Stack {
    Invoke-Api GET "$BaseUrl/api/stacks" | Where-Object { $_.Name -eq $StackName -and $_.EndpointId -eq [int]$EndpointId }
}

function Get-StackContainers {
    $filters = [uri]::EscapeDataString((@{ label = @("com.docker.compose.project=$StackName") } | ConvertTo-Json -Compress))
    Invoke-Api GET "$DockerApi/containers/json?all=1&filters=$filters"
}

function Get-ServiceContainer([string]$Name) {
    $c = Get-StackContainers | Where-Object { $_.Labels.'com.docker.compose.service' -eq $Name } | Select-Object -First 1
    if (-not $c) { throw "Služba '$Name' v stacku '$StackName' neexistuje." }
    return $c
}

# Docker logy/exec sú multiplexované (8-bajtová hlavička na rámec); vrátime čistý text.
function ConvertFrom-DockerStream([byte[]]$Bytes) {
    $sb = New-Object Text.StringBuilder
    $i = 0
    while ($i + 8 -le $Bytes.Length -and $Bytes[$i] -le 2 -and $Bytes[$i + 1] -eq 0) {
        $len = ([int]$Bytes[$i + 4] -shl 24) -bor ([int]$Bytes[$i + 5] -shl 16) -bor ([int]$Bytes[$i + 6] -shl 8) -bor [int]$Bytes[$i + 7]
        [void]$sb.Append([Text.Encoding]::UTF8.GetString($Bytes, $i + 8, [Math]::Min($len, $Bytes.Length - $i - 8)))
        $i += 8 + $len
    }
    if ($i -eq 0) { return [Text.Encoding]::UTF8.GetString($Bytes) }
    return $sb.ToString()
}

function Invoke-RawBytes([string]$Method, [string]$Url, [string]$JsonBody = $null) {
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.Timeout = 3600000
    $req.ReadWriteTimeout = 3600000
    $req.Headers.Add('X-API-Key', $Headers['X-API-Key'])
    if ($JsonBody) {
        $req.ContentType = 'application/json'
        $b = [Text.Encoding]::UTF8.GetBytes($JsonBody)
        $s = $req.GetRequestStream(); $s.Write($b, 0, $b.Length); $s.Close()
    }
    $resp = $req.GetResponse()
    $ms = New-Object IO.MemoryStream
    $resp.GetResponseStream().CopyTo($ms)
    $resp.Close()
    return , $ms.ToArray()
}

switch ($Action) {
    'info' {
        $status = Invoke-Api GET "$BaseUrl/api/status"
        $info = Invoke-Api GET "$DockerApi/info"
        [pscustomobject]@{
            Portainer    = $status.Version
            Endpoint     = $EndpointId
            Host         = $info.Name
            OS           = $info.OperatingSystem
            Architecture = $info.Architecture
            CPUs         = $info.NCPU
            MemoryGB     = [Math]::Round($info.MemTotal / 1GB, 1)
            Docker       = $info.ServerVersion
            Containers   = "$($info.ContainersRunning) running / $($info.Containers) total"
        } | Format-List
        $port = $Cfg['HTTP_PORT']
        $used = Invoke-Api GET "$DockerApi/containers/json" |
            Where-Object { $_.Ports | Where-Object { "$($_.PublicPort)" -eq $port } }
        if ($used) { Write-Warning "Port $port už používa: $($used.Names -join ', ')" } else { "Port $port je voľný (medzi Docker kontajnermi)." }
    }
    'deploy' {
        $compose = Get-Content (Join-Path $Root 'deploy\compose.yaml') -Raw -Encoding UTF8
        $envList = @(foreach ($n in $StackVarNames) {
                if (-not $Cfg[$n]) { throw "V .env chýba hodnota $n." }
                @{ name = $n; value = $Cfg[$n] }
            })
        $stack = Get-Stack
        if ($stack) {
            "Aktualizujem stack '$StackName' (id $($stack.Id))..."
            $body = @{ stackFileContent = $compose; env = $envList; prune = $true; pullImage = $true }
            $r = Invoke-Api PUT "$BaseUrl/api/stacks/$($stack.Id)?endpointId=$EndpointId" $body
        }
        else {
            "Vytváram stack '$StackName'..."
            $body = @{ name = $StackName; stackFileContent = $compose; env = $envList }
            $r = Invoke-Api POST "$BaseUrl/api/stacks/create/standalone/string?endpointId=$EndpointId" $body
        }
        "Hotovo: stack id $($r.Id), status $($r.Status)."
    }
    'status' {
        Get-StackContainers | ForEach-Object {
            [pscustomobject]@{
                Service = $_.Labels.'com.docker.compose.service'
                State   = $_.State
                Status  = $_.Status
                Image   = $_.Image
            }
        } | Sort-Object Service | Format-Table -AutoSize
    }
    'logs' {
        if (-not $Service) { throw 'Zadaj názov služby, napr. create-site.' }
        $c = Get-ServiceContainer $Service
        $bytes = Invoke-RawBytes GET "$DockerApi/containers/$($c.Id)/logs?stdout=1&stderr=1&tail=$Tail"
        ConvertFrom-DockerStream $bytes
    }
    'exec' {
        if (-not $Service -or -not $Command) { throw 'Použitie: exec <služba> "<príkaz>"' }
        $c = Get-ServiceContainer $Service
        $create = @{ AttachStdout = $true; AttachStderr = $true; Cmd = @('bash', '-c', $Command) }
        $exec = Invoke-Api POST "$DockerApi/containers/$($c.Id)/exec" $create
        $bytes = Invoke-RawBytes POST "$DockerApi/exec/$($exec.Id)/start" '{"Detach":false,"Tty":false}'
        ConvertFrom-DockerStream $bytes
        $result = Invoke-Api GET "$DockerApi/exec/$($exec.Id)/json"
        if ($result.ExitCode -ne 0) { throw "Príkaz skončil s kódom $($result.ExitCode)." }
    }
}
