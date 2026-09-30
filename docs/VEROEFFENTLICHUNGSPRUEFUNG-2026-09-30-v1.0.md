# Prüfung des Veröffentlichungskandidaten

[Zur README](../README.md) · [Verbindliche Dateiauswahl 1.9](VEROEFFENTLICHUNG-2026-09-30-v1.9.md) · Stand: 30. September 2026

**Der Veröffentlichungskandidat ist vorbereitet und geprüft.** Die bekannten Lizenzhinweise sind ergänzt, der private Meldeweg ist festgelegt und die abschließende Inhaltsprüfung hat keine ungeklärten Geheimnis- oder Audiofunde ergeben. Die Benutzerfreigabe für Commit und Upload steht noch aus.

## Repository und Umfang

Ziel ist das bereits öffentliche Repository [thomaskien/kienzlefon-ai](https://github.com/thomaskien/kienzlefon-ai) mit Standardbranch `main`. Ausgangsstand: `c93f063c90c4af9e460dbb2ad8a8068f311696ac`, ein bestehender Commit und eine Installerdatei; keine weiteren abgerufenen Branches oder Tags. Die bestehende Git-Historie wird fortgeführt.

Der Kandidat umfasst **209 Dateien**, darunter das kanonische Paket mit 150 synthetischen Dialogszenarien. Der bisherige Qwen-TTS-Einzelinstaller 1.5 wird bytegleich aus der Projektwurzel nach `installer/historisch/` verschoben und dort als historisch beschrieben. Bestätigte Programmversionen werden inhaltlich nicht verändert.

Enthalten sind insbesondere README, MIT-Lizenz, Sicherheitskontakt **[tk@mampf.net](mailto:tk@mampf.net)**, Benchmark- und Sophia-Vergleich, Installations-/Betriebsdokumentation, die CUDA-/Backendpaare 2.5.1 und 2.5.2, AMD 1.0.2 und die ausgewählten Tests. Aktueller Umfang und Pfade stehen in der Dateiauswahl 1.9; ältere Checklisten sind historische Dokumentstände.

## Inhaltsprüfung

- Alle ausgewählten Dateien einschließlich des bestehenden historischen Installers geprüft; keine Übernahme privater Arbeitsverzeichnisse, Konfigurationen, Snapshots oder Run-Exporte.
- Den eingebetteten AMD-Payload, das unveränderte WhisperLiveKit-Wheel und dessen weitere ZIP-basierte Modelldaten bzw. Filterdateien rekursiv gelesen. Archive nur im Speicher ausgewertet, keine darin enthaltenen Programme oder Modelle ausgeführt. Private Migrations-, Snapshot- und Hörprobenarchive blieben unangetastet.
- Dateinamen, typische Audio-Dateikennungen, Zugangstoken-/Schlüsselmuster, feste Zugangsdaten, private Netzadressen und zusätzliche große codierte Blöcke geprüft. Die vollständig abgerufene Git-Historie einschließlich Commit-Metadaten und Dateiblob ist einbezogen.
- Alle 48 zur Sichtung markierten Fundstellen einzeln eingeordnet: interaktive Eingabeaufforderungen, ausdrückliche Platzhalter, synthetische Selbsttestadressen und upstream-eigene Tokenizer-/Filterdateien. Kein ungeklärter Befund bleibt offen. Die Whisper-`assets` sind Bibliotheksdaten und keine lokalen Hörproben.
- Das enthaltene technische TTS-Messprotokoll enthält Zeit-/Statuswerte, keine Audiodateien oder Ein-/Ausgabetexte. Die Szenariodaten stammen unverändert aus dem kanonischen synthetischen Paket; ihr Manifest und die Zahl von 150 Szenarien sind abgeglichen.

Diese Prüfung untersucht den konkreten Kandidaten und die erreichbare abgerufene Historie. Sie ist keine pauschale Garantie für beliebige zukünftige Änderungen oder absichtlich versteckte Daten. Es wurde keine private Tokenkopie zum Vergleich geöffnet. Große Modellgewichte werden separat geladen; die im Fremdpaket enthaltenen kleinen VAD-Modelle sind bereits im Lizenzbericht eingeordnet.

## Technische Verifikation

Die Dateien des Kandidaten wurden per SHA-256 mit der festgelegten lokalen Auswahl abgeglichen. Relative Dokumentlinks zeigen auf vorhandene Dateien innerhalb der Auswahl. Shell-/Python-Syntax sowie Version und Hilfe der fünf aktuellen Installer und drei Testrunner wurden an den kopierten Dateien geprüft. Der historische Einzelinstaller wurde bytegleich übernommen und auf Shellsyntax geprüft.

AMD 1.0.2 bleibt bei SHA-256 `3058e464e274a20169459c9eb15aa5a994227ea744547e89779bef9afe482a9e`. Seine 71 zuvor bestandenen lokalen Selbsttests und die Paket-/Lizenzprüfung gelten für genau diese unveränderten Bytes. Die bestehenden CUDA-/Backendinstaller und Tests wurden ebenfalls nicht inhaltlich geändert; vollständige Selbsttests werden für die reine Zusammenstellung nicht erneut als neue Abnahme ausgegeben.

Keine Installation, Dienst-, GPU- oder Netzwerkänderung wurde durchgeführt. Die XTX-Hardwarebefunde stammen weiterhin aus AMD 1.0.1, die neue Prüfung ist eine Veröffentlichungskontrolle. Work in progress, Zwei-Kanal-Empfehlung und offene praktische Abnahmen bleiben ausdrücklich dokumentiert.

## Nächster Schritt

Nach der Benutzerfreigabe diesen geprüften Stand als neuen Commit auf `main` übertragen. Unmittelbar davor Remote-Ausgangsstand und Dateiidentität erneut kontrollieren; bei zwischenzeitlichen Änderungen zuerst abgleichen. Keine Historienumschreibung und kein Force-Push. Ein eigenständiges versioniertes GitHub-Release ist mit dieser Vorbereitung nicht erstellt.
