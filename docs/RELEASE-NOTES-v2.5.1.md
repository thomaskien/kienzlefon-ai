# Release Notes 2.5.1 – Entwurf

[Zur README](../README.md) · Dokumentationsstand: 28. September 2026

**Status: lokal implementiert und isoliert geprüft; Veröffentlichung und Zielhardwareabnahme stehen aus.** Diese Datei beschreibt den vorbereiteten Stand. Sie bestätigt weder einen veröffentlichten Git-Tag noch eine Installation von 2.5.1 auf dem Referenzserver.

## Neu in 2.5.1 gegenüber 2.5

Pyannote erhält eine eigene Bind-Adresse. Es gilt `--pyannote-bind` vor vorhandenem `DIARIZATION_HOST` aus der geschützten ENV vor dem neuen Standard `0.0.0.0`. Vorhandene Loopback-, LAN- oder Hostnamenwerte bleiben erhalten; der allgemeine Bind-Wert für LLM/ASR steuert Pyannote nicht mehr. Leere, ungültige oder unlesbare Bestandswerte führen zum Abbruch.

Die Healthprüfung verwendet bei Wildcardbindung localhost, ansonsten die konkrete Adresse. Der Dienst bleibt IPv4-basiert. Bei `0.0.0.0:8183` lauscht er auf allen IPv4-Schnittstellen und besitzt keine HTTP-Authentifizierung; Zugriff im geschützten Netz begrenzen. Der Installer ändert keine Firewallregeln. Eine gezielte Umstellung ist über `--action configure --role pyannote --pyannote-bind ADRESSE` möglich und startet den Dienst neu.

LLM, ASR, Qwen-TTS, Piper, Modelle, Abhängigkeiten, CUDA und GPU-Verträge bleiben unverändert. Das Backend ist gegenüber 2.5 ausschließlich versionsangepasst. Alle folgenden Wartefeedback-Funktionen wurden bereits mit 2.5 eingeführt und werden unverändert fortgeführt.

## Bereits in 2.5 gegenüber 2.4.2 eingeführt

### Konfigurierbares Wartefeedback

Die Backendruntime unterstützt drei getrennt einstellbare Ansagetexte und absolute Startzeiten ab erkanntem Sprachende. Defaults sind „Bitte warten.“ bei 2000 ms, „Ich verarbeite.“ bei 7000 ms und „Bitte warten.“ bei 13000 ms. Leere Texte deaktivieren einzelne Ansagen. Die Texte werden als statische Clips vorbereitet, nicht in jedem Gespräch neu synthetisiert.

Ein lokal erzeugter Piepton ergänzt die Wartephase: standardmäßig ab 0 ms alle 1000 ms, 400 Hz, 100 ms Dauer und lineare Amplitude 0.15. Sprache hat Vorrang; während Ansagen und bei zu knappem Abstand werden Töne ausgelassen. Das Tonraster läuft nach der letzten Ansage bis zur Antwort oder zum Ende der Pipeline weiter.

Erst tatsächlich ausgabefähiges Antwortaudio beendet weiteres Wartefeedback. Ein laufender Sprachblock oder Ton wird noch beendet; Auflegen bricht ab. Die zusätzliche Wartezeit auf diesen Abschluss wird separat gemessen.

### Vorbereitung beim Reload

`regenerate_on_reload = true` erlaubt dem ausdrücklichen Reload, ausschließlich fehlende oder geänderte Clips vorzubereiten. Passende Dateien aus 2.4.2 werden wiederverwendet. Startzeiten, Tonparameter und der normale Live-TTS-Seed verändern das Sprachclipprofil nicht.

Der Reload prüft freie Plätze vor und nach der Vorbereitung, sperrt parallele Aufrufe und verwendet private Zwischenablagen und Sicherungen. Für Aktivierungsfehler ist die Rücksicherung von Clips und letzter erfolgreicher TOML implementiert und isoliert getestet. `--check` synthetisiert keine Clips und startet keine Dienste. Reale Wiederherstellung auf der Zielhardware steht noch aus.

### Performancefelder

Neu sind `beep_count`, `beep_audio_ms`, `end_of_detected_speech_to_first_beep_audio_ms` und `end_of_actual_speech_to_first_beep_audio_ms`. Die bisherigen Sprachfüllmetriken und die echte Antwortlatenz behalten ihre Bedeutung. Fehlende neue Werte älterer Datensätze werden nicht als Nullmessung behandelt.

### Bestätigung im KI-Serverinstaller

Der versionsgleiche KI-Serverinstaller weist vor Installation bzw. Update ausdrücklich auf die KI-Komponenten und den separaten Backendinstaller hin. Enter, Nein, ungültige Antworten oder EOF brechen vor Änderungen ab. Nichtinteraktive Installationen benötigen zusätzlich `--confirm-ki-install`. Die KI-Payloads bleiben gegenüber 2.4.2 funktional unverändert.

## Updatehinweise

- Das Wartefeedback-Update betrifft ausschließlich das Backend. Dafür den KI-Serverinstaller nicht erneut ausführen.
- Die Wartefeedback-Schlüssel benötigen mindestens Runtime 2.5 und werden in 2.5.1 unverändert unterstützt. Beim Wechsel von 2.4.2 erfolgt zuerst eine Backendinstallation oder ein separat geprüftes gezieltes Update; ein Reload der alten Runtime genügt nicht.
- Unterstützte Bestandswerte, insbesondere deaktiviertes Wartefeedback und der Live-TTS-Seed, bleiben erhalten. `streaming_asr` und `speculative_llm` werden weiterhin auf `false` migriert.
- Der vollständige Backendinstaller kann SIP-/Dialplan-Dateien und Dienste bearbeiten. Ein späterer Konfigurationsreload startet Asterisk und KI-Dienste nicht neu.
- Eine notwendige Clipneuerzeugung benötigt den vorhandenen Qwen-Dienst. Sie findet nicht während des Gesprächs statt.

Die genaue Bedienung steht unter [Installation und Update](INSTALLATION-v2.5.1.md) sowie [Betrieb und Konfiguration](BETRIEB-v2.5.1.md).

## Unveränderte Grenzen

- Ubuntu x86_64 mit NVIDIA/CUDA für die KI-Rollen; kein stiller CPU-Fallback.
- Drei Telefonplätze, blockweise ASR und genau eine endgültige LLM-Anfrage; kein Barge-in und keine Spekulation.
- Piper ist ein separat vorhandener Pflicht-Fallback und wird vom KI-Serverinstaller nicht verändert.
- Pyannote bleibt optional und von der Kern-ASR getrennt.
- Noch keine 2.5.1-Abnahme für Neuinstallation, Upgrade, reale Audioqualität, drei parallele Gespräche und produktiven Rollback.
- Keine Zusage einer festen Antwortzeit oder allgemein belegten Leistungssteigerung.
- Bei Abbruch während Antwort-TTS können einzelne Audiozeiten fehlen; „Actual speech end“ ist VAD-geschätzt.

## Prüfsummen des dokumentierten Stands

SHA-256 der zwei lokalen Installer:

```text
8eeeeea6684ad46bc8f8568516a0ad83f192ed223b3807fa9e33db1a769f9fec  installer/install-kienzlefon-ai_v2.5.1.sh
a0b0b14b59c95c1cbc6c0e2969d6c2ef0e09a537eaa6244a75b804eb0aada907  installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh
```

Diese Werte identifizieren den beschriebenen lokalen Stand. Sie sind kein signiertes Release und kein Nachweis einer Veröffentlichung. Vor Veröffentlichung erneut mit den tatsächlich ausgewählten Dateien vergleichen.

## Abnahme und Veröffentlichung

Der [Validierungsstand](TESTS-v2.5.1.md) trennt lokale Tests und reale Ergebnisse. Die [Veröffentlichungscheckliste](VEROEFFENTLICHUNG-v2.5.1.md) führt noch offene Punkte: Lizenz, bekannte Tokenkopie, Dateiprüfung, öffentlicher Repositoryinhalt und Freigabe des Veröffentlichungsschritts.
