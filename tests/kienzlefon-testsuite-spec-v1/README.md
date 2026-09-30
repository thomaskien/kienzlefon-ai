# Kienzlefon Testsuite – Spezifikation und 150 Beispielszenarien

Inhalt:
- `CODEX_HANDOFF.md` – Systemdesign und Implementierungsübergabe
- `FORMAT_SPEC.md` – YAML-Formatspezifikation
- `schemas/scenario.schema.json` – JSON Schema Draft 2020-12
- `templates/patient-simulator-system.txt` – Basisprompt für den lokalen Patienten-Simulator
- `templates/external-evaluator-instructions.md` – Startpunkt für die spätere ChatGPT-Auswertung
- `scenarios/` – 150 synthetische Beispielpatienten-/Anruferszenarien plus `index.json`

Alle 150 YAML-Dateien wurden beim Erstellen gegen das Schema validiert.

Wichtig: `expectations` werden niemals an das Patienten-LLM gegeben. Sie dienen dem Testtreiber und der späteren externen Auswertung.
