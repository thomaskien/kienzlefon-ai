# Lizenztexte der mitgelieferten Fremdkomponenten

[Zur Projektübersicht](../../README.md) · [Prüfbericht](../LIZENZPRUEFUNG-2026-09-30-v1.1.md) · Stand: 30. September 2026

Die MIT-Projektlizenz gilt für den eigenen Kienzlefon-Code. Die hier aufgeführten Fremdanteile behalten ihre jeweiligen Lizenzen und Copyright-Hinweise. Die Texte wurden unverändert aus den angegebenen Originalquellen übernommen. [Quellen und Prüfsummen](QUELLEN.json) dokumentieren den Abgleich.

| Komponente | Lizenz | Volltext und Herkunft |
|---|---|---|
| qingming-qwen3-tts | Apache-2.0 | [qingming-qwen3-tts-LICENSE.txt](qingming-qwen3-tts-LICENSE.txt) · [Quelle](https://github.com/uulong950/qingming-qwen3-tts/blob/66b85b1e3b1d2cf6f927c6c8c8b23e48ed66e2ac/LICENSE) |
| WhisperLiveKit 0.2.24 | Apache-2.0 mit Herkunftshinweisen | [WhisperLiveKit-0.2.24-LICENSE.txt](WhisperLiveKit-0.2.24-LICENSE.txt) · [Quelle](https://github.com/QuentinFuxa/WhisperLiveKit/blob/v0.2.24/LICENSE) |
| OpenAI Whisper | MIT | [Whisper-LICENSE.txt](Whisper-LICENSE.txt) · [Quelle](https://github.com/openai/whisper/blob/main/LICENSE) |
| Silero VAD v6 | MIT | [Silero-VAD-v6-LICENSE.txt](Silero-VAD-v6-LICENSE.txt) · [Quelle](https://github.com/snakers4/silero-vad/blob/v6.0/LICENSE) |
| SimulStreaming | MIT | [SimulStreaming-LICENCE.txt](SimulStreaming-LICENCE.txt) · [Quelle](https://github.com/ufal/SimulStreaming/blob/0f63d3793ce3a0dcc026aade36e2fea82d573037/LICENCE.txt) |
| whisper_streaming | MIT | [Whisper-Streaming-LICENSE.txt](Whisper-Streaming-LICENSE.txt) · [Quelle](https://github.com/ufal/whisper_streaming/blob/main/LICENSE) |
| SimulWhisper | Apache-2.0 | [SimulWhisper-LICENSE.txt](SimulWhisper-LICENSE.txt) · [Quelle](https://github.com/backspacetg/simul_whisper/blob/ffeb3ff333026f29053d01c95a1a0524f2a41865/LICENSE.txt) |
| NeMo | Apache-2.0 | [NeMo-LICENSE.txt](NeMo-LICENSE.txt) · [Quelle](https://github.com/NVIDIA-NeMo/NeMo/blob/main/LICENSE) |
| Diart | MIT | [Diart-LICENSE.txt](Diart-LICENSE.txt) · [Quelle](https://github.com/juanmc2005/diart/blob/main/LICENSE) |

WhisperLiveKit 0.2.24 führt SimulWhisper, SimulStreaming, NeMo, whisper_streaming, Silero VAD und Diart in seinem eigenen Lizenzanhang auf. Zusätzlich enthält das Wheel eine Whisper-Codekopie sowie vier Silero-VAD-Modelldateien. Die Ergänzungen bewahren die Fremdhinweise; sie ersetzen nicht die vorhandene WhisperLiveKit-Lizenz. Der dort enthaltene SimulWhisper-Link verweist auf SimulStreaming; oben ist zusätzlich die tatsächliche SimulWhisper-Quelle angegeben.

Die Begleittexte sind zusammen mit dem Repository zu verteilen. AMD-Installer 1.0.2 enthält alle neun Volltexte und das Quellenverzeichnis zusätzlich bytegleich in seinem eigenen Paket. Damit bleiben sie bei Einzelweitergabe des Installers enthalten. Die beiden geänderten nativen TTS-Dateien tragen nun ausdrückliche Änderungshinweise. Die konkrete Korrektur ist abgeschlossen; das Originalwheel und der Installer 1.0.1 bleiben unverändert.

Nur bei der Installation heruntergeladene Software und große LLM-/ASR-/TTS-/Diarisierungsmodelle sind gesondert im Prüfbericht aufgeführt. Diese Sammlung ist keine vollständige Lizenzinventur aller transitiven Betriebssystem- und Python-Abhängigkeiten.
