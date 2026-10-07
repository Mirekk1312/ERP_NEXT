# Prevádzka

## Stav a logy

```powershell
.\scripts\portainer.ps1 status
.\scripts\portainer.ps1 logs backend -Tail 200
```

## Záloha

```powershell
.\scripts\backup.ps1
```

Vytvorí zálohu databázy a súborov do `sites/<SITE_NAME>/private/backups/` vo volume `erpnext_sites`.
Záloha zostáva na tom istom NAS – OVERIŤ/doplniť: kopírovanie mimo NAS (Hyper Backup, iný disk).

Zálohu sa oplatí spraviť vždy **pred aktualizáciou**.

## Aktualizácia verzie

1. Záloha (`.\scripts\backup.ps1`).
2. Pozrieť nový tag na https://github.com/frappe/erpnext/releases (v rámci v16) a porovnať
   `deploy/compose.yaml` s aktuálnym https://github.com/frappe/frappe_docker/blob/main/pwd.yml.
3. Zmeniť `ERPNEXT_VERSION` v `.env` aj v `deploy/.env.example`.
4. `.\scripts\portainer.ps1 deploy` (stiahne nové imagy a reštartuje stack).
5. Migrácia databázy:

   ```powershell
   .\scripts\portainer.ps1 exec backend "bench --site erp.local migrate"
   ```

## Obnova zo zálohy

```powershell
.\scripts\portainer.ps1 exec backend "ls sites/erp.local/private/backups"
.\scripts\portainer.ps1 exec backend "bench --site erp.local restore sites/erp.local/private/backups/<súbor>-database.sql.gz --with-public-files sites/erp.local/private/backups/<súbor>-files.tar --with-private-files sites/erp.local/private/backups/<súbor>-private-files.tar --db-root-password <DB_ROOT_PASSWORD>"
```

(`<DB_ROOT_PASSWORD>` nahradiť heslom z `.env`.)

## Doplnkové aplikácie (neskôr)

HRMS (`frappe/hrms`) alebo Frappe CRM (`frappe/crm`) nie sú v oficiálnom image `frappe/erpnext`.
Treba postaviť vlastný image s `apps.json` (pozri frappe_docker `docs/` – custom apps), nahradiť ním
image v `deploy/compose.yaml` a doinštalovať: `bench --site erp.local install-app hrms`.
