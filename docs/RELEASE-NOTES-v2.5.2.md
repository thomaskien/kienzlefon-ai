# Release Notes 2.5.2

Stand: 30. September 2026. Lokal implementiert und isoliert getestet, nicht auf dem Server aktiviert.

Die Standardstartzeiten der drei Füllansagen ändern sich auf 5000/11000/17000 ms. Mit den ausgewählten statischen Clips hört man damit fünf Pieptöne vor „Bitte warten.“ und danach drei weitere vor „Ich verarbeite.“. Die dritte Ansage wird entsprechend mitverschoben. Eine fertige Antwort beendet weitere Warteausgabe weiterhin sofort nach einem bereits laufenden Ton/Block.

Vorhandene explizite TOML-Zeiten bleiben erhalten. Zur Übernahme der neuen Folge in eine bestehende `[filler]`-Sektion `part1_start_ms = 5000`, `part2_start_ms = 11000` und `part3_start_ms = 17000` eintragen. Ein später gesondert freigegebener Reload genügt bei vorhandener Runtime ab 2.5; die Sprachclips müssen nicht neu generiert werden. Kein KI-Serverupdate nötig.

Der KI-Installer 2.5.2 ist ausschließlich versionsangepasst. Die Dateien 2.5.1 bleiben unverändert, ebenso der unabhängige AMD-Zweig. Die [Dokumentation 2.5.1](RELEASE-NOTES-v2.5.1.md) gilt außerhalb dieses Deltas weiter.

Syntax, Hilfe/Version und beide vollständigen Selbsttests bestanden; zusätzliche Tests prüfen die genaue Standardfolge mit virtuellem Zeitlauf und den Erhalt vorhandener Konfiguration. Keine neue Hardware-/Hörabnahme. Details und Grenzen: [Integrationsspezifikation 2.5.2](spezifikationen/SPEZIFIKATION-KIENZLEFON-AI-INTEGRATION-v2.5.2.md).
