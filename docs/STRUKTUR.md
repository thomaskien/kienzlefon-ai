# Verzeichnisübersicht

[Zur README](../README.md) · Neu geordnet am 30. September 2026

Im Projektwurzelverzeichnis bleiben `README.md`, `LICENSE`, `SECURITY.md`, `PROJECT.md`, `STATUS.md` und `AGENTS.md`. Alle folgenden lokalen Pfadangaben beziehen sich auf diese Projektwurzel.

| Ordner | Inhalt |
|---|---|
| [installer/](../installer/README.md) | CUDA-/Backendinstaller aller erhaltenen Versionen; bisherige Einzelmodule unter `installer/modules/` |
| [tests/](../tests/README.md) | Dialog-, Pipeline-, Parallel- und AudioSocket-Testprogramme, zugehörige Testdateien, Prompts, Requirements und Szenariopaket |
| [docs/spezifikationen/](spezifikationen/README.md) | Server-, Integrations- und Testsuitenspezifikationen |
| `docs/anleitungen/` | Ausgelagerte ältere Chat-/Testsuite-READMEs und Pyannote-Tokenanleitung |
| [docs/lizenzen/](lizenzen/README.md) | Unveränderte Lizenztexte der Fremdkomponenten und Quellenverzeichnis |
| `docs/historie/` | Frühere Übergabedokumente |
| `docs/` | Aktuelle Übersichten, Benchmarks, Vergleichsergebnisse, Betriebsdokumentation und Veröffentlichungsauswahl |
| `archiv/` | Alte Einzelkomponenten, Notizen, unverändert verschobene Paketdateien, Systempakete und frühere Szenariokopien; keine pauschale Veröffentlichung |
| `lokal/hoerproben/` | Bisher lose Audiodateien, Stimmproben und der frühere Ordner `testl`; nicht veröffentlichen |
| `lokal/caches/` | Bisherige Python-/Testcaches und Finder-Metadaten |
| `lokal/organisation/` | Protokoll der Verschiebungen mit Zuordnung alter und neuer Pfade |
| `benchmark/root-messungen/` | Zuvor lose Benchmark-JSONs; nur lokale Messartefakte |

Die bestehenden Arbeitsordner `7900XTX/`, `assets/`, `benchmark/`, `runs/`, `sophia-runs/` und `system-snapshots/` bleiben an ihrem Ort. Sie enthalten teils private Daten und sind keine pauschale Veröffentlichungsauswahl. Der AMD-Installer bleibt unter `7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh`.

Programme, Promptdateien und das kanonische Szenariopaket wurden inhaltlich unverändert verschoben. Zusammengehörige historische Chat-/Capacity-Komponenten samt ihren Installern und Tests liegen gemeinsam unter `archiv/entwicklung/`; die Dialogrunner bleiben neben ihrem Szenariopaket unter `tests/`. Die alten Sophia-Aufrufskripte unter `archiv/werkzeuge/` enthalten weiterhin ihre damaligen festen Serverpfade und sind keine neuen lokalen Einstiegspunkte.

Die Dokumentation wurde bei Verweisen auf die neuen Pfade angepasst. Programmversionen und die jeweiligen fachlichen Spezifikationsstände wurden dadurch nicht verändert. Für einen Download einzelner Skripte kann weiterhin deren Dateiname verwendet werden; die dokumentierten Befehle mit `installer/` beziehungsweise `tests/` gelten für die neue Projektstruktur.

**Nichts wurde gelöscht oder hochgeladen.** Bei der Ordnerbereinigung wurden ZIP-/Archivdateien nur verschoben. Die später ausdrücklich freigegebene Lizenzprüfung untersuchte ausschließlich das AMD-Installerpaket samt WhisperLiveKit-Wheel; daraus entstand der neue AMD-Installer 1.0.2 mit ergänzten Lizenzhinweisen. Token, Hörproben und deren Kopien bleiben von jeder Veröffentlichung ausgeschlossen. Entscheidend ist die ausdrückliche [Veröffentlichungsauswahl](VEROEFFENTLICHUNG-2026-09-30-v1.9.md), nicht der gesamte Inhalt dieser Ordner.
