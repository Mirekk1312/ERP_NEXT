# Prevádzka

## Stav a logy

```powershell
.\scripts\nas.ps1 status
.\scripts\nas.ps1 logs backend -Tail 200
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
4. `.\scripts\nas.ps1 deploy` (stiahne nové imagy a reštartuje stack).
5. Migrácia databázy:

   ```powershell
   .\scripts\nas.ps1 exec backend "bench --site erp.local migrate"
   ```

## Obnova zo zálohy

```powershell
.\scripts\nas.ps1 exec backend "ls sites/erp.local/private/backups"
.\scripts\nas.ps1 exec backend "bench --site erp.local restore sites/erp.local/private/backups/<súbor>-database.sql.gz --with-public-files sites/erp.local/private/backups/<súbor>-files.tar --with-private-files sites/erp.local/private/backups/<súbor>-private-files.tar --db-root-password <DB_ROOT_PASSWORD>"
```

(`<DB_ROOT_PASSWORD>` nahradiť heslom z `.env`.)

## Riešenie problémov

- **`502 Bad Gateway` hneď po `deploy`** – backend sa ešte štartuje; počkať 15–30 s.
  Ak sa v `deploy` zmení `configurator` (compose.yaml), reštartujú sa všetky ERPNext služby –
  krátky výpadok.
- **`permission denied … docker.sock`** (po reštarte NAS) – vlastník socketu sa vrátil na root;
  skontrolovať úlohu v DSM Plánovači úloh ([instalacia.md](instalacia.md#prístup-k-dockeru-bez-sudo))
  alebo ju v Plánovači spustiť ručne.
- **Kontajnery ostali v stave `Created`** – `deploy` bol prerušený (napr. výstup cez
  `Select-Object -First`, ktorý ukončí `ssh`); spustiť `.\scripts\nas.ps1 deploy` znova a nechať dobehnúť.
- **Hlásenie SSH „not using a post-quantum key exchange“** – len upozornenie, `nas.ps1` ho skrýva.

## Doplnkové aplikácie (neskôr)

HRMS (`frappe/hrms`) alebo Frappe CRM (`frappe/crm`) nie sú v oficiálnom image `frappe/erpnext`.
Treba postaviť vlastný image s `apps.json` (pozri frappe_docker `docs/` – custom apps), nahradiť ním
image v `deploy/compose.yaml` a doinštalovať: `bench --site erp.local install-app hrms`.

## Nastavenie firiem

Firmy (IČO, DIČ, IČ DPH, adresy), skupinu firiem, číslovanie faktúr a šablóny DPH 23 %
nastavuje [setup/firmy.py](../setup/firmy.py) z lokálneho súboru `data/firmy.json` (nie je v gite).
Skript sa dá spúšťať opakovane – po úprave údajov v JSON stačí:

```powershell
.\scripts\nas.ps1 py setup\firmy.py -Data data\firmy.json
```

### Číslovanie faktúr

- Každá firma má vlastný rad `VF<ROK><4 číslice>` (faktúry aj dobropisy), od 1. 1. znova od 0001;
  rok sa berie z dátumu vystavenia.
- V ERPNext musí byť názov dokladu jedinečný v celom systéme, preto je interný názov
  `<SKRATKA>-VF20260001` (napr. `ATAX-VF20260001`). Na faktúre sa tlačí pole **Číslo faktúry**
  (`VF20260001`) a **Variabilný symbol** (len číslice, `20260001`) – vypĺňa ich Server Script
  „Sales Invoice – číslo faktúry a VS“ (vyžaduje `server_script_enabled`, nastavuje `configurator`).
- Číslo sa pridelí už pri uložení konceptu. **Koncept faktúry nemazať** – zmazaním vznikne
  v rade medzera; nepotrebnú faktúru radšej odoslať a zrušiť (Cancel), opravou vznikne `VF20260002-1`.

### Skupina firiem

Firmy ATAX, AD, UMK a ZAU sú zaradené pod skupinovú firmu **Skupina AngelTax** (`SKUP`), ktorá
nefakturuje a slúži na súhrnné výkazy: **Consolidated Financial Statement** (filter Firma =
Skupina AngelTax, výkaz Profit and Loss Statement – stĺpec za skupinu aj za každú firmu)
a **Consolidated Trial Balance**. Štandardné predajné prehľady (Sales Register, Sales Analytics)
vedia len jednu firmu naraz – súhrnný prehľad fakturácie za všetky firmy je ešte na doplnenie.

## Služby a cenník

Služby (Item, skupina „Služby“, neskladové) a predajný cenník (ceny bez DPH) nastavuje
[setup/cennik.py](../setup/cennik.py) z JSON v `data/` (nie je v gite):

```powershell
.\scripts\nas.ps1 py setup\cennik.py -Data data\cennik_atax_2026.json
```

- Položka s `"price": null` sa založí bez ceny – cena sa zadá na faktúre.
- Nový cenník (napr. od 2027) = nový JSON s iným `price_list` / `valid_from`; služby sa zdieľajú.
- Stav: „Cenník ATAX 2026“ (35 služieb). Cenníky ďalších firiem a mesačné paušály klientov – na doplnenie.
