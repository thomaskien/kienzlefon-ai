# Lokale Prüfung von Kienzlefon AI 2.6

Geprüft wird das neue Installerpaar ausgehend von 2.5.2 und der Kokoro-Übergabe vom 8. Oktober 2026. Die folgenden Prüfungen verwenden temporäre Dateien, synthetische Audiosignale und simulierte Dienste. Sie installieren keine Modelle und sind keine Ubuntu-, GPU- oder Telefonabnahme.

## Reproduzierbare Prüfungen

Aus der Projektwurzel mit Bash 4 oder neuer und Python 3.11 oder neuer:

```sh
bash -n installer/install-kienzlefon-ai_v2.6.sh
bash -n installer/kienzlefon-installer-asterisk-backend-v2.6.sh
bash installer/install-kienzlefon-ai_v2.6.sh --version
bash installer/install-kienzlefon-ai_v2.6.sh --help
bash installer/kienzlefon-installer-asterisk-backend-v2.6.sh --version
bash installer/kienzlefon-installer-asterisk-backend-v2.6.sh --help
PYTHONDONTWRITEBYTECODE=1 bash installer/install-kienzlefon-ai_v2.6.sh --self-test
PYTHONDONTWRITEBYTECODE=1 PYTHONASYNCIODEBUG=1 PYTHONWARNINGS=error bash installer/kienzlefon-installer-asterisk-backend-v2.6.sh --self-test
python3 -B installer/kokoro-v2.6/test_installer.py
python3 -B tests/test-backend-v2.6.py
```

Die Bash-3-Version des macOS-Systems reicht für die Installer nicht aus. Der lokale Prüflauf verwendet `/usr/local/bin/bash`. Die Tests dürfen aus einer beschreibbaren temporären Umgebung laufen; für HTTP-Testfälle muss lokales Loopback erlaubt sein.

## Ergebnis am 8. Oktober 2026

Shellsyntax, Version/Hilfe, beide vollständigen Installer-Selbsttests und Payload-Kompilierung bestanden. Die gesonderten Suiten bestanden mit **21/21 Kokoro-Installertests** und **16/16 Backendregressionen**. Mit lokal erlaubtem Loopback bestanden anschließend **31/31 Service-/Integrationstests** und **6/6 WAV-Tests** aus der Übergabe gegen die neuen Payloads. Der vorherige Sandboxlauf hatte acht Socket-Bind-Fehler; der vollständige Wiederholungslauf ließ keine Tests aus.

Bei den drei übernommenen Rollback-Fixtures wurde ausschließlich im temporären Harness die neue Datei-/Dienstzustandsstruktur ergänzt. Die Erwartung für die Rückkehr zu einer alten Kokoro-Gerätekonfiguration verlangt jetzt korrekt einen Neustart, damit der residente Prozess die wiederhergestellte Datei tatsächlich lädt. Die Übergabeoriginale bleiben unverändert. Die neuen Backendregressionen prüfen außerdem, dass nach fehlgeschlagener Rücksetzung keine Clients mit ungeprüfter Konfiguration neu gestartet werden und dass fremde Dateiinhalte nicht als eigene Publikation behandelt werden.

## Prüfumfang

- Serverinstaller: Shellsyntax, Version/Hilfe, vorhandene Rollen-/Migrations-/Rendererprüfungen und sämtliche eingebetteten Shell-/Python-Payloads. Der Server-Selbsttest enthält zusätzlich die Kokoro-Regressionen und verifiziert die Quellprüfsummen seiner eingebetteten Dateien.
- Kokoro-Installation: 21 Tests für strenge Konfigurationsprüfung, Bestandswerte, explizite Geräte-/Portwahl, CPU-Paketprofil ohne CUDA-Pakete, Dienstgruppen, physische GPU-UUID, wiederholte Veröffentlichung, Fehler vor und nach Dateiaustausch, Rücksetzung und Erhalt späterer Änderungen.
- TTS-Auswahl: neuer Standard, alter Qwen-State, aktive Kokoro-/Qwen-Auswahl vor veraltetem State, geschütztes Lesen über sudo, eindeutige Auswahl bei zwei aktiven Diensten, Geräte-/Porterhaltung und reine CPU-Rolle ohne GPU-Abfrage.
- Backend: kompletter Selbsttest für Agent, Publisher, Dialog-/Chatpfade, Ansagen, Reload/Rollback, Debug-/Performanceverträge und Renderer. Neu sind Kokoro-Konfiguration, Apply-Payload, G.722, WAV und strenge VAD-Validierung.
- Sprachende: 1000-ms-Neustandard, explizite andere ganze Werte und Erhalt vorhandener 500-ms-Konfigurationen. Boolesche Werte, Fließkommazahlen, Strings und Werte außerhalb 100..5000 werden abgelehnt. Die VAD-Tests prüfen künstliche PCM-Frames und zusammenhängende Pausen; sie messen weder natürliche Sprechpausen noch den Höreindruck.
- Hauptanlage: der getrennte Generatorpatch passt auf die lokale Kienzlefon-Version 2.4.0. Drei KI-Endpunkte erlauben G.722; andere Endpunkte bleiben erhalten. [Prüfnachweis](integration-v2.6/main-generator-check.json). Das Hauptprojekt wurde dabei nicht verändert.

Die unveränderten Übergabetests für Service, Agent, Publisher, Umschaltung und WAV dienen zusätzlich dem Vergleich mit den neuen gerenderten Payloads. Tests der dortigen alten Installationshelfer sind Belege für diese Helfer und werden nicht als Test des neuen KI-Installers ausgegeben. Lokale Prüfprotokolle und der abschließende Dateihashnachweis werden unter `lokal/integration-v2.6/` aufbewahrt.

## Prüfgrenzen

Die übergebene Hardwareprüfung betrifft den damaligen Kokoro-Servicepaketstand 1.0.2/API 1.0.0. Der reale G.722-Anruf stammt vom 3. Oktober; der übergebene lesende Serverabgleich vom 8. Oktober. Diese Belege ersetzen keine neue Abnahme des Installerpaars 2.6.

Noch gesondert auf freigegebener Zielhardware zu prüfen sind Paketauflösung und Installation beider Geräteprofile, Systemd-Rechte und Start, CPU-/CUDA-Inferenz und Warmup, Mehr-GPU-Zuordnung, gemeinsamer residenter Betrieb, reales Upgrade, TTS-Wechsel samt Fehler-Rollback, Autostart/Reboot, G.722/AudioSocket und echte Anrufe mit WAV sowie längerer Sprechpause. Es gab für diese lokale Integration keinen SSH-Zugriff, Dienstneustart, Modellbenchmark oder Audio-Upload.

Rücksetzung schützt Dateien und den zuletzt beobachteten Dienstzustand. Ist dieser inzwischen verändert, bricht sie mit einem technischen Hinweis zur manuellen Prüfung ab. Das kann auch bei einem selbsttätigen Prozesszustandswechsel auftreten; eine atomare Sperre gegen parallele administrative `systemctl`-Befehle wird nicht behauptet.
