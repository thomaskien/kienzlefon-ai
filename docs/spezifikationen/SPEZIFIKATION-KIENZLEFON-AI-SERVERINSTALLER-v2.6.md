# KI Serverinstaller 2.6

Fortführung von [2.5.2](SPEZIFIKATION-KIENZLEFON-AI-SERVERINSTALLER-v2.5.2.md). Die freigegebene TTS-Änderung ersetzt bei neuen Installationen Qwen als Standard durch Kokoro-Thorsten; vorhandene Entscheidungen haben Vorrang.

| Vertrag | 2.6 |
| --- | --- |
| Rollen | `llm`, `asr`, `tts`, optional `pyannote`, ausdrückliche Pyannote-Wahl bei `all` |
| Neue TTS-Auswahl | `--tts-engine kokoro`, alternativ `qwen` |
| Gerät | Kokoro `--tts-device cuda` oder ausdrücklich `cpu`; übrige Rollen CUDA |
| Kokoro | Thorsten, Epoch 5, fixierte Revision und SHA256 im Modellmanifest |
| Konfiguration | `/etc/kienzlefon-ai/kokoro.toml`; keine Telefonie-/SIP-Konfiguration |
| Port | Kokoro 8184, Qwen 8182; eigener Bestand/Option erhalten |
| GPU | stabile NVIDIA-UUID in systemd; dieselbe physische GPU für Torch und VRAM-Prüfung |
| Umgebung | eigene `kokoro-venv-v2.6`, für CPU `kokoro-venv-v2.6-cpu`; getrennte Lockdateien |
| Dienst | eine residente Instanz, begrenzte Parallelität, Health nach Warmup |
| Fallback | kein stiller CPU-/Qwen-Wechsel; Piper-Dienst nur lesend prüfen |
| Modellwechsel Telefon | ausschließlich Backend-Umschaltwerkzeug, keine Telefonielogik im KI-Installer |

Abhängigkeiten und Modelle werden vor dem Dienstdateiaustausch vorbereitet. Bestehende Modell-Dateien mit falschem Hash werden nicht still ersetzt. Fehler beim Austausch oder Warmup stellen veröffentlichte Runtime-/Konfigurations-/Unit-Dateien und den vorherigen Dienstzustand wieder her; neu vorbereitete Modell-/Umgebungsdateien bleiben zur Diagnose erhalten. Konkurrierende Datei- oder spätere Dienstzustandsänderungen werden nicht überschrieben; der Installer meldet dann eine notwendige manuelle Prüfung statt automatischer Rücksetzung.

Vollständige Bedienung, Pfade und Migrationsverhalten: [Installation 2.6](../INSTALLATION-v2.6.md). Nachweise: [Tests 2.6](../TESTS-v2.6.md).
