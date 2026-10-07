# Inštalácia ERPNext na NAS

## Predpoklady

- Synology NAS s Container Managerom a Portainerom (http://192.168.1.120:9000).
- Aspoň ~4 GB voľnej RAM (stack zaberie cca 2–3 GB) a niekoľko GB miesta na disku.
- Voľný port `8085` (alebo iný – `HTTP_PORT` v `.env`).
- Portainer API token: Portainer → vpravo hore používateľ → **My account** → **Access tokens** → **Add access token**.

## 1. Konfigurácia

```powershell
Copy-Item deploy\.env.example .env
```

V `.env` doplň:

- `DB_ROOT_PASSWORD`, `ADMIN_PASSWORD` – len písmená a číslice (aspoň 20 znakov).
  `ADMIN_PASSWORD` je heslo používateľa **Administrator** v ERPNext.
- `PORTAINER_TOKEN` – token z Portainera.

Kontrola spojenia, architektúry, RAM a voľného portu:

```powershell
.\scripts\portainer.ps1 info
```

## 2. Nasadenie stacku

```powershell
.\scripts\portainer.ps1 deploy
```

Portainer stiahne imagy (prvýkrát niekoľko minút) a spustí stack `erpnext`. Potom:

1. `configurator` zapíše spoločnú konfiguráciu a skončí (exit 0).
2. `create-site` vytvorí site `SITE_NAME` a nainštaluje ERPNext – trvá 5–15 minút.

Priebeh:

```powershell
.\scripts\portainer.ps1 status
.\scripts\portainer.ps1 logs create-site
```

Hotovo je, keď `create-site` je `exited` s kódom 0 a ostatné služby sú `running`.

## 3. Overenie

```powershell
Invoke-RestMethod http://192.168.1.120:8085/api/method/ping   # -> message: pong
```

## 4. Úvodné nastavenie (Setup Wizard)

Otvor http://192.168.1.120:8085, prihlás sa ako `Administrator` s heslom `ADMIN_PASSWORD` a vyplň:

- Jazyk: Slovenčina (OVERIŤ: úplnosť slovenského prekladu), krajina: Slovakia, mena: EUR, časové pásmo Europe/Bratislava.
- Firma: AngelTax s.r.o., skratka, fiškálny rok.
- Účtová osnova: OVERIŤ – slovenská účtová osnova nie je v ERPNext štandardne; zatiaľ ponechať
  štandardnú a riešiť samostatne.
