# Pokyny pre prácu na tomto projekte

- Kontext: self-hosted ERPNext v16 pre AngelTax s.r.o. na Synology NAS 192.168.1.120, nasadený
  ako Portainer stack `erpnext` (endpoint 3). Pozri `README.md`.
- Repozitár je **verejný** (github.com/Mirekk1312/ERP_NEXT): heslá, tokeny ani firemné dáta nikdy
  necommitovať. Tajomstvá sú len v koreňovom `.env` (gitignorovaný); nové premenné pridať aj do
  `deploy/.env.example` bez hodnoty.
- Na NAS sa nepristupuje cez SSH – všetko cez Portainer API skriptom `scripts/portainer.ps1`
  (`info`, `deploy`, `status`, `logs <služba>`, `exec <služba> "<príkaz>"`).
- `deploy/compose.yaml` drží krok s oficiálnym `frappe_docker/pwd.yml`; pri zmene verzie
  porovnať s upstreamom. V shell príkazoch v compose escapovať `$` ako `$$`.
- PowerShell skripty musia bežať vo Windows PowerShell 5.1 a byť uložené v UTF-8 s BOM (diakritika).
- Pred zmenami, ktoré mažú dáta (volumes, `--force`, reinstall site), najprv urobiť zálohu
  (`scripts/backup.ps1`) a potvrdiť s používateľom.
- Nevymýšľať funkcie ERPNext pre SK legislatívu (účtovná osnova, DPH, výkazy) – ak nie sú
  overené, označiť `OVERIŤ:`.
- Dokumentácia v slovenčine, Markdown.
