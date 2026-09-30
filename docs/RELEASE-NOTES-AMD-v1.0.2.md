# AMD-Installer 1.0.2: Lizenzhinweise vollständig mitführen

[Zur README](../README.md) · [Installationsanleitung](AMD-INSTALLATION-v1.0.2.md) · Stand: 30. September 2026

Der [AMD-Installer 1.0.2](../7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh) schließt die zwei konkreten Hinweislücken aus der Lizenzprüfung: Die geänderten nativen TTS-Dateien tragen nun erkennbare Änderungshinweise, und auch eine einzeln weitergegebene Installerdatei enthält sämtliche ergänzten Fremdlizenztexte. Die Vorgängerversion 1.0.1 bleibt lokal unverändert erhalten und ist aus der aktuellen Veröffentlichungsauswahl entfernt.

## Genaues Delta gegenüber 1.0.1

| Bestandteil | Änderung |
|---|---|
| Versionsangabe | `1.0.1` → `1.0.2`; Modell- und Abhängigkeitspins unverändert |
| `native-tts/main.cpp` | Kopfkommentar nennt Herkunft, Verantwortlichen und WGP-Anpassungen |
| `native-tts/devices/rx7900xtx-24g/qwen3_tts_0_6b.cpp` | Kopfkommentar beschreibt PCM-Ausgabe, HIP-Allocator und Frame-/WGP-Profile |
| Begleittexte im Paket | MIT-Projektlizenz, zwei Herkunfts-/Änderungsübersichten, neun vollständige Fremdlizenzen und Quellenverzeichnis ergänzt |
| Integrität | Beide geänderten Quellhashes, Paketmanifest und eingebettete ZIP-Prüfsumme aktualisiert |

Nach Entfernen der neuen Kopfkommentare sind beide C++-Dateien bytegleich zu 1.0.1. Alle anderen bestehenden Nutzdateien sind unverändert, ausgenommen Versionsangabe und die beiden Manifeste. Das originale WhisperLiveKit-Wheel, Builder, Tests, Dienstkonfiguration, Netzdefaults und Modelleinstellungen bleiben identisch. Das neue Paket umfasst 38 Dateien statt 25; das Quellverzeichnis liegt getrennt unter `7900XTX/amd-installer-v1.0.2/`.

## Prüfung und Grenzen

- Shell- und Python-Syntax, `--version`, `--help` und Vier-Rollen-Plan erfolgreich geprüft.
- **71 lokale Selbsttests bestanden**, ohne übersprungene Tests. Der erste Sandboxlauf übersprang die HTTP-Testklasse wegen gesperrter Loopback-Verbindungen; die vollständige Wiederholung mit erlaubten lokalen Testverbindungen bestand auf macOS/Python 3.14.6.
- Alle 38 Paketdateien mit der neuen Quelle abgeglichen; vollständige Manifestabdeckung, native Quellhashes, alle neun Lizenztexte und unverändertes Originalwheel bestätigt.
- Erneuter Build in einem temporären Quellverzeichnis erzeugt bytegleich dieselbe Installerdatei.
- Bestätigte 1.0.1-Quellen und bisherige Installer unverändert; keine neue Installation, Modellinferenz oder Dienst-/Hardwareänderung.

Die [XTX-Messungen](BENCHMARK-XTX-v1.0.md) und die dort genannten 71 Ubuntu-/XTX-Selbsttests gehören weiterhin zu **1.0.1**. Die lokale Prüfung von 1.0.2 ist keine erneute Hardware-, Telefonie- oder Hörabnahme. Bestehende Dienste müssen für diese Lizenzkorrektur nicht neu installiert werden.

## Prüfsummen

```text
3058e464e274a20169459c9eb15aa5a994227ea744547e89779bef9afe482a9e  install-kienzlefon-ai-amd-v1.0.2.sh
792b825516210bc96d682625e58c204f09b70419a54cf3740213d0657f4e6e7d  eingebettetes ZIP
f11ff4c74f3efe11d09b50a08cfd6c33ed74fed4a397429d70254ada3feeeda6  whisperlivekit-0.2.24-py3-none-any.whl
```

[Abschluss der Lizenzkorrektur](LIZENZPRUEFUNG-2026-09-30-v1.1.md) · [Aktuelle Veröffentlichungsauswahl](VEROEFFENTLICHUNG-2026-09-30-v1.7.md). Hugging-Face-Token und sämtliche Hörproben bleiben ausgeschlossen; nichts wurde hochgeladen.
