# Veröffentlichung vorbereiten: CUDA-/Backendlinie bis 2.5.2 und AMD 1.0.2

[Zur README](../README.md) · Stand: 30. September 2026

Diese Fortführung ersetzt die bisherige Veröffentlichungsauswahl 1.8. Der private Meldeweg für Sicherheitsprobleme ist auf Benutzerauftrag festgelegt: **[tk@mampf.net](mailto:tk@mampf.net)**. Die ausgewählten Dateien sind in einem getrennten Checkout des bestehenden öffentlichen GitHub-Repositories zusammengestellt und geprüft; [Prüfbericht und Umfang](VEROEFFENTLICHUNGSPRUEFUNG-2026-09-30-v1.0.md). Commit und Upload warten noch auf die abschließende Freigabe. Sie enthält jetzt den [AMD-Installer 1.0.2](../7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh) mit vollständigen Lizenz- und Änderungshinweisen sowie die aktualisierte Anleitung und den Abschlussbericht. Die bestätigte 1.0.1-Datei bleibt lokal und wird nicht mit ausgewählt. Auswahlen 1.7 und 1.8 bleiben als historische Stände enthalten; maßgeblich für den nächsten Upload ist ausschließlich diese Auswahl 1.9. Die [Verzeichnisstruktur](STRUKTUR.md) und die MIT-Projektlizenz mit Copyright © 2026 Thomas Kienzle bleiben bestehen; der vollständige Text steht in [LICENSE](../LICENSE). Fremdsoftware und Modelle behalten ihre eigenen Bedingungen. Ziel ist das bereits öffentliche Repository `thomaskien/kienzlefon-ai`, Standardbranch `main`. Der abgerufene Ausgangsstand ist `c93f063c90c4af9e460dbb2ad8a8068f311696ac` mit einem Commit. Die historische Installerdatei wird bytegleich unter `installer/historisch/` eingeordnet. Der eigentliche Arbeitsordner bleibt ohne Git; der separate Veröffentlichungskandidat enthält die bestehende Historie. Es wurde nichts hochgeladen.

## Aktuelle Entscheidungen und abgeschlossene Lizenzkorrektur

- Der Betreiber bestätigt: Sein persönlicher Hugging-Face-Token war niemals öffentlich. Eine Tokenrotation wird aus der lokalen Snapshotkopie nicht als Veröffentlichungsvoraussetzung abgeleitet. Die Uploadausschlüsse bleiben verbindlich.
- Die CUDA-Pyannote-Bindung an alle IPv4-Schnittstellen ist für den Zugriff berechtigter Praxisrechner erforderlich und ausdrücklich bestätigt. Sie bleibt unverändert; die Netzgrenzen sind in [SECURITY.md](../SECURITY.md) erläutert.
- Die [Lizenzprüfung 1.1](LIZENZPRUEFUNG-2026-09-30-v1.1.md) dokumentiert den Abschluss der beiden konkreten Hinweiskorrekturen. Neun vollständige [Fremdlizenztexte mit Quellen](lizenzen/README.md) sind im Repository und im neuen AMD-Installer enthalten.
- **AMD 1.0.2 ersetzt 1.0.1 in der Dateiauswahl.** Änderungshinweise und vollständige Begleitlizenzen sind eingebettet, Programmlogik und Abhängigkeiten unverändert. 71 lokale Selbsttests, Manifestprüfung und reproduzierbarer Build bestanden. Die XTX-Hardwarebefunde beziehen sich weiterhin auf 1.0.1; keine erneute Installation erfolgt.

## Verbindliche Ausschlüsse auf Benutzeranweisung

**Der Hugging-Face-Token und sämtliche Hörproben dürfen keinesfalls hochgeladen werden.** Dies gilt für Repository-Inhalte und Historie, Release-Anhänge, Issues sowie Archive und eingebettete oder anders codierte Kopien. Auch rein synthetische Hörproben und ausgewählte Warteansagen sind ausgeschlossen; die Dokumentation darf ihre Eigenschaften und Testergebnisse beschreiben.

Ausgeschlossen bleiben insbesondere:

- Tokenwerte und tokenhaltige Konfigurationen wie `diarization.env`, einschließlich aller Sicherungen und System-Snapshots.
- `assets/` mit den ausgewählten Warteansagen, Hörproben-/Audioverzeichnisse und Audiodateien wie WAV, PCM, MP3, FLAC, OGG, M4A oder Opus – unabhängig vom Ablageort.
- `lokal/`, insbesondere `lokal/hoerproben/`, sowie `archiv/`, `system-snapshots/`, `runs/`, `tests/runs/`, `sophia-runs/`, Mess-/Migrationsarchive und sonstige Pakete, die solche Inhalte enthalten.

Die folgende ausdrückliche Dateiauswahl ist die Grundlage. Ein nicht aufgeführter Ordner wird nicht mitkopiert. Zusätzlich sind Dateiinhalte und eingebettete Pakete zu prüfen: Dateiendungen und `.gitignore` allein reichen nicht aus. Ein bereits erfasster Token oder eine Hörprobe darf auch nicht über frühere Git-Commits mit veröffentlicht werden. Ein Treffer stoppt die Veröffentlichung bis zur Bereinigung des Veröffentlichungskandidaten; lokale Originale werden nicht automatisch gelöscht.

Der Benutzer hat die weitere Untersuchung zur Lizenzklärung ausdrücklich freigegeben. Dafür wurden das ZIP im aktuellen AMD-Installer und sein WhisperLiveKit-Wheel gelesen. Der frühere ZIP-Prüfstopp bleibt für diese Lizenzprüfung nicht bestehen; private Snapshot-, Migrations- und Hörprobenarchive wurden nicht untersucht. Die Lizenzprüfung ersetzt keine vollständige Prüfung des tatsächlichen Veröffentlichungskandidaten auf Geheimnisse und Audio.

## Erreichte Nachweise korrekt veröffentlichen

- [x] Prominenten Projektstatus ergänzt: einsatzfähig mit zwei Telefonkanälen; bei zusätzlicher Kienzledoku-Nutzung höchstens zwei, weiterhin Work in progress. Dies ist die vom Projektbetreiber vorgegebene Betriebsempfehlung, keine zusätzliche Lastmessung.
- [x] Wartepieptöne als angenehm empfundene Überbrückung erklärt; neue 2.5.2-Folge und Vorrang fertiger Antworten beschrieben. Neue Defaults nur lokal geprüft, Aktivierung separat.
- [x] Nächste Arbeit an der Stimmqualität, Framework-Desktop-Testaufruf ab 64 GB und Kienzlefon classic als IVR-Alternative aufgenommen.
- [x] [Sophia-Vergleich 1.1](VERGLEICH-SOPHIA-v1.1.md) um die nachgereichte Inhaltsanalyse ergänzt: fachliche Vergleichstabelle, um Weiterleitungen bereinigte Speicherung und konkrete Stärken/Schwächen. Vier Kienzlefon-Durchläufe gegenüber einem Sophia-Lauf sowie unterschiedliche Testwege direkt benannt.
- [x] Automatischen Manifeststatus `NOT_PERFORMED` von der später übergebenen separaten Inhaltsanalyse unterschieden. Übernommene Bewertungen und lokal nachgezählte Befunde kenntlich gemacht.
- [x] Spätere Rückkehr des Telefonbetriebs zur RTX 3090 berücksichtigt; XTX-Tests vom 29. September als weiterhin gültige historische Nachweise eingeordnet.

- [x] [Benchmarkübersicht](BENCHMARK-XTX-v1.0.md) mit XTX-/3090-Vergleich, Messbedingungen und Wiederholungszahlen erstellt.
- [x] Frühere PyTorch-TTS-Messung von der späteren nativen HIP-TTS und dem installierten Dienst getrennt.
- [x] AMD 1.0.1 als real installiert und dienstgeprüft beschrieben, einschließlich finalem ASR-Rollenupdate und zweimal acht gleichzeitigen Anfragen.
- [x] Tatsächlich migrierte Telefonruntime **2.5** und vorhandenen Piper berücksichtigt; keine behauptete Installation von CUDA-/Backend-2.5.1 auf XTX.
- [x] Erfolgreichen realen Reload von noch offenem erzwungenem Rollback getrennt.
- [x] Knappen VRAM, fehlende umfassende Qualitäts-/Dauerlast-/Rebootabnahme und Telemetriegrenzen benannt.
- [ ] Noch offene Telefon-/Hör-, Dauerlast-, Boot- und Hardware-Uninstall-Prüfungen getrennt abnehmen; keine Hochstufung allein durch Veröffentlichung.

Die bestandenen Hardwaretests sind ein wesentlicher Fortschritt. Eine Veröffentlichung als geprüfter Entwicklungsstand kann sie benennen, ohne daraus eine allgemeine Produktiv-, Qualitäts- oder Hardwarekompatibilitätszusage zu machen.

## Öffentliche Dateiauswahl

Die folgende Liste führt die Auswahl mit dem korrigierten AMD-Installer und den aktuellen Dokumenten fort. Die AMD-Anleitung 1.0.1 und Veröffentlichungsauswahlen 1.0 bis 1.6 bleiben lokal. Auswahlen 1.7 und 1.8 werden als historische Stände mitgeführt. Der Meldeweg ist festgelegt und die abschließende Kandidatenprüfung abgeschlossen; maßgeblich ist diese Auswahl 1.9. Sie umfasst einzelne Dateien und das kanonische Szenariopaket; die Ordner `installer/`, `tests/` und `docs/spezifikationen/` werden nicht vollständig übernommen. Die [Release Notes 2.5.2](RELEASE-NOTES-v2.5.2.md) beschreiben deren begrenztes Wartefeedback-Delta; die XTX-Hardwarebefunde beziehen sich weiterhin auf die migrierte Telefonruntime 2.5. Die Projektlizenz ist festgelegt; die Auswahl ersetzt weder die Prüfung auf Geheimnisse und Hörproben noch die gesonderte Prüfung der Drittkomponenten.

```text
README.md
LICENSE
SECURITY.md
installer/README.md
installer/historisch/README.md
installer/historisch/install-kienzlefon-qwen3-tts-v1.5.sh
tests/README.md
docs/STRUKTUR.md
docs/spezifikationen/README.md
docs/spezifikationen/SPEZIFIKATION-KIENZLEFON-AI-SERVERINSTALLER-v2.5.2.md
docs/spezifikationen/SPEZIFIKATION-KIENZLEFON-DIALOG-TESTSUITE-v1.2.md
docs/BENCHMARK-XTX-v1.0.md
docs/AMD-INSTALLATION-v1.0.2.md
docs/RELEASE-NOTES-AMD-v1.0.2.md
docs/VEROEFFENTLICHUNG-2026-09-30-v1.7.md
docs/VEROEFFENTLICHUNG-2026-09-30-v1.8.md
docs/VEROEFFENTLICHUNG-2026-09-30-v1.9.md
docs/VEROEFFENTLICHUNGSPRUEFUNG-2026-09-30-v1.0.md
docs/LIZENZPRUEFUNG-2026-09-30-v1.0.md
docs/LIZENZPRUEFUNG-2026-09-30-v1.1.md
docs/lizenzen/README.md
docs/lizenzen/QUELLEN.json
docs/lizenzen/Diart-LICENSE.txt
docs/lizenzen/NeMo-LICENSE.txt
docs/lizenzen/Silero-VAD-v6-LICENSE.txt
docs/lizenzen/SimulStreaming-LICENCE.txt
docs/lizenzen/SimulWhisper-LICENSE.txt
docs/lizenzen/Whisper-LICENSE.txt
docs/lizenzen/Whisper-Streaming-LICENSE.txt
docs/lizenzen/WhisperLiveKit-0.2.24-LICENSE.txt
docs/lizenzen/qingming-qwen3-tts-LICENSE.txt
docs/VERGLEICH-SOPHIA-v1.0.md
docs/VERGLEICH-SOPHIA-v1.1.md
docs/ARCHITEKTUR-v2.5.1.md
docs/INSTALLATION-v2.5.1.md
docs/BETRIEB-v2.5.1.md
docs/TESTS-v2.5.1.md
docs/RELEASE-NOTES-v2.5.1.md
docs/RELEASE-NOTES-v2.5.2.md
docs/VEROEFFENTLICHUNG-v2.5.1.md
docs/spezifikationen/SPEZIFIKATION-KIENZLEFON-AI-INTEGRATION-v2.5.2.md
installer/install-kienzlefon-ai_v2.5.1.sh
installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh
installer/install-kienzlefon-ai_v2.5.2.sh
installer/kienzlefon-installer-asterisk-backend-v2.5.2.sh
7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh
tests/kienzlefon-dialog-testsuite-v1.2.6.py
tests/kienzlefon-dialog-testsuite-requirements-v1.0.txt
tests/kienzlefon-ai-pipeline-test-v1.2.1.py
tests/kienzlefon-ai-parallel-test-v1.0.1.py
tests/kienzlefon-testsuite-spec-v1/   (vollständiges kanonisches Manifestpaket)
```

Der AMD-Installer enthält sein geprüftes Quellpaket samt MIT-Projektlizenz, neun Fremdlizenztexten, Herkunfts- und Änderungshinweisen. Für seine Ausführung wird nicht der gesamte XTX-Arbeitsordner benötigt. Große LLM-/ASR-/TTS-/Diarisierungsgewichte und zusätzliche Build-/Python-Pakete lädt die Installation separat; kleine Silero-VAD-Modelle sind bereits im WhisperLiveKit-Wheel enthalten.

Die Benchmarkübersicht und der Sophia-Vergleich enthalten Zahlen und Methodik ohne Audio, Rohtranskripte oder konkrete private Netzadressen. Der aktuelle Sophia-Vergleich enthält fachliche Ergebnisse der nachgereichten Auswertung, aber keine gemeinsame Gesamtnote. Die technischen Werte 586/600 für Kienzlefon „Archive 4“ und 83/150 für Sophia stammen aus unterschiedlichen Text-/Telefonpfaden. Der separate Kienzlefon-1.9.9-Lauf mit 147/150 bleibt in der historischen Übersicht 1.0 und wird nicht mit „Archive 4“ vermischt. Der automatische Manifeststatus `NOT_PERFORMED` schließt die separat übergebene Inhaltsanalyse nicht aus. Ihre internen Quellberichte bleiben zur Nachvollziehbarkeit lokal erhalten. Eine zusätzliche Auswahl technischer Rohdaten hebt den Ausschluss von Token und Hörproben nicht auf; Verzeichnisse werden nicht pauschal übernommen.

## Private XTX-Artefakte ausschließen

Insbesondere nicht pauschal übernehmen:

- `7900XTX/secrets/`, SSH-/WireGuard-Schlüssel, Netzkonfigurationen und Geräteimportdateien.
- `7900XTX/telephony-migration-v1.0/`, insbesondere das private Quellarchiv mit Zugangsdaten und die umgebungsspezifischen Migrationsskripte.
- Ungeprüfte Audit-/Messverzeichnisse, Compiler-Caches, Buildbäume, Venvs und Audioartefakte.
- `lokal/`, `archiv/`, `system-snapshots/`, `runs/`, `tests/runs/`, `sophia-runs/` und deren Archive einschließlich Rohtranskripten, Audio, Exportdaten und Verbindungsmetadaten; für den Vergleich wird nur die bereinigte Übersicht ausgewählt.
- Interne `PROJECT.md`, `STATUS.md`, Workeraufträge und Berichte mit konkreten Betriebs-/Netzadressen, sofern sie nicht gesondert bereinigt und ausgewählt wurden.

Die Snapshotkopie enthält einen persönlichen, laut Betreiber niemals veröffentlichten Token und bleibt privat. Ihr Vorhandensein allein begründet keine erforderliche Rotation oder Löschung; sie darf nicht in den Veröffentlichungskandidaten gelangen. [SECURITY.md](../SECURITY.md) beschreibt die Geheimnisbehandlung und die unterschiedlichen Netzdefaults von CUDA und AMD.

## Vor dem Upload

- [x] Projektlizenz auf Benutzerauftrag festgelegt: MIT, Copyright © 2026 Thomas Kienzle. `LICENSE` liegt im Projektwurzelverzeichnis und ist in der Veröffentlichungsauswahl enthalten.
- [x] Hauptkomponenten, Modellkarten und tatsächlich eingebettete Fremdquellen geprüft; Umfang und Grenzen im [Lizenzbericht](LIZENZPRUEFUNG-2026-09-30-v1.0.md) dokumentiert.
- [x] Lizenz-/Hinweiskorrektur als AMD 1.0.2 umgesetzt, geprüft und in dieser Auswahl anstelle von 1.0.1 aufgenommen; [Abschlussbericht](LIZENZPRUEFUNG-2026-09-30-v1.1.md).
- [x] Tokenstatus mit Betreiber geklärt: niemals öffentlich, keine daraus abgeleitete Rotationspflicht. Beim Zusammenstellen des Uploads sämtliche Tokenkopien und Hörproben weiterhin ausschließen.
- [x] Privaten Meldeweg für Sicherheitsprobleme festgelegt und in [SECURITY.md](../SECURITY.md) dokumentiert: [tk@mampf.net](mailto:tk@mampf.net).
- [x] Kandidaten in einem separaten Checkout aus der Dateiauswahl zusammengestellt. Bestehenden historischen Installer bytegleich eingeordnet. Inhalte einschließlich eingebetteter Pakete und der vollständigen abgerufenen Historie auf Token-/Schlüsselmerkmale, Audio und private Arbeitsdateien geprüft; keine ungeklärten Treffer. [Prüfumfang und Grenzen](VEROEFFENTLICHUNGSPRUEFUNG-2026-09-30-v1.0.md).
- [x] Relative Links der lokalen Dateiauswahl sowie neue Installer-Version und Hashes abgeglichen. Historische Hinweise bleiben dem jeweiligen Prüfstand zugeordnet.
- [x] Lokale Links, Dateiauswahl, Quellidentität, Installer-Versionen und Prüfsummen am tatsächlichen Veröffentlichungskandidaten abgeglichen.
- [x] Eingebettetes AMD-Quellpaket und enthaltenes WhisperLiveKit-Wheel für die Lizenzprüfung geöffnet, Lizenztexte und Herkunft abgeglichen. Die anschließende Inhaltsprüfung des tatsächlichen Uploadkandidaten ist im verlinkten Prüfbericht dokumentiert.
- [x] Fachliche Vergleichsaussagen auf die nachgereichte historische Auswertung und ihre jeweiligen Fallzahlen beschränken; technische Erfolgsquoten nicht als Dialogqualität darstellen. Für eine Aussage zur besseren Stimme fehlt weiterhin eine vergleichende Hörbewertung.
- [x] Passende lokale Prüfungen protokolliert: Syntax, Version/Hilfe, Plan, 71 Selbsttests, Paket-/Lizenz-/Quellabgleich und bytegleicher Wiederholungsbuild. Keine neuen GPU-, produktiven Dienst- oder Telefonietests; [Release Notes](RELEASE-NOTES-AMD-v1.0.2.md).
- [ ] Abschließende Benutzerfreigabe für diesen geprüften Stand einholen; danach als neuen Commit auf `main` veröffentlichen. Vor dem Push erneut prüfen, ob der Remote-Stand unverändert ist; kein Überschreiben fremder Änderungen und kein Force-Push.

AMD-1.0.2-Referenzhash:

```text
3058e464e274a20169459c9eb15aa5a994227ea744547e89779bef9afe482a9e  7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh
```

Die CUDA-/Backendhashes stehen unverändert in den [Release Notes 2.5.1](RELEASE-NOTES-v2.5.1.md). Hashes identifizieren Dateien; sie ersetzen weder Signatur noch Inhaltsprüfung.
