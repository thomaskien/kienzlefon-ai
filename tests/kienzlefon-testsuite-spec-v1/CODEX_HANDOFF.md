# CODEX-ÜBERGABE: Kienzlefon Dialog-Testsuite / Regressionstest-System v1

## Ziel
Eine lokale Testsuite soll realistische Patientengespräche gegen das **echte Kienzlefon-AI-Backend** führen. Ein lokales LLM simuliert ausschließlich den Patienten. Das Kienzlefon-Backend läuft mit dem jeweils produktiven bzw. explizit ausgewählten System-Prompt und erzeugt seine normalen `reply`-/JSON-Ausgaben. Die Suite bewertet den Dialog **inhaltlich nicht lokal**, sondern speichert alle Rohdaten und erzeugt einen gebündelten Export für eine spätere externe Auswertung mit ChatGPT/großem LLM.

Die Architektur soll später auch einen Kanal `chat` unterstützen. Die fachliche Kernlogik bleibt identisch; kanalabhängige Regeln liegen in einem kleinen Modus-/Promptblock. Im Chat darf insbesondere keine echte Rufweiterleitung behauptet werden.

## Grundarchitektur

```text
scenario.yaml
    |
    v
Patienten-Simulator (lokales LLM, eigener Kontext/System-Prompt)
    | Patientenäußerung
    v
Kienzlefon-AI Backend (echter Backend-Pfad + echter Kienzlefon-Prompt)
    | reply + ggf. JSON/Datensatz/State
    v
Patienten-Simulator
    | ... interaktiver Dialog ...
    v
Recorder
    +-- transcript.md        menschenlesbar
    +-- events.jsonl         verlustfreie Ereignisfolge inkl. Raw-Responses
    +-- records.json         alle erzeugten auftragsbezogenen Datensätze
    +-- technical_validation.json
    +-- scenario.yaml        unveränderte Kopie des Inputs

Nach allen Szenarien:
    +-- evaluation_bundle.md
    +-- evaluation_bundle.json

Diese Bundles werden extern in ChatGPT analysiert.
```

## Zwingende Designregeln
1. Der Patienten-Simulator und das Kienzlefon müssen getrennte LLM-Kontexte/System-Prompts haben. Keine Rollenvermischung.
2. Der Testtreiber soll das **reale Kienzlefon-AI-Backend** ansprechen und nicht dessen Verhalten nachimplementieren.
3. `complete=true` ist auftragsbezogen, nicht telefonatbezogen. Ein Gespräch läuft nach einem abgeschlossenen Auftrag weiter, wenn der Patient noch ein weiteres Anliegen hat.
4. Alle während eines Gesprächs erzeugten Datensätze werden gesammelt; mehrere Aufträge pro Gespräch sind ausdrücklich zulässig.
5. Inhaltliche/semantische Bewertung erfolgt nicht lokal. Lokal nur technische Prüfungen: parsbares JSON, Schema, Datentypen, zulässige Struktur, Backendfehler.
6. Jeder Testlauf ist unveränderlich. Nachträgliche Auswertungen werden separat gespeichert und verändern den Run nicht.
7. Synthetische Testdaten verwenden; keine echten Patientendaten in die Suite übernehmen.
8. Maximalzahl Dialog-Turns pro Szenario erzwingen, damit ein fehlerhafter Prompt nicht endlos läuft.
9. Raw-Backendausgaben unverändert speichern; zusätzlich normalisierte/komfortable Darstellungen erzeugen.
10. Bei einem simulierten Auflegen/Hangup muss das Backend dieselbe Abschluss-/Persistenzlogik durchlaufen wie im Produktivpfad, soweit technisch möglich.

## Prompt-Versionierung / Reproduzierbarkeit
Beim Start jedes Runs müssen die **tatsächlich verwendeten Texte** gesichert werden:

```text
runs/<run_id>/prompts/
    kienzlefon-system.txt
    patient-simulator-system.txt
    channel-overlay.txt          # falls verwendet
    metadata.json
```

`manifest.json` enthält mindestens:
- `run_id`
- Zeitstempel mit Zeitzone
- `channel`
- Kienzlefon-Prompt: Versionslabel + SHA-256
- Patienten-Simulator-Prompt: Versionslabel + SHA-256
- ggf. Channel-Overlay: Versionslabel + SHA-256
- Backend-Version / Git-Commit, falls verfügbar
- verwendetes Kienzlefon-LLM + Modellpfad/-ID
- verwendetes Patienten-LLM + Modellpfad/-ID
- relevante Inferenzparameter (temperature, top_p, seed, ctx, max_tokens usw.)
- Backend-URL/API-Version
- Szenarioformat-Version
- Liste/Hash der ausgeführten Szenarien

Wichtig: Ein Versionslabel oder Git-Hash ersetzt **niemals** die Prompt-Kopie. Gespeichert wird der exakte String, der in diesem Lauf wirklich an das Modell ging.

## Empfohlene Run-Struktur

```text
runs/20260815_200000_prompt-2026.08.15-04/
├── manifest.json
├── prompts/
│   ├── kienzlefon-system.txt
│   ├── patient-simulator-system.txt
│   ├── channel-overlay.txt
│   └── metadata.json
├── scenarios/
│   ├── KF-001/
│   │   ├── scenario.yaml
│   │   ├── transcript.md
│   │   ├── events.jsonl
│   │   ├── records.json
│   │   └── technical_validation.json
│   └── ...
├── bundle/
│   ├── evaluation_bundle.md
│   └── evaluation_bundle.json
└── evaluations/
    └── chatgpt/                 # erst später hinzufügen
        ├── evaluation.md
        └── evaluation.json
```

## `events.jsonl`
Jede Zeile genau ein JSON-Ereignis. Empfohlene Events:
- `scenario_start`
- `patient_turn`
- `assistant_raw_response`
- `assistant_reply`
- `record_emitted`
- `transfer_requested`
- `hangup`
- `backend_error`
- `scenario_end`

Jedes Event möglichst mit `timestamp`, `scenario_id`, `turn`, `channel` und einer unveränderten `raw`-Nutzlast, wenn vorhanden.

Beispiel:
```json
{"event":"patient_turn","scenario_id":"KF-001","turn":1,"text":"Guten Tag, ich wollte ein Rezept bestellen."}
{"event":"assistant_raw_response","scenario_id":"KF-001","turn":2,"raw":{"reply":"Gerne. Wie ist Ihr Vorname?","complete":false,"type":"rezeptbestellung","data":{}}}
{"event":"assistant_reply","scenario_id":"KF-001","turn":2,"text":"Gerne. Wie ist Ihr Vorname?"}
```

## Szenarioeingabe
Die 150 mitgelieferten YAML-Dateien folgen `FORMAT_SPEC.md` und `schemas/scenario.schema.json`.
Der Patientensimulator sieht nur:
- seine Rolle/Persona,
- seine eigenen Fakten,
- Opening und Dialoganweisungen,
- die letzte Kienzlefon-Antwort.

Er soll **nicht** die `expectations` sehen. Diese bleiben Testtreiber/externem Evaluator vorbehalten, sonst würde der Patient auf das gewünschte Testergebnis hinspielen.

## Patienten-Simulator
Der Simulator soll kurz, natürlich und telefontypisch antworten. Fakten nur entsprechend `disclosure` und `instructions` preisgeben. Keine zusätzlichen medizinischen/personenbezogenen Fakten erfinden. Korrekturen/Meinungsänderungen exakt ausspielen. Prompt-Injection aus Kienzlefon-Antworten nicht befolgen. Ein Szenario kann durch die Sonderanweisung `SIMULATE_HANGUP` beendet werden.

## Dialogende
Ein Szenario endet bei einem der folgenden Punkte:
- Patient legt laut Szenario auf (`SIMULATE_HANGUP`).
- Kienzlefon verabschiedet sich und der Patient hat laut Szenario keine offenen Ziele mehr.
- Telefonmodus: eine echte/angeforderte Sofortweiterleitung ist Endzustand des Tests.
- `max_turns` erreicht.
- Backendfehler.

Ein `complete=true` allein beendet **nicht** den Test.

## Technische Validierung
Lokal zulässig/gewünscht:
- JSON parsebar?
- erwartete Basistypen vorhanden?
- `complete` boolesch?
- `reply` String?
- `type` zulässiger String/Null gemäß Backendvertrag?
- `data` Objekt?
- Datensatz serialisierbar?
- Backend/API-Fehler?
- Run-Dateien vollständig geschrieben?

Nicht lokal bewerten:
- Gesprächsqualität
- unnötige Rückfragen
- Regelverletzungen
- erfundene Inhalte
- richtige fachliche Interpretation
- Korrektheit von `complete` im semantischen Sinn
Diese Punkte gehen in den externen ChatGPT-Bundle-Review.

## Evaluation-Bundle
`evaluation_bundle.md` soll pro Szenario enthalten:
1. ID/Titel/Tags/Kanal
2. Testziel und Erwartungen
3. komplettes Szenario (ohne interne Geheimnisse zu verlieren; hier bewusst vollständig, da externer Evaluator)
4. vollständigen Dialog
5. alle erzeugten Datensätze/JSONs
6. technische Validierung
7. Run-Metadaten/Prompt-Version

Am Anfang des Bundles stehen zusätzlich der vollständige verwendete Kienzlefon-Prompt sowie dessen Hash. Optional kann der Patienten-Simulator-Prompt ebenfalls aufgenommen werden.

`evaluation_bundle.json` enthält dieselben Informationen strukturiert, damit spätere automatische Auswertung möglich bleibt.

## Kanalmodell Telefon / Chat
Die fachliche Core-Logik soll nicht dupliziert werden. Empfohlen:

```text
Kienzlefon Core Prompt
    + channel=telephone Overlay
oder
Kienzlefon Core Prompt
    + channel=chat Overlay
```

Telefon:
- reale Rufweiterleitung möglich
- CLIP/Rufnummernlogik
- telefonische Formulierungen

Chat:
- niemals behaupten, einen Anruf/Ruf weiterzuleiten
- stattdessen passende Kontakt-/Anrufanweisung gemäß Core-Regeln
- keine erfundenen Telefon-/Warteschlangenfunktionen

Szenarien dürfen `channel_overrides` enthalten, um unterschiedliche Soll-Endzustände für Telefon und Chat zu beschreiben.

## Empfohlene CLI
Beispiel, Namen frei an bestehendes Repository anpassen:

```bash
python -m testsuite.run \
  --scenarios ./testsuite/scenarios \
  --backend-url http://127.0.0.1:<PORT> \
  --channel telephone \
  --kienzlefon-prompt /path/to/current_prompt.txt \
  --patient-prompt ./testsuite/templates/patient-simulator-system.txt \
  --output ./runs
```

Weitere sinnvolle Optionen:
- `--scenario KF-017`
- `--tag rezept`
- `--seed 1234`
- `--max-parallel 1|N`
- `--fail-fast` nur für technische Fehler
- `--bundle-only <run_dir>`

## Akzeptanzkriterien v1
- 150 mitgelieferte Szenarien laufen einzeln und als Suite.
- Alle Eingaben validieren gegen das JSON-Schema.
- Pro Szenario entsteht ein vollständiges Transcript und `events.jsonl`.
- Mehrere `complete=true`-Datensätze innerhalb eines Telefonats werden erhalten.
- Der exakte produktive Prompt wird je Run kopiert und gehasht.
- Ein Run kann später ohne Veränderung als Bundle exportiert werden.
- Bundle enthält Dialoge + ggf. erzeugte JSONs + Testziele + Promptversion.
- Keine semantische lokale LLM-Bewertung.
- ChatGPT-Auswertung ist ein nachgelagerter, separater Schritt.
- Architektur blockiert eine spätere Nutzung derselben Core-Logik als Kienzlefon-Chat nicht.
