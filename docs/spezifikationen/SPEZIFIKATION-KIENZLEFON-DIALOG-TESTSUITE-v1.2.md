# Kienzlefon Dialog-Testsuite / Regressionstest-System

**Spezifikation:** 1.2  
**Stand:** 25. August 2026  
**Runner:** `tests/kienzlefon-dialog-testsuite-v1.2.6.py`  
**Szenarien:** KF-001 bis KF-150

## Änderung gegenüber 1.1

- Operative Zielruntime ist Kienzlefon-AI-Runtime 2.0.
- System-Prompt und Kanalregel werden weiterhin ausschließlich von der Runtime übernommen, sind aber keine getrennt versionierten Produktartefakte mehr.
- Das kanonische Paket enthält 150 statt 50 synthetische Szenarien.
- Die Tests umfassen zusätzlich Notfälle, Palliativsituationen, Angehörige, Organisationsanfragen, Beschwerden, Fehl-/Scherzanrufe, Apotheken, Pflegeheime und Pflegedienste.
- `caller_role` und `urgency` des 2.0-Schemas werden als Runtime-Rohantwort bewahrt; die lokale Suite trifft weiterhin keine semantische Bewertung.
- Version 1.2.6 setzt den Qwen-Standardsprecher passend zur Runtime 2.0 auf `uncle_fu`; alle übrigen Funktionen von 1.2.5 bleiben erhalten.

## 1. Ziel

Ein lokales LLM simuliert einen Patienten oder externen Anrufer und führt einen interaktiven Dialog mit der echten lokalen Textschnittstelle der Kienzlefon-Runtime. Der Testtreiber darf die Kienzlefon-Fachlogik nicht nachimplementieren.

Geprüft werden technische Verträge:

- Sessions und Kanäle,
- exakte HTTP-/JSON-Antwortkörper,
- terminaler Zustand und Hangup,
- Multi-Order-Erhalt,
- flüchtige Records,
- Fehler- und Turn-Limits,
- private Artefakte und unveränderliche Bundles.

Eine lokale semantische, medizinische oder fachliche PASS-/FAIL-Bewertung findet nicht statt. Dafür wird ein später extern auswertbares Bundle erzeugt.

## 2. Architektur

```text
scenario.yaml
      │
      ▼
Patienten-/Anrufersimulator mit eigenem LLM-Kontext
      │ nur Patiententext
      ▼
echte Kienzlefon Runtime 2.0 / lokale Text-API
      │ reply, raw_response, state, records
      ▼
Recorder
      ├─ transcript.md
      ├─ events.jsonl
      ├─ records.json
      ├─ technical_validation.json
      └─ evaluation_bundle.*
```

Patientensimulator und Kienzlefon besitzen getrennte Kontexte und Systemanweisungen.

Der Simulator sieht nur:

- synthetische Patienten-/Anruferdaten,
- für die Simulation nötige Umgebung,
- Kanal,
- letzte Kienzlefon-Antwort.

Er sieht niemals:

- `test_goal`,
- `expectations`,
- `channel_overrides`,
- erwartete Records oder JSON-Werte.

## 3. Runtimevertrag

Die Text-API ist lokal unter `127.0.0.1:8300` erreichbar. Testsessions verwenden standardmäßig:

```text
recording_mode=ephemeral
```

Sie erzeugen keine Produktivaufträge. Persistenter manueller Chat mit `recording_mode=spool` gehört zum Produkt, nicht zum normalen Regressionstestlauf.

`complete=true` beendet kein Gespräch. Es kennzeichnet genau einen vollständigen Auftrag. Weitere Aufträge, Korrekturen und Rückfragen bleiben möglich. Terminal wird ausschließlich durch die Runtime, einen simulierten Hangup, das harte Turn-Limit oder einen technischen Fehler bestimmt.

Telefon und Chat sind getrennte Runs. `telephone` kann Handoff-Wünsche als nicht ausgeführtes Ergebnis darstellen; `chat` darf keine technische Rufweiterleitung behaupten oder ausführen.

## 4. Prompt- und Kanalgrundlage

Die Runtime liefert den tatsächlich aktiven System-Prompt und die aktive Kanalregel. Genau diese Texte werden in den privaten Run kopiert und gehasht.

Es gibt keine:

- separate Promptversion,
- separate Overlayversion,
- Freigabedatei,
- Bytegleichheitsblockade gegen eine Repository-Referenz,
- Sperre bei manuell geänderter Runtime-Konfiguration.

Die Kopie dokumentiert ausschließlich, womit der konkrete Run tatsächlich ausgeführt wurde. Integritätsprüfungen des Szenariopakets und abgeschlossener Run-Artefakte bleiben verbindlich.

## 5. Szenariopaket

Kanonisches Verzeichnis:

`tests/kienzlefon-testsuite-spec-v1/`

Es enthält:

- JSON Schema Draft 2020-12,
- Index und Manifest,
- Simulator-Basisprompt,
- externe Evaluatoranweisung,
- 150 synthetische YAML-Szenarien KF-001 bis KF-150.

Das Szenarioformat bleibt 1.0. Die Erweiterung KF-051 bis KF-150 ändert das Format nicht.

Schwerpunkte:

- Rezept, Überweisung, Termin, Rückruf, freie Anliegen,
- mehrere Aufträge und Korrekturen,
- Telefon-/Chatunterschiede,
- akute Notfälle und Palliativsituationen,
- Angehörige und abweichende Anruferidentität,
- Ärzte, Krankenhäuser, Rettungsdienst und Notarzt,
- Apotheken, Pflegeheime und Pflegedienste,
- organisatorische und geschäftliche externe Anrufe,
- Beschwerden, Fehl-, Scherz- und Testanrufe.

Alle Identitäten und Inhalte sind synthetisch.

## 6. Artefakte und Datenschutz

Run-Verzeichnisse erhalten Modus 0700, Dateien Modus 0600. Normale Konsolenausgaben enthalten keine Dialoginhalte.

Je Szenario werden unter anderem gespeichert:

- unverändertes `scenario.yaml`,
- kompletter synthetischer Dialog,
- exakte Runtime-Rohantworten,
- Zustands- und Record-Snapshots,
- technische Validierung,
- tatsächlich verwendete Runtime-Anweisungen,
- Simulatorprompt und Modellmetadaten.

Diese ausführlichen Inhalte sind ausschließlich für bestätigte synthetische Testdaten zulässig. Ein abgeschlossener Ursprungs-Run wird beim späteren Bundleexport vor und nach dem Export gehasht und nicht verändert.

## 7. Ausführung

Voraussetzungen:

- Python 3.11 oder neuer,
- PyYAML und JSON Schema gemäß Requirements-Datei,
- laufende Runtime 2.0 auf Port 8300,
- lokaler OpenAI-kompatibler Simulatorendpunkt,
- ausdrückliche Bestätigung synthetischer Daten.

Beispiele:

```bash
python3 tests/kienzlefon-dialog-testsuite-v1.2.6.py \
  --validate-only \
  --channel telephone

python3 tests/kienzlefon-dialog-testsuite-v1.2.6.py \
  --channel telephone \
  --scenario KF-001 \
  --max-parallel 1 \
  --confirm-synthetic-test-data

python3 tests/kienzlefon-dialog-testsuite-v1.2.6.py \
  --channel chat \
  --max-parallel 1 \
  --confirm-synthetic-test-data
```

Der Standard für Parallelität bleibt 1. `--show-dialog` ist nur bei einem einzelnen synthetischen Lauf und `--max-parallel 1` zulässig.

## 8. Exitcodes und Nachweisgrenze

- 0: technische Ausführung oder Validierung erfolgreich
- 1: mindestens ein technisch fehlgeschlagenes Szenario
- 2: Konfigurations-, Abhängigkeits-, Transport- oder Vertragsfehler
- 3: unerwarteter interner Fehler ohne Dialogausgabe
- 130: Benutzerabbruch

Exitcode 0 ist kein semantischer, medizinischer, dialogischer oder Hardware-End-to-End-Qualitätsnachweis.
