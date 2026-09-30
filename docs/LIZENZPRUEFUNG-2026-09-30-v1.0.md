# Lizenzprüfung vor Veröffentlichung

[Zur README](../README.md) · [Lizenztexte und Herkunft](lizenzen/README.md) · Stand: 30. September 2026

## Ergebnis

Die eigene MIT-Projektlizenz kann bestehen bleiben. Für die untersuchten Hauptkomponenten wurde keine grundsätzliche Unvereinbarkeit mit einer Veröffentlichung des eigenen Codes unter MIT festgestellt. Fremdcode bleibt jedoch unter seinen ursprünglichen Bedingungen. **Der unveränderte AMD-Installer 1.0.1 ist wegen der unten genannten Verpackungs- und Hinweislücken noch nicht abschließend zur Veröffentlichung freigegeben.**

Die Prüfung erfolgte auf ausdrücklichen Benutzerauftrag auch innerhalb des eingebetteten ZIP-Pakets und des darin enthaltenen Wheels. Sie betraf ausschließlich den vorgesehenen Veröffentlichungskandidaten; private Snapshot-, Migrations- und Hörprobenarchive wurden nicht untersucht. Keine Installation, Ausführung des Installers, Modellinferenz oder Veröffentlichung erfolgte.

## Tatsächlich mitgelieferter Inhalt

Geprüft wurde `7900XTX/install-kienzlefon-ai-amd-v1.0.1.sh` mit SHA-256 `f88342823e5ecc4ae956cbd81c0aee12664213c0221dd884ef358db9985ddcfc`. Das eingebettete ZIP enthält 25 Dateien; seine Prüfsumme lautet `d2884f41341bdbdbe14f74bcf8a9d1ec40b13d53d9dd09bef9fc83de817b10ee`. Alle 25 Inhalte stimmen mit dem lokalen Quellverzeichnis des Installers überein.

| Mitgelieferter Fremdanteil | Nachweis | Ergebnis |
|---|---|---|
| Native TTS aus qingming-qwen3-tts | Commit `66b85b1e3b1d2cf6f927c6c8c8b23e48ed66e2ac`; gepinnter Git-Dateibaum und lokale Originaldateien abgeglichen | Apache-2.0; vollständige, unveränderte Lizenz im Paket vorhanden |
| WhisperLiveKit-Wheel 0.2.24 | SHA-256 `f11ff4c74f3efe11d09b50a08cfd6c33ed74fed4a397429d70254ada3feeeda6`, identisch mit dem veröffentlichten PyPI-Wheel; 118 enthaltene Dateien | Apache-2.0-Lizenz mit Herkunftsanhang vorhanden; bytegleich zum Tag `v0.2.24` |
| Whisper-Codekopie innerhalb des Wheels | Verzeichnis `whisperlivekit/whisper/` | Ergänzender MIT-Volltext von OpenAI erforderlich; als Begleitdatei ergänzt |
| Silero-VAD-Code und vier VAD-Modelldateien im Wheel | Herkunftshinweis auf Silero v6; Dateien unter `silero_vad_models/` | MIT; ergänzender Volltext des Herstellers als Begleitdatei ergänzt |
| Weitere von WhisperLiveKit genannte Grundlagen | SimulWhisper, SimulStreaming, NeMo, whisper_streaming und Diart im Lizenzanhang | Zugehörige Apache-/MIT-Texte und Quellen als Begleitdateien ergänzt |

Quellen: [qingming-Lizenz am verwendeten Commit](https://github.com/uulong950/qingming-qwen3-tts/blob/66b85b1e3b1d2cf6f927c6c8c8b23e48ed66e2ac/LICENSE), [WhisperLiveKit-Lizenz 0.2.24](https://github.com/QuentinFuxa/WhisperLiveKit/blob/v0.2.24/LICENSE), [PyPI-Dateinachweis](https://pypi.org/project/whisperlivekit/0.2.24/#files), [Whisper-Lizenz](https://github.com/openai/whisper/blob/main/LICENSE), [Silero-v6-Lizenz](https://github.com/snakers4/silero-vad/blob/v6.0/LICENSE).

Die pauschale frühere Aussage, dass keine Modellgewichte mitgeliefert werden, ist zu präzisieren: Große LLM-, Whisper-, Qwen-TTS- und Diarisierungsgewichte werden separat geladen; das mitgelieferte WhisperLiveKit-Wheel enthält bereits kleine Silero-VAD-Modelle. In den Dateilisten des ZIPs und Wheels wurden keine Hörprobendateien mit den üblichen Audioendungen gefunden. Diese Dateilistenprüfung ist keine vollständige Geheimnis- oder Audiofreiheitsprüfung beliebiger codierter Inhalte.

## Zwei konkrete Hinweislücken im AMD-Paket

**1. Änderungshinweis in der nativen TTS-Quelle.** Gegenüber dem bestätigten Upstream sind `native-tts/main.cpp` und `native-tts/devices/rx7900xtx-24g/qwen3_tts_0_6b.cpp` geändert. `main.cpp` enthält keinen ausdrücklichen Hinweis auf diese Änderungen. Die zweite Datei enthält einen älteren Instrumentierungskommentar, der die späteren Profil- und Allocatoranpassungen nicht vollständig beschreibt. `CMakeLists.txt`, `device.h` und `LICENSE` sind unverändert; die hinzugefügte Allocator-Hilfsdatei ist im Quellmanifest verzeichnet.

Apache 2.0 Abschnitt 4(b) verlangt erkennbare Änderungshinweise in veränderten Dateien. Deshalb sollen beide geänderten Quellen einen kurzen Kopfkommentar mit Herkunft, Änderungsverantwortlichem und Art der Änderungen erhalten. Das vorhandene externe Quellmanifest allein ersetzt den Hinweis in `main.cpp` nicht. Ein zusätzliches Upstream-`NOTICE` wurde im gepinnten qingming-Dateibaum nicht gefunden. [Apache 2.0, Abschnitt 4](https://www.apache.org/licenses/LICENSE-2.0#redistribution).

**2. Vollständige Hinweise auch bei Einzelweitergabe.** Das unveränderte WhisperLiveKit-Wheel enthält nur seine kombinierte Apache-Lizenzdatei, aber keine separaten vollständigen MIT-Texte für beispielsweise die enthaltene Whisper-Kopie und Silero VAD. Die [ergänzten Lizenzdateien](lizenzen/README.md) schließen diese Dokumentationslücke für das Repository als Gesamtpaket. Bei einer allein weitergegebenen AMD-Installerdatei wären die neuen Begleittexte jedoch nicht dabei. Sie müssen deshalb in einer neuen Installerfassung mitgeführt werden. Das Originalwheel kann dabei unverändert und mit seiner geprüften Prüfsumme erhalten bleiben; ergänzende Hinweise gehören daneben in das umschließende Paket.

## SimulStreaming: ältere Nichtkommerziell-Hinweise eingeordnet

Ältere Veröffentlichungen nennen eine PolyForm-Noncommercial-/kommerzielle Doppellizenz. Die offizielle Lizenz wurde am **22. Oktober 2025** auf MIT geändert; die aktuelle Datei entspricht diesem Änderungsstand. Das verwendete WhisperLiveKit 0.2.24 erschien danach und nennt SimulStreaming ausdrücklich unter MIT. Aus diesen älteren Hinweisen ergibt sich daher für den hier geprüften Stand kein belegter Bedarf einer gesonderten kommerziellen SimulStreaming-Lizenz. [Offizieller Lizenzwechsel](https://github.com/ufal/SimulStreaming/commit/0f63d3793ce3a0dcc026aade36e2fea82d573037), [MIT-Lizenztext](https://github.com/ufal/SimulStreaming/blob/0f63d3793ce3a0dcc026aade36e2fea82d573037/LICENCE.txt).

Die PyPI-Klassifikation von WhisperLiveKit 0.2.24 nennt noch MIT, während der tatsächlich ausgelieferte Lizenztext und der zugehörige Git-Tag Apache 2.0 ausweisen. Diese Inkonsistenz wurde nicht durch eine pauschale MIT-Zuordnung übergangen: Die vollständige ausgelieferte Apache-Lizenz und die Bedingungen der Unterkomponenten bleiben erhalten.

## Separat heruntergeladene Hauptkomponenten und Modelle

| Komponente | Lizenznachweis | Einordnung |
|---|---|---|
| llama.cpp, AMD-Commit `aedb2a5…` / CUDA-Referenz b9637 | [MIT](https://github.com/ggml-org/llama.cpp/blob/aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3/LICENSE) | Quellcode wird bei Installation geladen und gebaut |
| CUDA-Qwen-TTS von Gabriele Mastrapasqua, Commit `328ab9c…` | [MIT](https://github.com/gabriele-mastrapasqua/qwen3-tts/blob/328ab9cb241774572bb59917af199bdf64a17227/LICENSE) | Eigenständiges Projekt; nicht mit der nativen AMD-TTS gleichsetzen |
| CTranslate2 4.8.2 / faster-whisper 1.2.1 | [MIT bei CTranslate2](https://github.com/OpenNMT/CTranslate2/blob/v4.8.2/LICENSE), [MIT bei faster-whisper](https://github.com/SYSTRAN/faster-whisper/blob/v1.2.1/LICENSE) | Externe Installationsabhängigkeiten |
| TorchCodec, Commit `6df7fc8…` | [BSD-3-Clause](https://github.com/pytorch/torchcodec/blob/6df7fc8e81c9509e86833ca48695609c583e2953/LICENSE) | Wird separat gebaut |
| Qwen3.5-9B / Bartowski Q6_K-GGUF | [Apache-2.0 laut verwendeter Modellkarte](https://huggingface.co/bartowski/Qwen_Qwen3.5-9B-GGUF/blob/2dcd842/README.md) | Modellgewichte nicht im Veröffentlichungspaket |
| Whisper large-v3 / Faster-Whisper-Konvertierung | [MIT laut Modellkarte](https://huggingface.co/Systran/faster-whisper-large-v3/blob/edaa852ec7e145841d8ffdb056a99866b5f0a478/README.md) | Gewichte werden separat geladen |
| Qwen3-TTS 0.6B CustomVoice | [Apache-2.0 laut gepinnter Modellkarte](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice/blob/85e237c12c027371202489a0ec509ded67b5e4b5/README.md) | Große TTS-Gewichte werden separat geladen |
| pyannote.audio 4.0.7 | [MIT](https://github.com/pyannote/pyannote-audio/blob/4.0.7/LICENSE) | Bibliothekslizenz getrennt vom Modell |
| speaker-diarization-community-1 | [CC-BY-4.0 und Zugangsbedingungen auf der offiziellen Modellseite](https://huggingface.co/pyannote/speaker-diarization-community-1) | Eigene Modellfreigabe und persönlicher Token des jeweiligen Betreibers erforderlich; kein mitgelieferter Zugang |

Die öffentliche Pyannote-Modellkarte war lesbar; der direkte Abruf der gepinnten README ohne Anmeldung wurde mit HTTP 401 abgewiesen. Dafür wurde kein persönlicher Token verwendet. Die Modelllizenz wurde anhand der öffentlichen Anbieterseite eingeordnet. Für einen späteren Export installierter Gewichte sind die zugehörigen Dateien und Namensnennungen gesondert mitzunehmen.

Die Tabelle bewertet die vorgesehenen Hauptkomponenten. Sie ist keine vollständige Lizenzinventur aller nachgeladenen Python-, GPU-, Medien- und Betriebssystempakete. Solche Pakete werden mit der Veröffentlichung der Installerquellen nicht automatisch mitverteilt. Änderungen der Pins, ein Containerimage oder ein Komplettarchiv des installierten Systems benötigen eine eigene Prüfung.

## Konkrete Korrektur für einen neuen AMD-Veröffentlichungsstand

Ausgang: bestätigter AMD-Installer **1.0.1** mit dem oben genannten Hash. Vorschlag: neue Datei `7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh` und separates Quellverzeichnis `7900XTX/amd-installer-v1.0.2/`; 1.0.1 bleibt unverändert.

Das Delta soll ausschließlich die Versionsfortführung, zwei Kopfkommentare in den geänderten TTS-Dateien, eine Herkunfts-/Änderungsübersicht, die ergänzenden Lizenztexte sowie aktualisierte Paket-/Manifestprüfsummen umfassen. Modelle, Rechenpfade, Dienstkonfiguration, Netzbindung, Defaults und das originale WhisperLiveKit-Wheel bleiben unverändert. Diese reine Verpackungskorrektur ist vorbereitet und beschrieben, aber noch nicht umgesetzt.

Prüfplan: Diff auf dieses Delta begrenzen; Programmcode der TTS-Dateien nach Entfernen der neuen Kommentare bytegleich vergleichen; alle übrigen nicht versionsabhängigen Nutzdateien und das Wheel per Hash abgleichen. Paketmanifest, enthaltene Lizenztexte und vollständige Dateiauswahl prüfen. Danach `--version`, `--help` und `--self-test` des neuen AMD-Installers ausführen; die Ergebnisse als lokale Prüfungen ausweisen. Keine Installation oder erneute Hardwareabnahme für diesen Dokumentationsauftrag.

## Erledigte Betreiberentscheidungen

Der persönliche Hugging-Face-Token war laut ausdrücklicher Bestätigung des Betreibers niemals öffentlich. Die lokale Snapshotkopie wird nicht als offengelegter Token behandelt; eine Rotation wird daraus nicht verlangt. Token und Hörproben bleiben vom Upload ausgeschlossen.

Die CUDA-Pyannote-Netzbindung ist vom Betreiber bestätigt und für den Zugriff berechtigter Praxisrechner erforderlich. Sie bleibt bestehen; Zugriffsschutz im Praxisnetz und fehlende HTTP-Authentifizierung sind in [SECURITY.md](../SECURITY.md) dokumentiert.
