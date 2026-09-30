# Kienzlefon-AI-Integration 2.5.2 – spätere Standardansagen

Stand: 30. September 2026. Ausgang: `installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh`.
Neue Datei: `installer/kienzlefon-installer-asterisk-backend-v2.5.2.sh`.

## Delta

Die Standardstartzeiten werden von 2000/7000/13000 ms auf **5000/11000/17000 ms** geändert. Die Werte gelten einheitlich im TOML-Renderer, Runtime-Konfigurationsparser, Datenmodell und Wiedergabe-Fallback. Texte, ausgewählte Sprachclips, Seed, Tonhöhe, Lautstärke, Tonlänge und Sekundenraster bleiben unverändert.

Mit den vorhandenen Seed-12345-Clips (2,24 / 3,28 / 2,24 s) ergibt sich bei weiterhin laufender Berechnung:

- Pieptöne bei 0, 1, 2, 3 und 4 s; „Bitte warten.“ beginnt bei 5 s und endet etwa bei 7,24 s.
- Drei weitere Pieptöne bei 8, 9 und 10 s; „Ich verarbeite.“ beginnt bei 11 s und endet etwa bei 14,28 s.
- Pieptöne bei 15 und 16 s; die dritte Ansage „Bitte warten.“ beginnt bei 17 s. Ihr bisheriger Abstand zur zweiten Ansage bleibt erhalten.

Alle Zeiten beziehen sich auf das erkannte VAD-Sprachende. Es bleibt eine absolute Zeitplanung, kein neuer Piepton-Zählmodus. Andere Ansagetexte, Clipdauern, Tonintervalle oder stark verzögerte Verarbeitung können die tatsächlich hörbare Anzahl verändern. Während Sprache ausgefallene Pieptöne werden weiterhin nicht nachgeholt.

Eine früher fertige echte Antwort hat weiterhin Vorrang: kein Warten auf fünf oder drei vollständige Pieptöne, kein zusätzlicher Füllblock. Nur ein bereits laufender Block/Ton wird beendet; Auflegen bricht ab. ASR/LLM/TTS-Berechnung läuft wie bisher parallel zum Wartefeedback.

## Bestehende Konfiguration

Vorhandene explizite TOML-Werte bleiben beim Update erhalten, auch die bisherigen Standardzeiten. Fehlende Schlüssel erhalten die neuen Defaults. Für eine vorhandene Konfiguration diese drei Werte in der bestehenden `[filler]`-Sektion ändern, nicht eine zweite Sektion anhängen:

```toml
part1_start_ms = 5000
part2_start_ms = 11000
part3_start_ms = 17000
```

Für die beschriebene Folge gelten unverändert `beep_enabled = true`, `beep_start_ms = 0`, `beep_interval_ms = 1000` und die ausgewählten Clips. Reine Zeitänderungen erfordern keine neue Sprachsynthese. Eine bereits vorhandene Runtime 2.5 unterstützt diese Zeiten; dafür ist kein KI-Serverupdate nötig. Änderungen und Reload auf dem laufenden Server sind separat freizugeben und wurden hier nicht ausgeführt.

Alle übrigen Verträge aus `docs/spezifikationen/SPEZIFIKATION-KIENZLEFON-AI-INTEGRATION-v2.5.md` und `docs/spezifikationen/SPEZIFIKATION-KIENZLEFON-AI-INTEGRATION-v2.5.1.md` bleiben bestehen. Das KI-Installergegenstück 2.5.2 unterscheidet sich ausschließlich durch Versionsangaben von 2.5.1. Bestätigte 2.5.1-Dateien und Audioassets bleiben unverändert.

## Prüfung

Beide Installer: Shellsyntax, Version, Hilfe und vollständige isolierte Selbsttests. Backend mit Asyncio-Debug und Warnungen als Fehler. Ergänzt: virtueller Zeitlauf des tatsächlichen Wiedergabeplaners mit den ausgewählten Clipdauern, exakt fünf/drei Pieptöne, Startzeiten 5/11/17 s und vorzeitiges Ende bei Antwortbereitschaft. Renderer/Parser-Defaults und Erhalt alter expliziter Zeiten über Einlesen und erneutes Rendern geprüft. Bestehende Tests für Audioframes, Antwortübergang, Auflegen, parallele Wiedergabe, Cache, Reload und Rückabwicklung bleiben enthalten.

Die PCM-Dateigrößen entsprechen 2,24/3,28/2,24 s bei 16 kHz/S16LE/mono. Keine neue TTS-Anfrage, kein Hardware-/Telefon-Hörtest und keine Serveraktivierung. Aktuelle Installerprüfsummen stehen in `STATUS.md`.
