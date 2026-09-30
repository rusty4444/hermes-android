# Rollback / Recovery Guide

Dit bestand beschrijft hoe je terug kunt naar een werkende toestand als een
wijziging in de Hermes Android app of server iets kapot maakt.

Laatst bijgewerkt: 21 augustus 2026.

---

## Server-side dashboard auth plugin

Locatie:
- `/home/david/.hermes/hermes-agent/plugins/dashboard_auth/api_server_key/`
- Oude user-variant: `/home/david/.hermes/plugins/dashboard_auth/api_server_key/` (verwijderd)

Deze plugin zorgt dat het dashboard op poort 9119 de gateway `API_SERVER_KEY`
accepteert als Bearer-token op de routes die de Android-app gebruikt
(`/api/model/options`, `/api/config`, `/api/skills`, `/api/cron/jobs`,
`/api/memory`).

### Verwijderen (terug naar sessie-cookie auth)

```bash
sudo -u david rm -rf /home/david/.hermes/hermes-agent/plugins/dashboard_auth/api_server_key
```

Daarna dashboard herstarten:

```bash
# Zoek PID van dashboard op poort 9119
ps aux | grep "hermes.*dashboard.*9119" | grep -v grep
# Vervang <PID> door het gevonden nummer
sudo -u david kill <PID>
sleep 3
sudo -u david /home/david/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main dashboard --host 0.0.0.0 --port 9119 --no-open --skip-build > /tmp/hermes-dashboard-9119.log 2>&1 & disown
```

Na verwijderen accepteert het dashboard alleen nog sessie-cookies / password
login op deze routes. De Android app moet dan weer een geldige dashboard
sessie hebben om Settings/Cron/Skills/Memory te gebruiken.

---

## OTA-server poort 8842

De host-firewall heeft een regel gekregen om poort 8842 voor iedereen open te
zetten:

```bash
sudo ufw allow 8842/tcp
```

### On-gedaan maken

```bash
sudo ufw delete allow 8842/tcp
```

Daarna is de OTA-server alleen nog bereikbaar vanaf de lokale netwerken die al
in de firewall stonden. VPN-clients kunnen de APK dan niet meer direct
downloaden.

---

## Android app versies

APK's staan op:
- `/data/hermes-android-release.apk` (huidige release)
- `/data/hermes-android-update/hermes-android-release.apk` (OTA-server)
- `/data/hermes-android-update/version.json`

Historische builds zijn niet automatisch bewaard. Maak voor elke release
handmatig een backup als je terug wilt kunnen.

### Huidige versie resetten

1. Pas `pubspec.yaml` aan naar de gewenste versie.
2. Bouw opnieuw:
   ```bash
   cd /home/david/hermes-android
   flutter build apk --release
   cp build/app/outputs/flutter-apk/app-release.apk /data/hermes-android-release.apk
   cp build/app/outputs/flutter-apk/app-release.apk /data/hermes-android-update/hermes-android-release.apk
   ```
3. Update `/data/hermes-android-update/version.json`.

### Belangrijke versies in deze sessie

- **1.0.25+125**: multi-image upload (`pickMultiImage`) + diagnose-foutmeldingen.
- **1.0.24+124**: alleen diagnose-foutmeldingen.
- **1.0.23+123**: geen cookie/password fallback; OTA poort 8842 open.
- **1.0.22+122**: lege-API-key detectie; `fromMap` backwards compat.
- **1.0.21+121**: betere HTTP-foutmeldingen.
- **1.0.20+120**: dashboard Bearer auth geforceerd; zonder server-plugin brak
  dit de menu's.

Wil je terug naar pre-1.0.20 gedrag, verwijder dan de server-side plugin en
zet de app terug naar een build waarin `DashboardClient` de gateway API key
niet forceert (bijv. 1.0.19+119 of eerder).

---

## Snelle health-checks

Gateway API (poort 7681, accepteert API_SERVER_KEY):

```bash
curl -H "Authorization: Bearer <API_SERVER_KEY>" \
  http://192.168.22.50:7681/v1/models
```

Dashboard (poort 9119, accepteert API_SERVER_KEY dankzij de plugin):

```bash
curl -H "Authorization: Bearer <API_SERVER_KEY>" \
  http://192.168.22.50:9119/api/model/options
```

OTA-server:

```bash
curl -s http://192.168.22.50:8842/version.json
curl -I http://192.168.22.50:8842/hermes-android-release.apk
```

---

## Processen

Dashboard poort 9119:
```bash
ps aux | grep "hermes.*dashboard.*9119" | grep -v grep
```

Dashboard poort 8642 (web UI):
```bash
ps aux | grep "hermes.*dashboard.*8642" | grep -v grep
```

OTA-server poort 8842:
```bash
ps aux | grep "hermes-android-update/server.py" | grep -v grep
```

---

## Belangrijke bestanden

App:
- `/home/david/hermes-android/pubspec.yaml` — versie.
- `/home/david/hermes-android/lib/core/services/connection_manager.dart` —
  `DashboardClient` en gateway chat client.
- `/home/david/hermes-android/lib/core/screens/chat_screen.dart` — chat,
  attachments, image upload.
- `/home/david/hermes-android/CHANGELOG.md` — release notes.
- `/home/david/hermes-android/RECOVERY.md` — dit bestand.

Server:
- `/home/david/.hermes/hermes-agent/plugins/dashboard_auth/api_server_key/` —
  dashboard auth plugin.
- `/data/hermes-android-update/server.py` — OTA server.
- `/data/hermes-android-update/version.json` — OTA metadata.
- `/data/hermes-android-release.apk` — huidige release APK.

Secrets:
- `/data/.secrets/hermes-android-gateway-apikey.txt` — `API_SERVER_KEY`.
- `/mnt/openclaw/.secrets/hatoken.txt` — Home Assistant token.

---

## Terugvalplan (als alles stuk gaat)

1. **Server-plugin verwijderen** en dashboard herstarten (zie boven).
2. **App terugzetten** naar laatst bekende werkende build (handmatig via
   `flutter build apk` of oudere APK als je die hebt opgeslagen).
3. **OTA poort dichten** als dat nodig is (zie boven).
4. **Test met directe curl** naar gateway en dashboard.
5. **Check logs:**
   - Dashboard: `/tmp/hermes-dashboard-9119.log`
   - OTA-server: stdout van `server.py`
