# Tests und Validierungsstand – Version 2.5.1

[Zur README](../README.md) · Stand: 28. September 2026

## Was bisher belegt ist

Die folgende Einordnung übernimmt die dokumentierten Ergebnisse aus dem lokalen Projektstand. Frühere Ergebnisse werden nicht als im Zuge dieser Dokumentation neu ausgeführte Tests dargestellt.

| Bereich | Vorliegender Nachweis | Aussagegrenze |
|---|---|---|
| Installer 2.5.1 | Shellsyntax, Version, Hilfe und isolierte Selbsttests laut Projektstatus bestanden | Keine reale Installation oder Deinstallation |
| Backendruntime 2.5.1 | Gerenderte Python-Payloads, Konfiguration, Zeitplan, Clipwiederverwendung, Reload und Fehlerpfade isoliert geprüft | Dienste und Telefonturns teilweise simuliert; keine Telefon-End-to-End-Abnahme |
| KI-Installationsbestätigung 2.5.1 | Zustimmung, Ablehnung, leere/ungültige Eingabe, EOF und nichtinteraktive Bestätigung isoliert geprüft | Kein Test der nachfolgenden echten Installation |
| Pyannote-Bind-Konfiguration 2.5.1 | Frischer Standard, Vorrang, Bestandserhalt, ungültige Werte, Tokenfreiheit der Meldungen, Health-URLs und Schreibpfad mit temporären Fixtures laut Projektstatus geprüft | Keine reale Netzfreigabe, Bind- oder Erreichbarkeitsabnahme |
| Ausgewählte Altclips | 2.4.2-Audiodateien durch 2.5 lokal importiert und bytegleich verglichen; null Syntheseaufrufe; Backendcode in 2.5.1 ausschließlich versionsangepasst | Keine neue Qwen-Synthese und keine Hörprüfung am Telefon |
| Backend 2.4.2 | Auf der Referenzhardware aktiviert; Runtime-Health, drei Registrierungen und freie Plätze technisch geprüft | Hörprüfung und umfassende Gesprächsabnahme weiterhin offen |
| Frühere Telefonstände | Reale einzelne Pipeline- und Telefonmessungen vorhanden | Kleine, ungleiche Stichproben; keine Stabilitäts- oder Latenzzusage für 2.5.1 |
| Dialogszenarien | 150 Szenarien; Manifest mit 158 Dateien laut Projektstatus auf Dateiwerte, Größe und SHA-256 geprüft | Kein vollständiger erfolgreicher Lauf aller Szenarien gegen 2.5.1 |

Der bislang dokumentierte vollständige Runner-Aufruf `--validate-only` scheiterte in der damaligen lokalen Umgebung an fehlendem PyYAML. Die unabhängige Manifest-/Indexprüfung war erfolgreich. Diese beiden Aussagen sind getrennt zu behandeln.

## Prüfung dieser Dokumentation am 28. September 2026

Lokal auf macOS mit Python 3.14.6 geprüft:

- Acht neue Markdown-Dokumente, 41 relative Verweise, geschlossene Codeblöcke und Whitespace.
- Shellsyntax aller 23 dokumentierten Bashbeispiele; Installations-, Reload- und sonstige Systembefehle aus diesen Beispielen wurden dabei nicht ausgeführt.
- Zwei TOML-Beispiele geparst; alle 15 dokumentierten Wartefeedbackwerte stimmen mit dem isoliert gerenderten Backend 2.5.1 überein.
- Beide Installer 2.5.1: Shellsyntax, Version, Hilfe und Abgleich der in den Release Notes genannten SHA-256-Werte.
- Python-Syntax der drei aufgeführten Testskripte sowie Version und Hilfe des Dialogrunners.
- Szenariopaket: alle 158 Manifesteinträge mit Größe und SHA-256 abgeglichen, keine zusätzlichen oder fehlenden Paketdateien; 150 Indexeinträge und 150 Szenariodateien.
- Begrenzte Suche nach üblichen Token- und Privatschlüsselformaten in den 173 vorgesehenen Dokumentations-, Installer- und Testdateien ohne Treffer. Dies ersetzt keine vollständige Prüfung vor dem Upload und umfasst keine privaten Snapshots oder Git-Historie.

Der erneut ausgeführte Dialogrunner mit `--validate-only --channel telephone` endet in dieser Umgebung weiterhin mit Exitcode 2: PyYAML fehlt. Es wurden keine Abhängigkeiten nachinstalliert. Die vollständigen Installer-Selbsttests wurden für diese reine Dokumentationsarbeit nicht erneut ausgeführt; ihr oben genannter Stand stammt aus den dokumentierten Implementierungsprüfungen. Keine Installation, Dienständerung oder Hardwareprüfung wurde durchgeführt.

## Lokale Prüfungen ohne Zielsystem

Im Projektverzeichnis, ohne `sudo`:

```bash
bash -n installer/install-kienzlefon-ai_v2.5.1.sh
bash -n installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh
bash installer/install-kienzlefon-ai_v2.5.1.sh --version
bash installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh --version
bash installer/install-kienzlefon-ai_v2.5.1.sh --help
bash installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh --help
```

Die Installer enthalten außerdem isolierte Selbsttests:

```bash
bash installer/install-kienzlefon-ai_v2.5.1.sh --self-test
bash installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh --self-test
```

Diese verwenden temporäre Dateien und simulierte Gegenstellen. Sie sind keine Aufrufe zur Installation der Dienste. Es wird ein zur jeweiligen Payload passendes Python benötigt; für Backend und Dialogsuite mindestens Python 3.11. Für den zusätzlichen Lauf mit strenger Behandlung von Python-Warnungen:

```bash
PYTHONASYNCIODEBUG=1 PYTHONWARNINGS=error bash installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh --self-test
```

Ein Installationsbaum lässt sich getrennt rendern:

```bash
render_dir="$(mktemp -d /tmp/kienzlefon-ai-render-2.5.1.XXXXXX)"
bash installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh --render-only "$render_dir"
```

Der Renderer benutzt ohne explizite Angaben synthetische Beispielzugänge. Diesen Baum nicht als produktive Konfiguration übernehmen. Das Ziel muss absolut und leer sein. Ein erfolgreicher Renderer beweist weder SIP-Verbindung noch GPU-Nutzung.

## Dialogsuite und Szenariopaket

Runner: [kienzlefon-dialog-testsuite-v1.2.6.py](../tests/kienzlefon-dialog-testsuite-v1.2.6.py). Szenarien: [kienzlefon-testsuite-spec-v1](../tests/kienzlefon-testsuite-spec-v1/). Für einen neuen Testarbeitsplatz kann eine eigene Python-Umgebung eingerichtet werden; die folgenden Befehle installieren ausschließlich die Testabhängigkeiten in dieser Umgebung:

```bash
python3 -m venv .venv-dialog-tests
.venv-dialog-tests/bin/python -m pip install -r tests/kienzlefon-dialog-testsuite-requirements-v1.0.txt
.venv-dialog-tests/bin/python tests/kienzlefon-dialog-testsuite-v1.2.6.py --version
.venv-dialog-tests/bin/python tests/kienzlefon-dialog-testsuite-v1.2.6.py --help
.venv-dialog-tests/bin/python tests/kienzlefon-dialog-testsuite-v1.2.6.py --validate-only --channel telephone
```

Die angegebene [Requirements-Datei](../tests/kienzlefon-dialog-testsuite-requirements-v1.0.txt) fixiert PyYAML und jsonschema. Die virtuelle Umgebung und spätere Testausgaben gehören nicht ins Repository.

Ein direkter synthetischer Einzeltest benötigt zusätzlich die laufende Text-API und einen getrennten Patientensimulator-Kontext:

```bash
.venv-dialog-tests/bin/python tests/kienzlefon-dialog-testsuite-v1.2.6.py \
  --channel telephone --scenario KF-001 --max-parallel 1 \
  --confirm-synthetic-test-data
```

`--channel telephone` allein erzeugt im direkten Modus keinen echten SIP-Anruf. Für Chat `--channel chat` verwenden. Sprachtests benötigen die gesonderten Voice-Optionen aus `--help`, eine geeignete Asterisk-Testanbindung sowie Patient-TTS und Observer-ASR. Die Standards der historischen Pipeline-/Parallelskripte vor Verwendung mit den aktuellen Endpunkten abgleichen.

Die Suite bewertet lokal technische Verträge, keine medizinische oder semantische Qualität. Der Patientensimulator darf die Erwartungen nicht sehen. Prompt und Kanalregeln stammen aus der getesteten Runtime. Private Run-Artefakte können vollständige synthetische Dialoge enthalten und sind keine normalen Performancelogs.

## Noch erforderliche Zielhardwareabnahme

| Prüfung | Zu dokumentierendes Ergebnis |
|---|---|
| Frische und Upgrade-Installation | Jede gewünschte Rolle auf Ubuntu/NVIDIA; exakte Version, Hardware, Treiber und Toolkit |
| LLM und GPU-Zuordnung | Richtiger Modellhash, drei Slots, Gesamtkontext, Residency und tatsächliche UUID-Zuordnung |
| ASR | Genau eine large-v3-Instanz, Gatewayvertrag, Finalisierung und fehlender CPU-Fallback |
| Qwen/Piper | INT8-/Batch-/Sprecherprofil, echtes Streamingaudio, erreichbarer Piper-Fallback ohne Installer-Eingriff in Piper |
| Optionales Pyannote | Downloadfreigabe, Tokenrechte, CUDA-Nutzung und Sprecherantwort |
| Pyannote-Netzbindung 2.5.1 | Bestandserhalt und gezielte Umstellung, tatsächliche Erreichbarkeit nur von vorgesehenen Clients, passende Zugriffsbeschränkung |
| Telefonie und Chat | SIP, G.722/AudioSocket, VAD, Antwort, Auflegen, Handoff, Multi-Order und vorgesehene Spool-Ausgabe |
| 2.5.1-Wartefeedback | Geänderte Texte echt synthetisieren; Tonlautstärke, Aussprache, Startzeiten und Übergang zur Antwort hören |
| Parallelbetrieb | Ein und drei Anrufe; Fehler, Abbrüche, Audioverluste und GPU-Auslastung erfassen |
| Reload und Rückweg | Freie/belegte Plätze, Fehlschlag bei Clipvorbereitung, kontrollierter Aktivierungsfehler und tatsächliche Rücksicherung |
| Deinstallation | Rollenweise und vollständig, ohne fremde Komponenten oder Piper zu beeinträchtigen |
| Szenarien | Alle 150 synthetischen Fälle getrennt je Kanal; technische und inhaltliche Beurteilung getrennt protokollieren |

Ein Abnahmeprotokoll sollte Datum, Installerhashes, Hardware, Konfiguration ohne Geheimnisse, Fallzahl, Fehler, Abbrüche und offene Abweichungen enthalten. Keine Audio-, Patienten- oder Dialoginhalte in das normale technische Protokoll übernehmen.

Für Latenzvergleiche dieselben Testäußerungen, warme Dienste und vergleichbare Last verwenden. Wartefeedback an/aus getrennt betrachten. Erste Warteansage bzw. erster Ton und erstes tatsächliches Antwortaudio sind verschiedene Messpunkte; eine frühere Rückmeldung ist keine nachgewiesene Verkürzung der Rechenzeit.
