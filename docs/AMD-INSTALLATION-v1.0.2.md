# AMD-Installer 1.0.2: Einstieg und geprüfter Umfang

[Zur README](../README.md) · Stand: 30. September 2026

Der [eigenständige AMD-Installer 1.0.2](../7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh) ergänzt die Lizenz- und Änderungshinweise des auf RX 7900 XTX geprüften Vorgängers **1.0.1**. Programmlogik, Modell-/Abhängigkeitspins und Netzdefaults bleiben unverändert. **1.0.2 ist lokal paket- und selbsttestgeprüft, aber nicht erneut auf XTX installiert.** Die Hardwaremessungen stammen weiterhin aus 1.0.1.

Der Installer verwaltet ausschließlich KI-Dienste. Die spätere Telefonie-/Piper-Migration ist ein eigener Vorgang und keine Funktion dieses Installers. [Release Notes 1.0.2](RELEASE-NOTES-AMD-v1.0.2.md) beschreiben die Lizenzkorrektur; Ergebnisse und Grenzen der Hardwaretests stehen im [Benchmark- und Hardwarebericht](BENCHMARK-XTX-v1.0.md).

## Plattform und Abgrenzung

| Voraussetzung | Geprüfter bzw. erzwungener Stand |
|---|---|
| Betriebssystem | Ubuntu 24.04 x86_64, systemd, System-Python 3.12 |
| Kernel / GPU-Laufzeit | GA-Kernel `6.8.0-*`, vorhandene ROCm 7.2.4 unter `/opt/rocm-7.2.4`, funktionierendes `/dev/kfd` |
| GPU | Genau eine erkannte RX 7900 XTX / gfx1100; keine zusätzlich sichtbare iGPU |
| Speicherplatz | Mindestens 45 GiB frei unter `/opt` für den Installations-Preflight; weitere Releases/Sicherungen benötigen zusätzlichen Platz |
| Downloads | Zugriff auf festgelegte Quellen, Wheels und Modelle; passende lokale Modelle werden nur nach Hashprüfung wiederverwendet |
| Pyannote | Für erstmaligen Modelldownload Freigabe und Read-Token; vollständig passende vorhandene Modell-Dateien benötigen keinen neuen Downloadtoken |

Keine automatische Treiber-, ROCm-, Kernel-, BIOS- oder Netzänderung. Keine Framework-/gfx1151- oder Multi-GPU-Zusage. Die CUDA-2.x-Linie bleibt ein eigener Installerzweig; ihre Versionsnummer ist nicht die AMD-Versionsnummer.

## Rollen

| Rolle | Profil | Standardport |
|---|---|---:|
| `llm` | llama.cpp b9637/HIP, Qwen3.5-9B Q6_K, 3 Slots, Gesamtkontext 131072, Q8_0-K/V, Flash Attention, Thinking aus | 8080 |
| `asr` | Ein residenter WhisperLiveKit-/large-v3-Pfad, CT2-ROCm-Encoder und Torch/HIP-Decoder, Deutsch, Beam 1, SimulStreaming | 8178 |
| ASR intern | WhisperLiveKit 0.2.24, keine zweite ASR oder Diarisierung | 8179 |
| `tts` | Native HIP-Qwen3-TTS 0.6B CustomVoice, `uncle_fu`, German, PCM S16LE/24 kHz/mono mit Streaming | 8182 |
| `pyannote` | Optionale Community-1-Sprechertrennung, Segmentierung und Embedding auf GPU | 8183 |

`all` umfasst LLM, ASR und TTS; `--with-pyannote yes|no` muss ausdrücklich angegeben werden. Es gibt keinen stillen CPU-Inferenzfallback. CPU-Medienaufbereitung und Laden eines Checkpoints im Hauptspeicher sind davon zu unterscheiden.

Alle APIs binden standardmäßig an `127.0.0.1`, einschließlich Pyannote. **Der neue Pyannote-Wildcardstandard des CUDA-Installers 2.5.1 gilt nicht für diesen AMD-Installer.** Netzbindung erfordert eine ausdrückliche Adresse und `--allow-network`; die APIs besitzen keine eigene Authentifizierung oder TLS. Netzfreigaben werden hier nicht automatisch eingerichtet.

Die ASR spricht `kienzlefon-asr-v1` auf `/v1/asr/stream`. Sie ist kein WhisperDoku-Langdatei-/Batch-Dienst; der getrennt gemessene 3090-Endpunkt `/v1/asr/final-block` ist nicht enthalten. Piper auf 8181 muss separat bereitgestellt werden. Der AMD-Installer prüft nur seine Erreichbarkeit und verändert ihn nicht.

## Datei zunächst prüfen

Aus dem Repository-Hauptverzeichnis, ohne Installation:

```bash
bash 7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh --version
bash 7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh --help
bash 7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh --action plan --role all --with-pyannote yes
```

Auf der vorgesehenen Zielplattform zusätzlich:

```bash
bash 7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh --action preflight
```

Ohne Argumente wird ebenfalls nur ein Plan angezeigt. Der Preflight prüft Plattform und GPU; die vollständigen Download-, Build- und Portprüfungen erfolgen erst während `install`.

SHA-256 der lokal paket- und selbsttestgeprüften Version 1.0.2:

```text
3058e464e274a20169459c9eb15aa5a994227ea744547e89779bef9afe482a9e  install-kienzlefon-ai-amd-v1.0.2.sh
```

## Beabsichtigte Installation

Die folgenden Befehle verändern das Zielsystem und setzen eine bewusste Installationsentscheidung voraus. Sie wurden beim Aktualisieren dieser Dokumentation nicht ausgeführt.

Alle drei Kernrollen ohne Pyannote:

```bash
sudo bash 7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh \
  --action install --role all --with-pyannote no \
  --confirm-install --install-deps
```

Für Pyannote `--with-pyannote yes` verwenden und beim nötigen Erstdownload einen vorbereiteten root-privaten Token-Dateipfad über `--hf-token-file` angeben. Den Tokenwert nicht in einen Befehl oder eine Dokumentation schreiben. Die Datei muss regulär, root-eigen und höchstens für den Besitzer zugänglich sein. Der Installer kopiert den Token nicht in seinen Dienstzustand.

`--install-deps` erlaubt die fehlenden rollenspezifischen Build-/Medienpakete samt notwendigen Paketmanager-Abhängigkeiten. Es ist keine Freigabe für GPU-Treiber- oder ROCm-Installation. Ohne diesen Schalter werden fehlende Pakete gemeldet. Jeder Installationslauf erzeugt ein neues Release; ein erneuter Lauf ist kein schneller wirkungsloser Versionscheck.

## Betrieb

```bash
sudo bash 7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh --action status
sudo bash 7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh --action test --role tts
```

`test` prüft Health/Dienstzustand und ersetzt keinen Inferenzbenchmark. Die eigenen Units heißen:

```text
kienzlefon-ai-amd-llm.service
kienzlefon-ai-amd-asr-backend.service
kienzlefon-ai-amd-asr.service
kienzlefon-ai-amd-tts.service
kienzlefon-ai-amd-pyannote.service
```

Releases und Modelle liegen unter `/opt/kienzlefon-ai-amd/`, der private tokenfreie Zustand unter `/etc/kienzlefon-ai-amd/state.json`. Fremde Units oder belegte Ports werden nicht still übernommen. Ein Hardware-Uninstall und ein Boot der komplett migrierten Installation sind noch nicht abgenommen.

Der Lasttest belegte den verfügbaren GPU-Speicher fast vollständig. Die Installationsprüfung ist keine Kapazitätszusage für beliebig große gleichzeitig laufende Aufträge. Bei hoher Telefonielast Pyannote zeitlich getrennt betreiben oder ein geeignetes Speicherprofil gesondert prüfen.

## Telefonie und historischer Hardwareteststand 1.0.1

Auf dem geprüften XTX-System wurde nach der KI-Installation separat Runtime 2.5 samt Asterisk, Chat und Piper übernommen. Drei SIP-Konten und die Admission-Anbindung sind technisch geprüft; Runtime-TTS, Block-ASR, LLM, RAM-Spool-Test und flüchtiger Chat bestanden. Ein tatsächlicher Reload gelang nach Ergänzung des bei der Migration fehlenden privaten Rückfallzustands.

Die individuellen Migrationsskripte enthalten Annahmen über Quell- und Zielsystem und sind kein allgemeiner AMD-Telefonieinstaller. Die CUDA-Installationsanleitung darf nicht als AMD-Installationsbefehl übernommen werden. Für die gemeinsamen Dialog-/Wartefeedbackregeln kann die [Backend-Betriebsanleitung](BETRIEB-v2.5.1.md) herangezogen werden; sie dokumentiert die aus 2.5 unverändert fortgeführten Funktionen. Ihre Standangaben vom 28. September sind durch den aktuellen Hardwarebericht ergänzt.

## Lizenzen bei Weitergabe

Der einzelne Installer enthält die MIT-Projektlizenz, neun vollständige Fremdlizenztexte mit Herkunft und Prüfsummen sowie Hinweise auf die geänderten nativen TTS-Dateien. Die ursprünglichen Fremdlizenzen und das WhisperLiveKit-Wheel bleiben unverändert. Diese Begleittexte gehören bei einer Weitergabe des entpackten Quellpakets dazu; die vollständige Installerdatei führt sie bereits mit. Einzelheiten: [Lizenzprüfung 1.1](LIZENZPRUEFUNG-2026-09-30-v1.1.md).

Ein bestehender 1.0.1-Dienst benötigt wegen dieser Verpackungskorrektur keinen Neuinstallationslauf. Ein dennoch ausgeführtes `install` legt wie bisher ein neues Release an und ist eine gesonderte Systemänderung.
