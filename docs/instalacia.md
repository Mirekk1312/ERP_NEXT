# Inštalácia ERPNext na NAS

Stack sa spravuje cez **SSH + `docker compose`** skriptom [scripts/nas.ps1](../scripts/nas.ps1).
Na NAS sa ukladá do `NAS_STACK_DIR` (predvolene `/volume1/docker/erpnext`): `compose.yaml` + `.env`.

## Predpoklady

- Synology DSM 7 s balíkom **Container Manager** (obsahuje `docker` aj `docker compose`).
- Aspoň ~4 GB voľnej RAM (stack zaberie cca 2–3 GB) a niekoľko GB miesta na `/volume1`.
- Voľný port `8085` (alebo iný – `HTTP_PORT` v `.env`).
- Na Windows: OpenSSH klient (`ssh`) a kľúč `~\.ssh\id_ed25519`.

## 1. Jednorazové nastavenie NAS

### SSH

1. DSM → **Ovládací panel → Terminál a SNMP** → zaškrtnúť **Povoliť službu SSH**, port 22 → Použiť.
2. DSM → **Ovládací panel → Používateľ a skupina → Rozšírené** → zaškrtnúť **Povoliť službu
   domovských priečinkov používateľov** (bez nej nefunguje prihlásenie kľúčom).
3. Používateľ pre SSH musí byť v skupine **administrators**.

### Prihlásenie kľúčom (z Windows PowerShell)

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh <user>@192.168.1.120 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 755 ~ && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
ssh <user>@192.168.1.120 "echo OK"    # už bez hesla
```

### Prístup k Dockeru bez sudo

Na Synology má k `/var/run/docker.sock` prístup len root. Cez SSH (`ssh <user>@192.168.1.120`):

```sh
sudo synogroup --add docker <user>
sudo chown root:docker /var/run/docker.sock
```

Vlastník socketu sa po reštarte NAS/Container Managera vráti na root, preto v DSM →
**Ovládací panel → Plánovač úloh → Vytvoriť → Spustená úloha → Skript definovaný používateľom**:
používateľ `root`, udalosť **Spustenie**, príkaz:

```sh
sleep 60; chown root:docker /var/run/docker.sock
```

Pozor: členstvo v skupine `docker` znamená v praxi root prístup k NAS – SSH kľúč chrániť.

## 2. Konfigurácia

```powershell
Copy-Item deploy\.env.example .env
```

V `.env` doplň:

- `DB_ROOT_PASSWORD`, `ADMIN_PASSWORD` – len písmená a číslice (aspoň 20 znakov).
  `ADMIN_PASSWORD` je heslo používateľa **Administrator** v ERPNext.
- `NAS_USER` – používateľ zo sekcie 1.

Kontrola spojenia, architektúry, RAM, Dockeru a voľného portu:

```powershell
.\scripts\nas.ps1 info
```

## 3. Nasadenie stacku

```powershell
.\scripts\nas.ps1 deploy
```

Skript nahrá `compose.yaml` a `.env` (len premenné stacku, práva 600) do `NAS_STACK_DIR`,
stiahne imagy (prvýkrát niekoľko minút) a spustí `docker compose up -d`. Potom:

1. `configurator` zapíše spoločnú konfiguráciu a skončí (exit 0).
2. `create-site` vytvorí site `SITE_NAME` a nainštaluje ERPNext – trvá 5–15 minút.

Priebeh:

```powershell
.\scripts\nas.ps1 status
.\scripts\nas.ps1 logs create-site
```

Hotovo je, keď `create-site` je `exited (0)` a ostatné služby sú `running`.

Stack je viditeľný aj v DSM → Container Manager → **Projekt** (ako `erpnext`).

## 4. Overenie

```powershell
Invoke-RestMethod http://192.168.1.120:8085/api/method/ping   # -> message: pong
```

## 5. Úvodné nastavenie (Setup Wizard)

Otvor http://192.168.1.120:8085, prihlás sa ako `Administrator` s heslom `ADMIN_PASSWORD` a vyplň:

- Jazyk: Slovenčina (OVERIŤ: úplnosť slovenského prekladu), krajina: Slovakia, mena: EUR, časové pásmo Europe/Bratislava.
- Firma: AngelTax s.r.o., skratka, fiškálny rok.
- Účtová osnova: OVERIŤ – slovenská účtová osnova nie je v ERPNext štandardne; zatiaľ ponechať
  štandardnú a riešiť samostatne.
