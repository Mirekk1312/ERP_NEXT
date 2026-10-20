# ERP_NEXT

Interný systém na **fakturáciu a prehľady služieb** pre skupinu firiem AngelTax, postavený na
[ERPNext](https://frappe.io/erpnext) ([GitHub](https://github.com/frappe/erpnext)) a prevádzkovaný
ako vlastné (self-hosted) riešenie na firemnom NAS – nie vo Frappe Cloud. Účtovníctvo ostáva
v MRP K/S, faktúry sa tam prenášajú exportom.

| | |
|---|---|
| Verzia | ERPNext v16 (`frappe/erpnext`, verzia v `.env` → `ERPNEXT_VERSION`) |
| Server | Synology NAS 192.168.1.120, Docker (Container Manager), správa cez SSH + `docker compose` |
| Adresa | http://192.168.1.120:8085 (len LAN) |
| Stack | projekt `erpnext` v `/volume1/docker/erpnext` – podľa oficiálneho [frappe_docker](https://github.com/frappe/frappe_docker) |
| Firmy | ANGEL TAX s.r.o. (ATAX), ADVENTURA s.r.o. (AD), Účtovná a mzdová kancelária s.r.o. (UMK), Zauctujeme.shop s.r.o. (ZAU) – pod skupinou `Skupina AngelTax` |

## Štruktúra

- [deploy/compose.yaml](deploy/compose.yaml) – Docker stack (MariaDB, Redis, ERPNext služby, nginx).
- [deploy/.env.example](deploy/.env.example) – vzor premenných; reálne hodnoty v koreňovom `.env` (nie je v gite).
- [scripts/nas.ps1](scripts/nas.ps1) – nasadenie a správa stacku cez SSH (`info`, `deploy`, `status`, `logs`, `exec`, `py`).
- [scripts/backup.ps1](scripts/backup.ps1) – záloha databázy a súborov.
- [setup/firmy.py](setup/firmy.py) – firmy, skupina, IČO/DIČ polia, číslovanie faktúr, DPH.
- [setup/cennik.py](setup/cennik.py) – služby a predajný cenník.
- `data/` – firemné dáta pre `setup/` skripty (údaje firiem, cenníky); **nie je v gite**.
- [docs/instalacia.md](docs/instalacia.md) – inštalácia krok za krokom.
- [docs/prevadzka.md](docs/prevadzka.md) – zálohy, aktualizácie, nastavenie firiem a cenníka, riešenie problémov.

## Rýchly štart

```powershell
Copy-Item deploy\.env.example .env   # doplň heslá a NAS_USER (pozri docs/instalacia.md)
.\scripts\nas.ps1 info
.\scripts\nas.ps1 deploy
.\scripts\nas.ps1 status
.\scripts\nas.ps1 py setup\firmy.py -Data data\firmy.json
.\scripts\nas.ps1 py setup\cennik.py -Data data\cennik_atax_2026.json
```
