# Lizenzprüfung: konkrete AMD-Hinweislücken geschlossen

[Zur README](../README.md) · [Vollständige Lizenztexte und Herkunft](lizenzen/README.md) · Stand: 30. September 2026

**Die beiden im Prüfbericht 1.0 festgestellten Hinweislücken sind mit AMD-Installer 1.0.2 behoben.** Die eigene MIT-Projektlizenz bleibt bestehen; Fremdkomponenten behalten ihre ursprünglichen Lizenzbedingungen. Die Korrektur wurde ausdrücklich freigegeben und als neue Version umgesetzt.

| Befund aus 1.0.1 | Umsetzung und Nachweis in 1.0.2 |
|---|---|
| Fehlender bzw. unvollständiger Änderungshinweis in zwei nativen TTS-Dateien | Beide Dateien beginnen mit Herkunft, Änderungsverantwortlichem und Beschreibung der Anpassungen; ursprünglicher Apache-2.0-Text bleibt unverändert |
| Ergänzende Fremdlizenzen fehlten bei Weitergabe nur der Installerdatei | Neun vollständige Texte, Quellen-/Hashverzeichnis, Projektlizenz und Herkunftshinweise sind nun direkt im eingebetteten Paket enthalten und durch dessen Manifest erfasst |

Das originale WhisperLiveKit-Wheel ist unverändert. Die Begleittexte stehen daneben im umschließenden Paket und werden auch bei einer normalen Installation in das Release übernommen. Die Änderungen an den beiden C++-Dateien beschränken sich auf zusätzliche Kommentare; Programmlogik, Modelle, Abhängigkeiten und Netzdefaults bleiben unverändert. Details: [Release Notes 1.0.2](RELEASE-NOTES-AMD-v1.0.2.md).

## Umfang der abgeschlossenen Prüfung

Installer-SHA-256: `3058e464e274a20169459c9eb15aa5a994227ea744547e89779bef9afe482a9e`. Das eingebettete Paket enthält 38 Dateien, einschließlich der neun bytegleich aus [docs/lizenzen](lizenzen/README.md) übernommenen Fremdlizenztexte. Vollständige Manifestabdeckung, Quellhashes, unverändertes Wheel und reproduzierbarer Build sind geprüft. Syntax, Version/Hilfe, Plan und **71 lokale Selbsttests** bestanden. Diese Prüfungen sind keine neue GPU-/Telefonieabnahme.

Der [ursprüngliche Prüfbericht 1.0](LIZENZPRUEFUNG-2026-09-30-v1.0.md) bleibt als Nachweis der Untersuchung erhalten. Er enthält die Primärquellen zu den Hauptkomponenten und Modellen, die Einordnung von SimulStreaming unter MIT sowie die Abgrenzung von Bibliotheks- und Modelllizenzen. Seine Aussagen „Korrektur noch offen“ und „1.0.2 noch nicht erstellt“ beschreiben den Stand vor dieser Umsetzung. Die dortigen Grenzen, insbesondere keine vollständige Inventur sämtlicher nachgeladenen Abhängigkeiten, gelten weiter.

Für die konkret festgestellten Hinweislücken besteht damit kein offener Umsetzungspunkt mehr. Ein Containerimage, ein Export installierter Modellgewichte oder geänderte Abhängigkeitspins wären ein anderer Verteilungsumfang und sind durch diese Prüfung nicht abgedeckt. Die [Veröffentlichungsauswahl 1.7](VEROEFFENTLICHUNG-2026-09-30-v1.7.md) verwendet ausschließlich den neuen AMD-Installer; die alte 1.0.1-Datei bleibt lokal.

## Betreiberentscheidungen und Veröffentlichung

Der persönliche Hugging-Face-Token war laut Betreiber niemals öffentlich; es wird keine Offenlegung oder daraus folgende Rotationspflicht behauptet. Token und sämtliche Hörproben bleiben vom Upload ausgeschlossen. Private Snapshot-, Migrations- und Hörprobenarchive wurden für diese Korrektur nicht untersucht.

Die bestätigte CUDA-Pyannote-Bindung für berechtigte Praxisrechner bleibt unverändert. Betriebs- und Netzgrenzen stehen in [SECURITY.md](../SECURITY.md). Die abschließende Prüfung des tatsächlich zusammengestellten Uploadkandidaten und seiner Git-Historie ist weiterhin ein Veröffentlichungsschritt. Es wurden weder Commit noch Push ausgeführt.
