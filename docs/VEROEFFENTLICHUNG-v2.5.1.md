# Vorbereitung der GitHub-Veröffentlichung 2.5.1

[Zur README](../README.md) · Stand: 28. September 2026

Ziel: [thomaskien/kienzlefon-ai](https://github.com/thomaskien/kienzlefon-ai).

Diese Checkliste dient der Vorbereitung. Sie ist keine Bestätigung eines Uploads, Tags oder Releases. Im lokalen Projektordner ist kein nutzbares Git-Repository vorhanden. Die am 28. September 2026 über die öffentliche [GitHub-Dateiliste](https://api.github.com/repos/thomaskien/kienzlefon-ai/contents/) geprüfte Hauptverzeichnisansicht enthielt nur `install-kienzlefon-qwen3-tts-v1.5.sh`; das ist der historische Einzelinstaller, nicht das aktuelle 2.5.1-Paar.

## 1. Veröffentlichungsstatus festlegen

- [x] Dokumentation bezeichnet 2.5.1 als lokalen Entwicklungsstand mit ausstehender Zielhardwareabnahme.
- [x] Neuinstallation, Backendupdate und späterer Reload werden getrennt erklärt.
- [x] README und Release Notes stellen keine allgemeine Produktivfreigabe oder feste Latenz in Aussicht.
- [ ] Entscheiden, ob zunächst nur der Entwicklungsstand im Repository oder zusätzlich ein ausdrücklich als Vorabversion gekennzeichnetes Release veröffentlicht wird.
- [ ] Nach realer Abnahme die zugehörigen Ergebnisse und Grenzen ergänzen; keinen Teststatus allein aufgrund eines Uploads hochstufen.

Das zuletzt technisch aktivierte Backend 2.4.2 und der vorbereitete Stand 2.5.1 dürfen nicht als derselbe getestete Stand beschrieben werden.

## 2. Lizenz und Herkunft klären

- [ ] Projektlizenz durch den Maintainer festlegen und eine passende `LICENSE` bereitstellen. Derzeit fehlt diese Entscheidung.
- [ ] Herkunft und erforderliche Hinweise für eingebettete bzw. mitgelieferte Software, Testmaterial und eventuelle Audioassets prüfen.
- [ ] Lizenz-/Zugriffsbedingungen der tatsächlich verwendeten Modellversionen und Abhängigkeiten prüfen. Eine Projektlizenz ersetzt diese Bedingungen nicht.
- [ ] Einen privaten Meldeweg für Sicherheitsprobleme festlegen und `SECURITY.md` entsprechend aktualisieren.

Diese Dokumentation vergibt keine Lizenz stellvertretend für den Rechteinhaber und enthält keine pauschale Lizenzfreigabe für Drittkomponenten.

## 3. Bekannte Tokenkopie behandeln

- [ ] Den im lokalen Projektstatus dokumentierten Hugging-Face-Token beim Anbieter widerrufen bzw. ersetzen; Durchführung bestätigen.
- [ ] Die bekannte Snapshotkopie und weitere Kopien nach gesonderter Freigabe kontrolliert bereinigen.
- [ ] Prüfen, ob die betreffende Information jemals in eine Git-Historie oder frühere Veröffentlichung gelangt ist. Der lokale Befund allein belegt keine Veröffentlichung des Tokens.
- [ ] Tatsächlich ausgewählte Dateien und spätere Git-Änderungen auf Zugangsdaten und personenbezogene Inhalte prüfen, ohne Trefferwerte in normale Logs zu schreiben.

Der betroffene Snapshot darf keinesfalls mit veröffentlicht werden. Es wurde im Rahmen der Dokumentation weder ein Token widerrufen noch eine Sicherung verändert. Details: [SECURITY.md](../SECURITY.md).

## 4. Dateien ausdrücklich auswählen

Für einen übersichtlichen ersten 2.5.1-Stand ist folgende Auswahl vorgesehen. Dateiauswahl ist noch keine Freigabe der jeweiligen Inhalte; vor dem Upload die Kandidaten prüfen.

### Öffentliche Dokumentation

```text
README.md
SECURITY.md
docs/ARCHITEKTUR-v2.5.1.md
docs/INSTALLATION-v2.5.1.md
docs/BETRIEB-v2.5.1.md
docs/TESTS-v2.5.1.md
docs/RELEASE-NOTES-v2.5.1.md
docs/VEROEFFENTLICHUNG-v2.5.1.md
```

### Installerpaar

```text
installer/install-kienzlefon-ai_v2.5.1.sh
installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh
```

Die benötigten Runtimeprogramme sind in den Installern eingebettet. Historische einzelne Prompt-, Overlay-, Chat- und TTS-Dateien werden für dieses Paar nicht zusätzlich als aktuelle Komponenten benötigt. Den bereits öffentlichen TTS-Installer 1.5 nicht versehentlich überschreiben; seine Behandlung als historische Datei im tatsächlichen Git-Checkout prüfen.

### Tests

```text
tests/kienzlefon-dialog-testsuite-v1.2.6.py
tests/kienzlefon-dialog-testsuite-requirements-v1.0.txt
tests/kienzlefon-ai-pipeline-test-v1.2.1.py
tests/kienzlefon-ai-parallel-test-v1.0.1.py
tests/kienzlefon-testsuite-spec-v1/   (kanonisches Paket; 150 Szenarien, Manifest prüfen)
```

Das Szenariopaket als zusammenhängendes, manifestgeprüftes Paket übernehmen. Darin enthaltene historische Einleitungstexte anhand der neuen Testanleitung einordnen; Dateien nicht unbemerkt verändern und damit Manifesthashes ungültig machen.

Die ausführlichen bisherigen Spezifikationen können nach Prüfung ergänzend veröffentlicht werden. Einzelne spätere Spezifikationen verweisen auf ältere Fassungen: Bei Übernahme die gesamte tatsächlich benötigte Verweiskette mitnehmen oder eine gesonderte konsolidierte Fassung erstellen. Die neue Einstiegsdokumentation setzt diese historischen Dateien nicht voraus.

Die ausgewählten allgemeinen Füllclips unter `assets/filler-seed-12345-v2.4.2/` sind optionale Referenzassets. Der Installer kann benötigte Clips über Qwen vorbereiten und setzt dieses Quellverzeichnis nicht als Installationspaket voraus. Audioassets nur nach ausdrücklicher Auswahl und Prüfung ihrer Herkunft, Inhalte und Weitergabebedingungen aufnehmen.

### Nicht pauschal übernehmen

| Lokaler Inhalt | Grund |
|---|---|
| `system-snapshots/`, Live-Dateisicherungen und Archive | Enthalten bzw. können Zugangsdaten und installierte Konfiguration enthalten |
| `runs/`, `sophia-runs/`, `benchmark/`, einzelne Benchmark-JSON-Dateien | Private Test-/Messartefakte; nicht allein aufgrund des Dateinamens inhaltsfrei |
| Lokale WAV-/PCM-Dateien, `lokal/hoerproben/stimmen/` | Audio und Hörproben; Veröffentlichung nicht allgemein freigegeben |
| Alte ZIP-/TAR-Pakete, alternative Szenariopakete und Quarantäne | Ungeprüfte oder doppelte Historie, teilweise andere Szenariostände |
| Historische Reparatur-/Patchdateien und Hostskripte | Nicht die dokumentierte 2.5.1-Installation; gegebenenfalls umgebungsspezifisch |
| `PROJECT.md`, `STATUS.md`, `AGENTS.md`, Workeraufträge | Interne Arbeitsanweisungen und Betriebsdetails; vor möglicher Veröffentlichung gesondert prüfen |
| Caches, `lokal/caches/__pycache__/`, `lokal/caches/.pytest_cache/`, `.venv*`, `lokal/caches/root.DS_Store` | Lokale Arbeitsartefakte |

Kein pauschales `git add .` im historischen Arbeitsverzeichnis verwenden. Eine spätere `.gitignore` ist eine zusätzliche Hilfe und ersetzt weder Dateiprüfung noch Prüfung der Git-Historie. In dieser Dokumentationsaufgabe wurde keine Repositorykonfiguration angelegt oder verändert.

## 5. Kandidaten prüfen

- [ ] Die ausdrückliche Dateiauswahl in einem separaten Checkout des vorhandenen GitHub-Repositories zusammenstellen; bestehende Remote-Historie beibehalten.
- [ ] Beide Installer melden 2.5.1; ihre SHA-256-Werte stimmen mit den Release Notes überein.
- [ ] Shellsyntax und isolierte Selbsttests nach [Testanleitung](TESTS-v2.5.1.md) ausführen und Ergebnis, Datum und Umgebung festhalten.
- [ ] Dialog-Requirements und vollständiges Szenariopaket prüfen; fehlende Abhängigkeiten nicht als bestandenen Runner-Test werten.
- [ ] Links und Codebeispiele nochmals im tatsächlichen Veröffentlichungskandidaten prüfen. Relative Links müssen dort dieselben Ziele wie lokal erreichen.
- [ ] Alle tatsächlich vorgesehenen Dateien auf Geheimnisse und ungeeignete persönliche bzw. lokale Inhalte prüfen. Eine reine Musterprüfung ist keine umfassende Freigabe.

Nach gezieltem Staging in diesem separaten Checkout:

```bash
git status --short
git diff --cached --name-status
git diff --cached --stat
git diff --cached --check
```

Dateiliste und Inhalt der ausgewählten Änderungen kontrollieren. Ein leerer Whitespace-Check beweist keine Geheimnisfreiheit. Verdächtige Inhalte vertraulich prüfen, bevor Diffausgaben weitergegeben werden.

## 6. Veröffentlichen

- [ ] Konkrete geprüfte Dateiauswahl, Lizenzstatus und bekannte Grenzen zur abschließenden Veröffentlichung freigeben.
- [ ] Erst dann Commit und Push zum vorgesehenen Repository ausführen.
- [ ] Falls gewünscht, die geprüften Dateien mit einem Release verknüpfen und [Release Notes](RELEASE-NOTES-v2.5.1.md) übernehmen. Den Status als Vorabversion bis zur passenden Abnahme klar kennzeichnen.
- [ ] Anschließend die tatsächlich sichtbare README, Dateilinks, Installerdateien, Checksummen und gegebenenfalls Release-Assets auf GitHub prüfen.

Die Erstellung der Dokumentation umfasst keinen Commit, Push, Tag, Release, Serverzugriff oder Installationslauf. Offene Punkte bleiben bis zu einem eigenen Nachweis offen.
