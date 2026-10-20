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

Kľúč sa vkladá priamo do príkazu – pri posielaní cez rúru (`Get-Content … | ssh`) sa vo Windows
nedá zadať heslo. Heslo sa pri písaní nezobrazuje, píše sa naslepo.

```powershell
$key = (Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub -Raw).Trim()
ssh <user>@192.168.1.120 "mkdir -p ~/.ssh && echo '$key' >> ~/.ssh/authorized_keys && chmod 755 ~ && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && echo HOTOVO"
ssh <user>@192.168.1.120 "echo OK"    # už bez hesla
```

### Prístup k Dockeru bez sudo

Na Synology má k `/var/run/docker.sock` prístup len root. Cez `ssh -t <user>@192.168.1.120`
(pod `sudo` nie je `synogroup` v PATH, preto plná cesta; `--add` len ak skupina ešte neexistuje):

```sh
sudo /usr/syno/sbin/synogroup --add docker <user>       # skupina docker ešte neexistuje
sudo /usr/syno/sbin/synogroup --memberadd docker <user> # skupina docker už existuje
sudo chown root:docker /var/run/docker.sock
ls -l /var/run/docker.sock                               # srw-rw---- root docker
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
2. `create-site` vytvorí site `SITE_NAME` a nainštaluje ERPNext – trvá niekoľko minút
   (na tomto NAS ~4 min).

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

- Jazyk: Slovenčina alebo English (OVERIŤ: úplnosť slovenského prekladu), krajina: Slovakia,
  mena: EUR, časové pásmo Europe/Bratislava.
- Používateľ: vlastný účet (e-mail) – dostane rolu System Manager; `Administrator` nechať ako núdzový účet.
- Firma: ANGEL TAX s.r.o., skratka `ATAX`, fiškálny rok 1. 1. – 31. 12.
- Účtová osnova: „Standard with Numbers“. Slovenská osnova v ERPNext štandardne nie je; keďže
  účtovníctvo ostáva v MRP, netreba ju.
- Voľba demo dát vytvorí navyše firmu „… (Demo)“ s ukážkovými dokladmi – pred ostrou prevádzkou
  ju odstrániť (v ERPNext „Delete Demo Data“).

## 6. Firmy a cenník

Ďalšie firmy, skupinu, polia IČO/DIČ, číslovanie faktúr a DPH nastavia skripty zo `setup/`
(dáta v `data/`, nie sú v gite) – pozri [prevadzka.md](prevadzka.md#nastavenie-firiem).
