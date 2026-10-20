# Pokyny pre prácu na tomto projekte

- Kontext: self-hosted ERPNext v16 na Synology NAS 192.168.1.120 pre 4 firmy (ATAX, AD, UMK, ZAU)
  pod skupinou `Skupina AngelTax`. ERPNext slúži len na fakturáciu a prehľady, účtovníctvo
  ostáva v MRP K/S (faktúry sa tam prenášajú exportom). Nasadené ako docker compose projekt
  `erpnext` v `/volume1/docker/erpnext`. Pozri `README.md`.
- Repozitár je **verejný** (github.com/Mirekk1312/ERP_NEXT): heslá, tokeny ani firemné dáta nikdy
  necommitovať. Tajomstvá sú len v koreňovom `.env`, firemné dáta (firmy, cenníky, klienti)
  v `data/` – oba gitignorované. Nové premenné pridať aj do `deploy/.env.example` bez hodnoty.
- NAS sa spravuje cez SSH + `docker compose` skriptom `scripts/nas.ps1`
  (`info`, `deploy`, `status`, `logs <služba>`, `exec <služba> "<príkaz>"`,
  `py <súbor.py> [-Data <súbor.json>]`). Výstup `nas.ps1` nepripájať na `Select-Object -First` –
  ukončí `ssh` a preruší príkaz na NAS (napr. `docker compose up` uprostred).
- Nastavenie ERPNext robia idempotentné skripty v `setup/` (funkcia `run(data)`, spúšťané cez
  `nas.ps1 py`); jednorazové testy/zásahy písať do scratchpadu, nie do repa.
- `deploy/compose.yaml` drží krok s oficiálnym `frappe_docker/pwd.yml`; pri zmene verzie
  porovnať s upstreamom. V shell príkazoch v compose escapovať `$` ako `$$`.
- PowerShell skripty musia bežať vo Windows PowerShell 5.1 a byť uložené v UTF-8 s BOM (diakritika).
- Pred zmenami, ktoré mažú alebo hromadne menia dáta (volumes, `--force`, reinstall site, mazanie
  firiem), najprv urobiť zálohu (`scripts/backup.ps1`) a potvrdiť s používateľom.
- Nevymýšľať funkcie ERPNext pre SK legislatívu (účtovná osnova, DPH, výkazy) – ak nie sú
  overené, označiť `OVERIŤ:`.
- Dokumentácia v slovenčine, Markdown.
