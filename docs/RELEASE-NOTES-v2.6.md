# Kienzlefon AI 2.6

Version 2.6 integriert den übergebenen Kokoro-Thorsten-Dienst und die zugehörigen Telefonieerweiterungen in ein neues versionsgleiches Installerpaar. Die Standardpause bis zum erkannten Sprachende steigt von 500 auf **1000 ms**, ohne Änderung der Lautstärkeschwelle. Vorhandene Einstellungen werden übernommen; eine ausdrückliche Option erlaubt die gezielte Anpassung.

- KI-Server: Kokoro als neuer TTS-Standard, fixiertes Modell, eigene versionierte Python-Umgebung, unprivilegierter residenter Dienst, Warmup und Healthcheck. CUDA als Standard, bewusste CPU-Auswahl, keine automatische Ausweichwahl. UUID-basierte Mehr-GPU-Zuordnung einschließlich VRAM-Prüfung.
- Telefonie: Kokoro neben Qwen/Piper, Piper-Fallback vor erster Ausgabe, konfigurierbare WAV-/TTS-Begrüßung, Ansagen und Kapazitätsprüfung. Bestehende WAV-Dateien und Konfigurationswerte bleiben erhalten.
- Betrieb: expliziter TTS-/Gerätewechsel mit Sperre, Prüfung freier Plätze und Rücksetzung. Reiner Backendreload lädt das residente Modell nicht neu.
- SIP: G.722-only für die KI-Endpunkte; separater vorbereiteter Hauptanlagen-Generatorpatch. AudioSocket bleibt 16 kHz.
- VAD: `speech_end_ms = 1000` bei neuen Konfigurationen, `--speech-end-ms` für ausdrückliche Auswahl, Bereichsprüfung auch in Runtime/Reload. Bestehende 500-ms-Einstellungen werden nicht still geändert.

Die bisher bestätigten Installer und die Übergabeoriginale bleiben erhalten. LLM-/ASR-/Pyannote-Payloads werden gegenüber 2.5.2 nur in Versionsangaben fortgeführt. Der AMD-Zweig bleibt unverändert. Qwen bleibt installiert bzw. separat installierbar; Piper wird vom KI-Serverinstaller ausschließlich auf Erreichbarkeit geprüft.

[Installation und Betrieb](INSTALLATION-v2.6.md) · [Prüfungen und Grenzen](TESTS-v2.6.md)

Die Freigabe umfasst lokale Integration. Eine produktive Aktivierung des neuen Installerpaars, neue Hardwaretests, Veröffentlichung oder ein Push sind damit nicht durchgeführt.
