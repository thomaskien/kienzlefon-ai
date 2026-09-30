# Tests und Szenarien

[Zur Projektübersicht](../README.md)

| Einstieg | Aufgabe |
|---|---|
| [Dialog-Testsuite 1.2.6](kienzlefon-dialog-testsuite-v1.2.6.py) | Synthetische Dialogtests und gesondert konfigurierte Sprachtests |
| [Szenariopaket](kienzlefon-testsuite-spec-v1/) | Kanonisches Paket mit 150 Szenarien, Schemas, Vorlagen und Manifest |
| [Requirements](kienzlefon-dialog-testsuite-requirements-v1.0.txt) | Abhängigkeiten der Dialogsuite |
| [Pipeline-Test 1.2.1](kienzlefon-ai-pipeline-test-v1.2.1.py) | Gesonderte Prüfung der Audio-/KI-Pipeline |
| [Paralleltest 1.0.1](kienzlefon-ai-parallel-test-v1.0.1.py) | Gesonderte Lastmessung |

Programme und Szenariopaket wurden unverändert gemeinsam hierher verschoben. Dadurch bleiben die vom Runner relativ zu seiner eigenen Datei bestimmten Szenario-, Schema- und Vorlagenpfade gültig. Frühere Runner, Unit-Tests und historische Prompts bleiben zur Nachvollziehbarkeit ebenfalls erhalten.

Aus der Projektwurzel:

```bash
python3 tests/kienzlefon-dialog-testsuite-v1.2.6.py --version
python3 tests/kienzlefon-dialog-testsuite-v1.2.6.py --help
```

Die [Testanleitung](../docs/TESTS-v2.5.1.md) erläutert Abhängigkeiten und Voraussetzungen. Echte Testanrufe und Hardwaretests werden durch die Ordnerbereinigung nicht ausgeführt.

Ohne ausdrückliches Ausgabeziel verwendet die Dialogsuite nun `tests/runs/`, da sie dieses Verzeichnis relativ zum eigenen Skript bestimmt. Bisherige Läufe bleiben unverändert im bisherigen Projektordner `runs/`; das ist eine Folge des neuen Skriptorts, keine Änderung der Programmlogik. Für ein gewünschtes Ausgabeziel `--output` ausdrücklich setzen. Sämtliche Run-Ausgaben und Audioartefakte bleiben privat und sind nicht Teil der Veröffentlichungsauswahl.
