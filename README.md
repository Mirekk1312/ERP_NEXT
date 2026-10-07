# ERP_NEXT

Interný ERP systém pre **AngelTax s.r.o.** postavený na [ERPNext](https://frappe.io/erpnext)
([GitHub](https://github.com/frappe/erpnext)), prevádzkovaný ako vlastné (self-hosted) riešenie
na firemnom NAS – nie vo Frappe Cloud.

| | |
|---|---|
| Verzia | ERPNext v16 (`frappe/erpnext`, verzia v `.env` → `ERPNEXT_VERSION`) |
| Server | Synology NAS 192.168.1.120, Docker cez Portainer (`:9000`, endpoint 3) |
| Adresa | http://192.168.1.120:8085 (len LAN) |
| Stack | `erpnext` – podľa oficiálneho [frappe_docker](https://github.com/frappe/frappe_docker) |

## Štruktúra

- [deploy/compose.yaml](deploy/compose.yaml) – Docker stack (MariaDB, Redis, ERPNext služby, nginx).
- [deploy/.env.example](deploy/.env.example) – vzor premenných; reálne hodnoty v koreňovom `.env` (nie je v gite).
- [scripts/portainer.ps1](scripts/portainer.ps1) – nasadenie a správa stacku cez Portainer API.
- [scripts/backup.ps1](scripts/backup.ps1) – záloha databázy a súborov.
- [docs/instalacia.md](docs/instalacia.md) – inštalácia krok za krokom.
- [docs/prevadzka.md](docs/prevadzka.md) – aktualizácie, zálohy, obnova, riešenie problémov.

## Rýchly štart

```powershell
Copy-Item deploy\.env.example .env   # doplň heslá a PORTAINER_TOKEN
.\scripts\portainer.ps1 info
.\scripts\portainer.ps1 deploy
.\scripts\portainer.ps1 status
```
