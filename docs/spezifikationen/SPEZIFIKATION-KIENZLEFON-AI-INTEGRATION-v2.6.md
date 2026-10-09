# Telefonie Integration 2.6

Fortführung von [2.5.2](SPEZIFIKATION-KIENZLEFON-AI-INTEGRATION-v2.5.2.md). Die neue Runtime integriert Kokoro-Thorsten, die bestehende WAV-Erweiterung und G.722. Prompt, Telefonoverlay, Chatoverlay und Chat-Client bleiben Bestandteile derselben Runtime-Version.

Die Telefonie arbeitet weiterhin blockweise und ohne Barge-in. ASR erhält die gesammelte Äußerung nach dem VAD-Endpunkt, das LLM ausschließlich den finalen Text. Neuinstallationen verwenden `[vad].speech_end_ms = 1000`; der Benutzer kann 100–5000 ganze Millisekunden wählen. Bestandserhalt und ausdrücklich gesetztes `--speech-end-ms` haben Vorrang. `energy_threshold` bleibt 520 bzw. der vorhandene Wert.

Primär-TTS ist neu Kokoro; explizite bestehende Qwen-/Piper-Wahl bleibt erhalten. Das PCM-Protokoll ist mono S16LE bei 24 kHz mit Headern für Format, Kanäle und Abtastrate. Der Telefonadapter setzt auf 16 kHz um. Vor dem ersten Audio ist Piper-Fallback möglich; nach begonnenem Audio keine Wiederholung desselben Texts über ein anderes Backend. Numerische Ausgabe läuft weiter durch den vorhandenen Zahlen-Guard.

Der Agent lädt eine gewählte WAV-Begrüßung beim Start und hält das aufbereitete PCM im Speicher. Sie ersetzt nur die Begrüßungssynthese. `greeting_mode = "tts"` bleibt verfügbar. Vorhandene Aufnahme, Modus und Pfad bleiben bei Upgrades erhalten. Lokales Bereitstellen einer fehlenden Aufnahme erfolgt ausdrücklich über `--greeting-wav`; Audio wird nicht in den Installer eingebettet.

Der Backendinstaller installiert den unabhängigen `kienzlefon-ai-tts-apply`-Befehl, aber keine Modelle oder CUDA-Komponenten. Umschalten verwendet die bestehende Reload-Sperre und Kapazitätsprüfung. Ein reiner VAD-/Begrüßungsreload erneuert nur die Backendclients. Kokoro bleibt dabei resident. Bestehende Ansagentexte, Zeiten und Profile werden erhalten; fehlende Zeitwerte folgen weiterhin der 2.5.2-Folge 5/11/17 Sekunden.

KI-SIP-Endpunkte verlangen G.722. Der Hauptanlagen-Generatorpatch wird getrennt bereitgestellt; andere Endpunkte bleiben unverändert. AudioSocket behält `slin16`/16 kHz und drei technische Telefonplätze. Die dokumentierte Betriebsempfehlung von höchstens zwei parallelen Anrufen wird durch lokale Tests nicht erweitert.

[Bedienung und Upgrade](../INSTALLATION-v2.6.md) · [Tests und Nachweisgrenzen](../TESTS-v2.6.md)
