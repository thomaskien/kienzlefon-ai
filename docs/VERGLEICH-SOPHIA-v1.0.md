# Kienzlefon AI und IONOS / Sophia – vorhandene Testergebnisse

[Zur README](../README.md) · Dokumentationsstand: 30. September 2026

Die vorhandenen Läufe decken dieselben 150 synthetischen Szenariodefinitionen ab. **Eine abgeschlossene vergleichende Bewertung der Dialog- oder Stimmqualität ist im gefundenen Material nicht enthalten.** Die technische Auswertung liegt vor; beide Manifeste melden die inhaltliche Bewertung ausdrücklich als `NOT_PERFORMED`. Die folgende Übersicht trennt diese Nachweise.

## Kompakter Vergleich

| Merkmal | Kienzlefon AI | IONOS / Sophia |
|---|---|---|
| Testdatum | 22.08.2026 | 14.09.2026 |
| Geprüfter Stand | Backend 1.9.9, Qwen3.5-9B | Externes Sophia-Telefonziel; Produkt-/Modellversion nicht ausgewiesen |
| Testweg | Text-API mit Telefon-Dialogregeln, ohne ASR/TTS/SIP | Sprachtest über Telefonie und Audio, einschließlich Test-TTS und Rücktranskription |
| Testsuite | 1.0.3 | 1.2.0 |
| Ausgeführt | 150 von 150 | 150 von 150 |
| Technisch bestanden | **147 (98,0 %)** | **83 (55,3 %)** |
| Technisch fehlgeschlagen | **3 (2,0 %)** | **67 (44,7 %)** |
| Fehlergruppen | 3 × Gesprächslimit von 20 Patientenbeiträgen erreicht | 61 × Sprachtransportfehler; 6 × Gesprächslimit von 24 Patientenbeiträgen erreicht |
| Inhaltliche Gesamtbewertung | Nicht durchgeführt laut Manifest | Nicht durchgeführt laut Manifest |
| Vergleichende Hörbewertung | Nicht enthalten | Nicht enthalten |

Die beiden Quoten messen die technischen Erfolgskriterien des jeweiligen Runners. Sie ergeben **keine vergleichbare Qualitätsnote und keinen belegten Qualitätsvorsprung**: Nur der Sophia-Lauf umfasst den fehleranfälligen Telefon-/Audiopfad. Außerdem unterscheiden sich Testsuite, Gesprächslimits, Zeitlimits und Testdatum. Die Quoten dürfen nicht als „98 % gegenüber 55 % Dialogqualität“ dargestellt werden.

## Einordnung der Fehler und des vorhandenen Qualitätsbefunds

Im Kienzlefon-Lauf scheiterten drei Szenarien am Gesprächslimit. Auch ein technischer PASS bestätigt noch nicht, dass alle fachlichen Erwartungen eines Szenarios erfüllt wurden. Die Manifeste und Einzelvalidierungen enthalten keine abschließende semantische Benotung.

Die 61 Sophia-Sprachtransportfehler bestehen aus 58 geschlossenen Medienverbindungen, zwei vor der Antwortmarkierung geschlossenen Verbindungen und einem Zeitablauf beim Warten auf die Rufannahme. Die Ursache kann anhand dieser Zähler nicht pauschal Sophia oder IONOS zugeordnet werden; Testaufbau, Telefonieroute und Zielverhalten sind beteiligt. Die weiteren sechs Fehlschläge betreffen das Gesprächslimit.

Ein **separater Sophia-Einzellauf KF-001 vom 14. September** wurde bereits inhaltlich nachgeprüft. Dieser Vorlauf ist nicht mit der Gesamtbewertung des späteren 150er-Laufs gleichzusetzen:

| Prüfaspekt der Rezeptbestellung | Vorhandener Befund |
|---|---|
| Name, vollständiges Geburtsdatum, Medikament und Stärke | Im Gespräch erhoben; ein zunächst unvollständiges Geburtsdatum wurde nachgefragt |
| Weitere Bestellwünsche vor Abschluss klären | Abweichung vom Testsoll: Speicherung wurde bereits bestätigt, bevor weitere Wünsche abgefragt waren |
| Tatsächlich vollständiger gespeicherter Auftrag | In diesem Einzelreview nicht prüfbar; dort lagen keine zugeordneten externen Auftragsdaten vor |

Das Einzelreview beruht auf dem rücktranskribierten Gespräch. Es liefert einen konkreten inhaltlichen Befund, aber keine belastbare Gesamtquote und keine vergleichende Beurteilung der Stimme. Separat vorhandene Sophia-Exportdateien müssten für eine Gesamtbewertung den jeweiligen Szenarien verlässlich zugeordnet und geprüft werden.

## Auswahl und Nachvollziehbarkeit

Als Kienzlefon-Referenz wurde der zeitlich letzte lokal vorliegende vollständige 150er-Lauf ausgewählt, nicht der Lauf mit der höchsten Erfolgsquote. Der Sophia-Vergleich verwendet den vorhandenen vollständigen 150er-Lauf. Die früheren Kienzlefon-Läufe sind Entwicklungsstände und werden nicht zu einer gemeinsamen Erfolgsquote vermischt.

Für beide ausgewählten Läufe wurden die Ergebniszeilen nachgezählt und gegen die Manifestzusammenfassungen geprüft. Die 150 Szenario-IDs, Quelldatei-Prüfsummen und Simulator-Seeds stimmen überein. Gleiche Szenariodefinitionen garantieren bei dynamischen Dialogen weder dieselben tatsächlichen Äußerungen noch identische Testbedingungen. Beide Manifeste weisen ausschließlich synthetische Testdaten aus.

Interne Quellen, die für diese Übersicht gelesen wurden:

- `runs/20260822_115925Z_telephone_651354af/manifest.json` sowie das zugehörige `bundle/evaluation_bundle.json` mit Einzelvalidierungen.
- `sophia-runs/20260914_133457Z_sophia_all_D41D890D/manifest.json` sowie das zugehörige `bundle/evaluation_bundle.json` mit Einzelvalidierungen.
- `sophia-runs/20260914_133457Z_sophia_all_D41D890D.verification.json`: 150 ausgewählte und ausgeführte Szenarien; Manifest verifiziert, technische Fehler, keine semantische Bewertung.
- `runs/20260914_124253Z_voice_9d278ab6/evaluations/LEAD-REVIEW.md`: vorhandenes inhaltliches KF-001-Einzelreview.

Manifest-Prüfsummen (SHA-256):

```text
43ff841cd5ee33993989f6c2a1635d3ee9aa4c9bb89601d55c9587fb1dc2831b  Kienzlefon-Referenzmanifest
ff82a59f13b1fc8e2872e19bfb7c7b6665841d852b8f55bf7d86d64d3bb6c1d2  Sophia-Referenzmanifest
```

Diese öffentliche Übersicht enthält keine Rohtranskripte, Audiodateien, Rufnummern oder Zugangsdaten. Interne Quellen sind zur Nachvollziehbarkeit benannt und gehören nicht automatisch zur Veröffentlichungsauswahl.

Für einen abgeschlossenen Qualitätsvergleich fehlen eine einheitliche Bewertung der fachlichen Erwartungen, die Prüfung der tatsächlich gespeicherten Aufträge und eine gesonderte Hörbewertung. Die historischen Ergebnisse sind außerdem keine Abnahme der aktuellen Kienzlefon-Runtime 2.5.x. In dieser Dokumentationsarbeit wurden keine neuen Testanrufe oder Hardwaretests ausgeführt.
