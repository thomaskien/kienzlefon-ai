# Kienzlefon Testszenario-Format v1.0

Dateiformat: UTF-8 YAML, eine Datei pro Szenario.
Schema: `schemas/scenario.schema.json`.

## Top-Level

```yaml
format_version: "1.0"
scenario_id: "KF-001"
title: "Rezept – ein Medikament"
description: "Kurzer Zweck des Tests"
enabled: true
channels: [telephone, chat]
tags: [rezept, happy-path]

simulation:
  max_turns: 20
  seed: 1001

patient:
  identity:
    first_name: "Hans"
    last_name: "Meier"
    birth_date: "12.03.1957"
    callback_number: null
  persona:
    style: "kurz und freundlich"
    disclosure: "nur_auf_nachfrage"
    quirks: []
  facts:
    medications: ["Ramipril 5 mg"]
  opening: "Guten Tag, ich wollte ein Rezept bestellen."
  instructions:
    - "Nenne persönliche Daten nur auf Nachfrage."
    - "Wenn nach weiteren Medikamenten gefragt wird, verneine."

environment:
  caller_id: "+4917610000001"
  within_phone_hours: false

test_goal:
  topic: "Rezeptbestellung"
  clarification_goal: "Ein Medikament vollständig aufnehmen."

expectations:
  terminal_outcome: "order_complete"
  records:
    - type: "rezeptbestellung"
      complete: true
      data:
        vorname: {equals: "Hans"}
        nachname: {equals: "Meier"}
        geburtsdatum: {equals: "12.03.1957"}
        medikamente: {contains_lines: ["Ramipril 5 mg"]}
  required_behaviors:
    - "Rezept erst nach Klärung weiterer Bestellwünsche abschließen."
  forbidden_behaviors:
    - "Bekannte Stammdaten unnötig erneut abfragen."
  notes: []

channel_overrides:
  chat:
    terminal_outcome: null
    required_behaviors: []
    forbidden_behaviors:
      - "Eine reale Rufweiterleitung behaupten."
```

## Semantik

### `channels`
Kanäle, für die das Szenario grundsätzlich geeignet ist. v1 kennt `telephone` und `chat`.

### `simulation.max_turns`
Harte Schleifenbegrenzung. Wird sie erreicht, endet der Test mit technischem Status `max_turns_reached`.

### `simulation.seed`
Seed für den Patienten-Simulator, soweit das lokale Backend deterministische Seeds unterstützt. Er muss im Run-Manifest erneut protokolliert werden.

### `patient.identity`
Synthetische Identität. Felder dürfen `null` sein. `callback_number` ist eine bewusst angesagte Nummer und nicht mit `environment.caller_id` zu verwechseln.

### `patient.persona.disclosure`
Freier, aber standardisierter Hinweis für den Patienten-Simulator. Empfohlene Werte in v1:
- `nur_auf_nachfrage`
- `teilweise_spontan`
- `alles_spontan`
- `zurueckhaltend`

Der Runner soll hier keine harte Fachlogik implementieren; der Text steuert den Patienten-Prompt.

### `patient.facts`
Beliebiges YAML-Objekt mit den **wahren, geheimen Fakten des simulierten Patienten**. Diese Fakten sind kein erwartetes Kienzlefon-JSON-Schema, sondern Input für das Patienten-LLM.

### `patient.opening`
Erste wörtliche bzw. sinngemäß sehr eng einzuhaltende Patientenäußerung.

### `patient.instructions`
Geheime Regieanweisungen. Beispiele:
- Information erst auf Nachfrage geben
- zunächst falsches Datum sagen und später korrigieren
- nach Abschluss eines Rezepts ein zweites Anliegen beginnen
- `SIMULATE_HANGUP` ausführen

**Diese Liste darf dem Kienzlefon-LLM nicht zugänglich gemacht werden.**

### `environment.caller_id`
Simulierte übermittelte Rufnummer. `null` bedeutet keine Rufnummernübermittlung. Das Feld gehört zur Testumgebung/Backend-Session und soll nicht als Patiententext vorgegeben werden.

### `environment.within_phone_hours`
Simulierte Telefonzeit. Dient Tests von kanal-/zeitabhängigen Pfaden, soweit das Backend dies unterstützt.

### `test_goal`
Menschenlesbarer Zweck des Testfalls. Wird im externen Evaluation-Bundle mitgegeben.

### `expectations`
Kein lokaler semantischer Pass/Fail-Zwang. Die Struktur dient vor allem dem späteren großen Evaluator und optional einfachen deterministischen Checks.

`terminal_outcome` ist ein frei erweiterbarer String. Empfohlene Werte:
- `order_complete`
- `multiple_orders_complete`
- `no_order`
- `forward_immediately`
- `callback_offered`
- `message_recorded`
- `incomplete_after_hangup`
- `conversation_end`
- `contact_instruction`

### `expectations.records`
Erwartete auftragsbezogene Datensätze. Leere Liste bedeutet: Es soll kein normaler Auftrag erzeugt werden.

Ein Record-Matcher:
```yaml
- type: rezeptbestellung
  complete: true
  data:
    geburtsdatum: {equals: "12.03.1957"}
    medikamente:
      contains_lines:
        - "Ramipril 5 mg"
```

Matcher v1:
- `{equals: <scalar>}`
- `{contains: <string>}`
- `{contains_lines: [<string>, ...]}`
- `{one_of: [<scalar>, ...]}`
- `{present: true|false}`

Der externe Evaluator darf sinnvoller/semantischer urteilen als diese Matcher.

### `required_behaviors` / `forbidden_behaviors`
Natürliche Sprache, ausdrücklich für die externe qualitative Auswertung. Nicht versuchen, diese Regeln lokal per Keyword-Suche als Wahrheit zu bewerten.

### `channel_overrides`
Überschreibt nur die genannten Erwartungsfelder für einen Kanal. Nicht genannte Felder werden aus `expectations` geerbt.

Beispiel Krankenhaus:
```yaml
expectations:
  terminal_outcome: forward_immediately
  records: []
channel_overrides:
  chat:
    terminal_outcome: contact_instruction
    required_behaviors:
      - "Geeignete Kontakt-/Anrufanweisung statt Weiterleitung geben."
    forbidden_behaviors:
      - "Behaupten, jetzt tatsächlich weiterzuleiten."
```

## Sicherheit gegen Test-Leakage
Dem Patienten-LLM nur `patient`, `environment` soweit nötig, Kanal und letzte Assistant-Antwort geben. `test_goal`, `expectations` und `channel_overrides` niemals in dessen Prompt einbauen.

## Erweiterbarkeit
Unbekannte zusätzliche Felder sollen in v1 vom Loader möglichst toleriert werden; das Schema erlaubt deshalb Erweiterungen. Pflichtfelder und Kerntypen bleiben aber validierbar.
