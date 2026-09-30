# Architektur und Schnittstellen – Version 2.5.1

[Zur README](../README.md) · Stand: 28. September 2026

## Zuständigkeiten

| Komponente | Verantwortet | Voraussetzung / Grenze |
|---|---|---|
| CUDA-Serverinstaller | Residente Dienste für LLM, ASR, Qwen-TTS und optional Pyannote | Ubuntu/NVIDIA/CUDA; keine SIP-, VAD- oder Dialoglogik |
| Asterisk-Backendinstaller | Dedizierter Asterisk, drei Telefonagenten, VAD, Dialog, Chat, Kapazität und Handoff | Vorhandene KI-Endpunkte und Kienzlefon-Verträge; keine KI-Modell- oder CUDA-Installation |
| Kienzlefon / Haupt-Asterisk | Anrufverteilung, Admission-/Handoff-Gegenstelle, vorhandene Spool-/Ausgabeverarbeitung | Separat eingerichtete, kompatible Kienzlefon-Umgebung |
| Piper | Bereits vorhandene Ausweich-Sprachausgabe | Vom KI-Serverinstaller nur auf Erreichbarkeit geprüft |
| Pyannote | Optionaler eigenständiger Dienst zur Sprechertrennung | Kein Teil der Kern-ASR und kein zweites Whisper |

Prompt, Telefonoverlay, Chatoverlay und Chat-Client sind Bestandteile der Backendruntime. Ihre operative Version ist 2.5.1; sie werden nicht als unabhängige aktuelle Komponenten zusammengestellt.

## KI-Profil

| Rolle | Festgelegtes Profil |
|---|---|
| LLM | Qwen3.5-9B, GGUF Q6_K, llama.cpp `b9637`, drei Slots, Gesamtkontext 131072 Token, Q8_0 für K/V, Flash Attention, Continuous Batching, Thinking aus |
| ASR | Genau eine residente WhisperLiveKit-/Whisper-`large-v3`-Instanz, Faster-Whisper/CUDA, SimulStreaming, Deutsch, Beam 1 |
| Qwen-TTS | `Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice`, CUDA/INT8, vier Threads, Batch 1, Sprecher `uncle_fu`, Sprache `German` |
| Pyannote | `pyannote/speaker-diarization-community-1`, CUDA/PyTorch, neutrale Sprecherkennungen |

Das LLM-Modell liegt einmal resident im Server. Drei Slots teilen sich den Gesamtkontext; 131072 Token sind nicht der Kontext pro Gespräch. Die Dialogruntime verwaltet voneinander getrennte Gesprächszustände.

LLM-Datei: `Qwen_Qwen3.5-9B-Q6_K.gguf`, erwartete Größe 7.958.818.848 Byte, SHA-256:

```text
073a9275e65d9c8cd2819cf5f77b99fbaa6e87ba591da6bbaa86ec073a64bfef
```

Der native Qwen-TTS-Build ist auf Commit `328ab9cb241774572bb59917af199bdf64a17227` festgelegt. Jede CUDA-Rolle erhält eine stabile NVIDIA-GPU-UUID. Mehrere Rollen dürfen dieselbe GPU verwenden; daraus folgt keine garantierte Speicherauslastung oder Parallelleistung. Keine dieser Rollen fällt still auf CPU-Verarbeitung zurück.

## Standardports

Die Tabelle beschreibt das vorgesehene lokale bzw. geschützte Netz. Sie ist keine Aufforderung, diese Ports im Internet freizugeben.

| Port | Dienst / Schnittstelle | Verwendung |
|---|---|---|
| 8080/TCP | LLM, `/v1/chat/completions` | Dialoganfragen; OpenAI-kompatible API |
| 8178/TCP | `kienzlefon-asr-v1`, `/v1/asr/stream` | Einziger ASR-Einstieg für Kienzlefon, WebSocket |
| 8179/TCP | WhisperLiveKit-Backend | Intern hinter dem ASR-Gateway |
| 8181/TCP | Piper, `/v1/audio/speech` | Bereits vorhandener Pflicht-Fallback |
| 8182/TCP | Qwen-TTS, `/v1/tts/stream` | Primäre Sprachausgabe |
| 8183/TCP | Pyannote, `/v1/diarize` | Nur bei Auswahl der optionalen Rolle |
| 8290–8292/TCP | AudioSocket der drei Telefonagenten | Lokal auf `127.0.0.1` |
| 8300/TCP | Text-API, `/v1/dialog/sessions` | Lokaler Chat / direkte Tests, `127.0.0.1` |
| 8190/TCP | Admission-Listener am Hauptsystem | Verbindung des Kapazitätspublishers zum Hauptsystem |
| 5060/UDP | SIP, Standardregistrar und Backendtransport | Geschütztes Telefonienetz; RTP-Bereich separat nach Asterisk-Konfiguration |

LLM und ASR-Gateway verwenden standardmäßig `127.0.0.1`. Pyannote hat seit 2.5.1 einen eigenen Standard `0.0.0.0:8183`, sofern kein eigener Bestandswert existiert. Es besitzt keine HTTP-Authentifizierung; der Hugging-Face-Token schützt ausschließlich den Modellzugang. Bei getrennten Hosts müssen Zieladressen und Netzfreigaben geplant und auf vertrauenswürdige Rechner begrenzt werden. Der Installer verändert keine Firewallregeln.

## Telefonablauf

1. Hauptsystem und Kapazitätspublisher vermitteln einen verfügbaren Telefonplatz. Die Runtime prüft den Admission-Vertrag vor Annahme.
2. Asterisk liefert AudioSocket-PCM S16LE mit 16 kHz, mono, an den zuständigen Agenten. G.722 ist das Breitbandprofil, G.711 ein Telefonie-Fallback.
3. VAD sammelt eine vollständige Äußerung; Standard-Sprachendeschweigen: 500 ms.
4. Erst nach dem Endpunkt geht die Äußerung an das ASR-Gateway. Nach dem finalen Transkript beginnt genau eine endgültige LLM-Anfrage.
5. Schema und Dialogzustand werden geprüft. Qwen liefert Antwortaudio mit nativ 24 kHz, das für den Telefonpfad auf 16 kHz umgesetzt wird. Piper ist der TTS-Fallback.
6. Vollständige Aufträge werden gemäß dem Kienzlefon-Vertrag idempotent an die vorhandene Spool-/Ausgabeverarbeitung übergeben. Ein vollständiger Auftrag beendet nicht automatisch das Gespräch.

2.5.1 verwendet Half-Duplex ohne Barge-in. `streaming_asr` und `speculative_llm` sind in dieser Runtime deaktiviert und werden beim Update auf `false` migriert. SimulStreaming bezeichnet weiterhin das Verfahren im ASR-Dienst, keine aktivierbare Liveübertragung der Telefonruntime.

Warteansagen und Pieptöne laufen parallel zur Verarbeitung. Sie ändern weder den finalen ASR-Vertrag noch den Zeitpunkt, ab dem echtes Antwortaudio gemessen wird. Details stehen in [Betrieb und Konfiguration](BETRIEB-v2.5.1.md).

## Chat und Speicherung

Die Text-API unterstützt Telefon-Testkanäle und Chat. Chat führt keine telefonische Weiterleitung aus. Testsitzungen sind standardmäßig flüchtig; ausdrücklich als `recording_mode=spool` angelegte Chats können vollständige Aufträge an die Produkt-Spool übergeben. Der manuelle Befehl `kienzlefon-chat` dient der persistenten Chatnutzung und ist kein folgenloser Healthcheck.

Inhaltsfreie technische Logs bedeuten nicht, dass das Gesamtsystem keinerlei Patientendaten speichert: Die fachlich vorgesehene Auftragsausgabe enthält die erfassten Angaben. Konfiguration, Spool, Ausgabe, Debugzugriff und Sicherungen benötigen deshalb eigene Zugriffsbeschränkungen. Sie gehören nicht in GitHub.

## Quellen der Implementierung

Diese Beschreibung wurde mit dem [KI-Serverinstaller 2.5.1](../installer/install-kienzlefon-ai_v2.5.1.sh), dem [Backendinstaller 2.5.1](../installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh) und dem lokalen Projekt-/Validierungsstand abgeglichen. Sie beschreibt den vorhandenen Entwurf; den tatsächlichen Abnahmestand führt [Tests und Validierung](TESTS-v2.5.1.md).
