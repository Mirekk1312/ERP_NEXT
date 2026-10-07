<#
.SYNOPSIS
  Záloha ERPNext site (databáza + súbory) v backend kontajneri.
  Zálohy ostávajú vo volume "sites": sites/<SITE_NAME>/private/backups/.

.EXAMPLE
  .\scripts\backup.ps1
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent

$site = (Get-Content (Join-Path $Root '.env') -Encoding UTF8 |
    Where-Object { $_ -match '^\s*SITE_NAME\s*=' } |
    ForEach-Object { ($_ -split '=', 2)[1].Trim() }) | Select-Object -First 1
if (-not $site) { $site = 'erp.local' }

& (Join-Path $PSScriptRoot 'portainer.ps1') exec backend "bench --site $site backup --with-files && ls -lh sites/$site/private/backups | tail -n 5"
