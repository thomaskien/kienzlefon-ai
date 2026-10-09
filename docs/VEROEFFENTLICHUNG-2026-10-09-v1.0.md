# Veröffentlichung Kienzlefon AI 2.6 — 9. Oktober 2026

Der Benutzer hat den Upload der lokal geprüften Version 2.6 ausdrücklich beauftragt. Diese Auswahl ergänzt den am 30. September veröffentlichten Stand `3a841551c8371a72170d7f3458cb6d85cffa6f6c`. Frühere Programm- und Dokumentversionen bleiben erhalten. Die damaligen Aussagen zur noch ausstehenden Veröffentlichung in den versionierten 2.6-Dokumenten beschreiben den Entwicklungsstand vom 8. Oktober.

## Auswahl und unveränderte Programme

Die folgenden 24 Dateien stammen aus der geprüften 2.6-Integration. Nur die nicht versionierte README wird für das Veröffentlichungsdatum und den Verweis auf diesen Bericht fortgeführt; Programm-, Test- und übrige Dokumentinhalte bleiben bytegleich. Hinzu kommt dieser Bericht als 25. Datei. Im Git-Baum sind nur die zwei Shell-Installer ausführbar; Quellen, Manifeste, Tests und Dokumente werden mit regulären Dateirechten veröffentlicht.

```text
README.md
docs/INSTALLATION-v2.6.md
docs/RELEASE-NOTES-v2.6.md
docs/TESTS-v2.6.md
docs/integration-v2.6/kienzlefon-2.4.0-g722.patch
docs/integration-v2.6/main-generator-check.json
docs/spezifikationen/README.md
docs/spezifikationen/SPEZIFIKATION-KIENZLEFON-AI-INTEGRATION-v2.6.md
docs/spezifikationen/SPEZIFIKATION-KIENZLEFON-AI-SERVERINSTALLER-v2.6.md
installer/README.md
installer/install-kienzlefon-ai_v2.6.sh
installer/kienzlefon-installer-asterisk-backend-v2.6.sh
installer/kokoro-v2.6/LICENSE.kienzlefon-ai
installer/kokoro-v2.6/download_models.py
installer/kokoro-v2.6/embed.py
installer/kokoro-v2.6/install_kokoro.py
installer/kokoro-v2.6/kokoro_service.py
installer/kokoro-v2.6/model_manifest.json
installer/kokoro-v2.6/requirements-cpu.lock.txt
installer/kokoro-v2.6/requirements.lock.txt
installer/kokoro-v2.6/source_manifest.json
installer/kokoro-v2.6/test_installer.py
tests/README.md
tests/test-backend-v2.6.py
```

Installer-Prüfsummen (SHA-256):

```text
44e014869549fcc8d4d09c43f10b6f14637e73a69fb6121ce5773b61c1989b6b  installer/install-kienzlefon-ai_v2.6.sh
c4875a5b8678b69cf6eacc7b064a5557820327ce2b56be5122a7dea5e9e48ab7  installer/kienzlefon-installer-asterisk-backend-v2.6.sh
```

## Prüfung und Ausschlüsse

Die Auswahl wurde gegen die gespeicherten Lieferhashes der Integration abgeglichen. Die vollständigen Installer-Selbsttests sowie 21 Kokoro-, 16 Backend-, 31 Service-/Integrations- und 6 Begrüßungstests wurden bei der Integration bestanden; die Programmbytes werden für diesen Upload unverändert übernommen. Syntax, Version/Hilfe, Quellmanifest, alle 25 ausgewählten Dateien und 85 lokale Dokumentverweise sind zusätzlich am Veröffentlichungskandidaten geprüft. Die Sichtung der Geheimnis-/Audiomerkmale ergab ausschließlich bekannte öffentliche Testwerte und eine als Netzadresse erkannte Paketversionsnummer; keine ungeklärten Treffer. Die Prüfung auf Geheimnismerkmale und Audio umfasst ausschließlich die neue Auswahl; bereits veröffentlichte unveränderte Binärpakete werden dafür nicht erneut geöffnet. Die ursprüngliche Gesamtprüfung des Ausgangsstands bleibt im [Bericht vom 30. September](VEROEFFENTLICHUNGSPRUEFUNG-2026-09-30-v1.0.md) dokumentiert.

Interne Arbeitsanweisungen, PROJECT/STATUS, Workeraufträge und -berichte, lokale Prüfprotokolle, die vollständige Übergabe, Serverkonfigurationen, Tokens und sämtliche Hörproben bleiben ausgeschlossen. Die WAV-Begrüßung wird nicht in einen Installer eingebettet oder hochgeladen. Der Hauptanlagenpatch wird als getrenntes Integrationsartefakt veröffentlicht; auf die Hauptanlage wurde er hier nicht angewendet.

Dies ist die Veröffentlichung des lokal geprüften Entwicklungsstands. Es wurde dadurch weder eine Installation ausgeführt noch eine neue Ubuntu-/GPU-/Modell-/Telefonabnahme bestanden. [Installation und Betrieb](INSTALLATION-v2.6.md), [Prüfungen und Grenzen](TESTS-v2.6.md), [Release Notes](RELEASE-NOTES-v2.6.md).
