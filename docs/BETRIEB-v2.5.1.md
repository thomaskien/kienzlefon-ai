# Betrieb und Konfiguration – Version 2.5.1

[Zur README](../README.md) · Stand: 28. September 2026

Diese Anleitung setzt eine installierte Backendruntime 2.5.1 voraus. Die Zielhardware-Aktivierung dieses Stands ist noch offen. Die folgenden TOML-Blöcke sind Ausschnitte: jeweils die vorhandene Sektion bearbeiten, keine zweite gleichnamige Sektion anhängen und keine vollständige Bestandskonfiguration durch einen Ausschnitt ersetzen.

## Wichtige Pfade

| Pfad | Inhalt |
|---|---|
| `/etc/kienzlefon-ai/installer-v2.conf` | Gespeicherte KI-Rollen, Ports und GPU-Zuordnung; ohne Token |
| `/etc/kienzlefon-ai/kienzlefon-ai-v2.toml` | LLM-/ASR-Konfiguration |
| `/etc/kienzlefon-ai/diarization.env` | Optionaler Hugging-Face-Token; ausschließlich root-lesbar |
| `/etc/kienzlefon-ai-asterisk-backend/backend.toml` | Backendkonfiguration einschließlich SIP-Zugangsdaten |
| `/opt/kienzlefon-ai-asterisk-backend/bin/` | Installierte Runtimeprogramme |
| `/opt/kienzlefon-ai-asterisk-backend/audio/filler-v1/` | Statische Warteansagen und Manifest |
| `/var/lib/kienzlefon-ai-asterisk-backend/last-reload.toml` | Letzte erfolgreiche Reload-Konfiguration, Modus `0600`; enthält Zugangsdaten |
| `/var/backups/kienzlefon-ai-asterisk-backend/` | Private Installations-/Reload-Sicherungen |
| `/var/log/kienzlefon-ai-asterisk-backend/performance.jsonl` | Optionales technisches Performancelog |

Das `v2` bzw. `filler-v1` in diesen Pfaden bezeichnet bestehende Ablageverträge. Die Pfade werden nicht in `v2.5.1` umbenannt.

## Standardverhalten

Die Begrüßung lautet:

> Ich bin Karl der elektronische Praxisassistent. Bitte Sprechen Sie in natürlicher Sprache einfach drauf los. Wie kann ich Ihnen bitte helfen?

Qwen-TTS verwendet standardmäßig `uncle_fu` und `German`, Piper bleibt Fallback. Das VAD-Endpunktschweigen beträgt 500 ms. Der Live-TTS-Seed `[dialog].qwen_seed` hat bei Neuinstallation den Standard 42; unterstützte vorhandene Werte bleiben bei Updates erhalten.

Die Telefonruntime arbeitet blockweise. Die Werte `[dialog].streaming_asr = false` und `[dialog].speculative_llm = false` sind für 2.5.1 verbindlich; ein Umschalten auf `true` aktiviert keinen unterstützten Alternativmodus.

## Wartefeedback konfigurieren

Defaults der Sektion `[filler]`:

```toml
[filler]
enabled = true
seed = 12345
regenerate_on_reload = true

part1_text = "Bitte warten."
part1_start_ms = 2000
part2_text = "Ich verarbeite."
part2_start_ms = 7000
part3_text = "Bitte warten."
part3_start_ms = 13000

beep_enabled = true
beep_start_ms = 0
beep_interval_ms = 1000
beep_frequency_hz = 400
beep_duration_ms = 100
beep_volume = 0.15
```

Alle Startzeiten beziehen sich auf denselben erkannten VAD-Endpunkt. Das vorherige Endpunktschweigen liegt zusätzlich davor. Im Standard werden Töne bei 0 und 1 Sekunde fällig, die erste Sprachansage bei 2 Sekunden; weitere Sprachansagen bei 7 und 13 Sekunden, sofern noch gewartet wird.

| Wunsch | Einstellung |
|---|---|
| Gesamtes Wartefeedback ausschalten | `enabled = false` |
| Nur Sprachansagen | `enabled = true`, `beep_enabled = false` |
| Nur Töne | `enabled = true`, `beep_enabled = true`, alle drei `partN_text = ""` |
| Einzelne Ansage ausschalten | Den betreffenden Text leer setzen |
| Ansagetext ändern | Den betreffenden `partN_text` ändern und einen regulären Reload vorbereiten |
| Nur Startzeit oder Ton ändern | Entsprechende Werte bearbeiten; passende Sprachclips werden wiederverwendet |

### Gültige Werte

| Wert | Grenze / Bedeutung |
|---|---|
| `seed` | Ganzzahl 0–2147483647; unabhängig vom Live-TTS-Seed |
| `partN_text` | Höchstens 240 Zeichen, einzeilig, ohne Steuerzeichen; leere Texte deaktivieren den Teil |
| `partN_start_ms`, `beep_start_ms` | Ganzzahlen 0–120000 ms; aktive Sprachstartzeiten müssen aufsteigend oder gleich sein |
| `beep_interval_ms` | 200–10000 ms |
| `beep_frequency_hz` | 200–2000 Hz |
| `beep_duration_ms` | 20–500 ms in 20-ms-Schritten, höchstens so lang wie das Intervall |
| `beep_volume` | Endliche lineare PCM-Amplitude 0–0.5; 0 unterdrückt den Ton |
| Schalter | Echte TOML-Werte `true` oder `false` |

Eine vorbereitete Sprachansage darf höchstens zehn Sekunden dauern. Stimme und Sprache stammen aus `[dialog].qwen_speaker` und `[dialog].qwen_language`. Ausschließlich allgemeine statische Texte konfigurieren: Die daraus erzeugten Ansagen werden als Dateien gespeichert.

### Wiedergabe

- Jede aktivierte Sprachansage läuft höchstens einmal. Überschreitet sie den Start der nächsten, wartet diese bis zum Ende.
- Sprache hat Vorrang vor Tönen. Während einer Ansage und bei zu wenig Zeit vor der nächsten Ansage wird kein Ton begonnen.
- Ausgelassene Töne werden nicht nachgeholt. Danach gilt wieder das ursprüngliche Zeitraster. Nach der letzten Ansage können Töne bis zur Antwort bzw. zum Ende der Pipeline weiterlaufen.
- Erst ausgabefähiges Antwortaudio beendet weiteres Wartefeedback. Ein gerade laufender Satz oder kurzer Ton endet noch; die zusätzliche Antwortwartezeit wird separat gemessen.
- Auflegen bricht die Ausgabe ab. Die drei Telefonplätze haben unabhängige Zeitpläne.

Die Tonlautstärke am Telefon muss praktisch geprüft werden. `beep_volume` ist kein Schallpegel und keine Zusicherung gleicher Lautstärke für unterschiedliche Endgeräte.

## Konfiguration übernehmen

Zuerst nur validieren:

```bash
sudo kienzlefon-ai-reload --check
```

Dieser Aufruf erzeugt keine Sprachclips und ändert keine Dienste. Nach einer Textänderung kann er deshalb einen noch nicht passenden Clipsatz melden.

Für die beabsichtigte Aktivierung bei freien Telefonplätzen:

```bash
sudo kienzlefon-ai-reload
```

Mit `regenerate_on_reload = true` werden nur fehlende oder geänderte Sprachclips über den bestehenden Qwen-Dienst vorbereitet. Reine Timing-/Tonänderungen oder ein anderer Live-TTS-Seed lösen keine Neusynthese aus. Bei `false` muss bereits ein vollständig passender Clipsatz vorhanden sein; sonst wird der Reload abgelehnt.

Der Reload sperrt parallele Aufrufe, prüft freie Plätze und bereitet Dateien in einem privaten Zwischenverzeichnis vor. Unmittelbar vor Aktivierung prüft er die Belegung erneut. Kommt zwischenzeitlich ein Anruf hinzu, erfolgt kein Dienststopp. Erst ein vollständiger Satz wird gesichert und aktiviert; dabei werden die Telefonagenten angehalten, die Kapazität abgemeldet und die Backenddienste neu gestartet. Asterisk und KI-Dienste werden durch diesen Reload nicht neu gestartet.

Scheitert die Vorbereitung, laufen bisherige Dienste und Clips weiter; die bearbeitete TOML bleibt zur Korrektur erhalten. Bei Aktivierungsfehlern versucht der Reload, Clips und letzte erfolgreiche TOML wiederherzustellen. Fehlt `last-reload.toml`, wird vor Dienständerungen abgebrochen. Konkurrierende manuelle Änderungen werden nicht überschrieben; in diesem Fall kann ein manueller Wiederanlauf nötig sein. Ein Strom- oder Prozessausfall mitten in der Wartung ist kein abgenommener automatischer Wiederherstellungsfall.

Während Gesprächen und bei einem normalen Dienststart werden keine Warteansagen synthetisiert. Unpassende oder fehlende Clips verursachen eine technische Warnung; Sprachfüllblöcke entfallen, aktivierte lokale Pieptöne können weiter verwendet werden. Die eigentliche Antwortpipeline bleibt erhalten.

## Chat

Nach Installation steht der mit der Runtime ausgelieferte Client zur Verfügung:

```bash
kienzlefon-chat --help
kienzlefon-chat
```

Der manuelle Chat kann vollständige Aufträge über die vorhandene Kienzlefon-Spool persistieren. Deshalb für Funktionsprüfungen synthetische Daten und eine geeignete Testumgebung verwenden. Die Text-API unter `127.0.0.1:8300` ist keine öffentliche Weboberfläche. Chat bietet keine telefonische Rufweiterleitung.

## Technische Diagnose

```bash
sudo kienzlefon-ai-debug-console --snapshot
sudo kienzlefon-ai-debug-console --slot 0 --snapshot
curl -fsS http://127.0.0.1:8300/health
systemctl is-active kienzlefon-ai-agent@0.service kienzlefon-ai-agent@1.service kienzlefon-ai-agent@2.service
systemctl is-active kienzlefon-ai-text.service kienzlefon-ai-capacity-publisher.service
```

Normale Diagnosen enthalten keine Dialogtexte. Die explizit konfigurierbare sensitive Livekonsole erfordert sowohl `[debug].allow_sensitive_console = true` als auch einen ausdrücklichen Root-Aufruf mit `--show-text`. Sie bleibt im Standard aus. Solche Ausgaben nicht in Issues, Screenshots oder normale Logs übernehmen.

## Performanceaufzeichnung

In der bestehenden Sektion einschalten und anschließend bei freien Plätzen per Reload aktivieren:

```toml
[performance]
enabled = true
```

Bericht anzeigen:

```bash
sudo kienzlefon-ai-performance-report
sudo kienzlefon-ai-performance-report --json
```

Standardmäßig ist die Aufzeichnung ausgeschaltet. Die JSONL-Datensätze enthalten technische Zeiten, Zähler, `program_version` und `pipeline_mode`, keine Patientendaten, Dialogtexte, Audioinhalte oder Tokens. Die Auswertung trennt Versionen und die Modi `half_duplex_filler` bzw. `half_duplex`.

`beep_count` und `beep_audio_ms` zählen Töne, `filler_*`-Felder die Sprachansagen. `filler_available = 0` ist bei ausschließlich aktivierten Tönen möglich. `reply_audio_wait_for_filler_ms` misst die zusätzliche Wartezeit auf eine laufende Ansage oder einen Ton. Die eigentliche Antwortlatenz bleibt von beiden Arten Wartefeedback getrennt.

Grenzen: „Actual speech end“ ist VAD-geschätzt; bei Abbruch während Antwort-TTS können Audiozeiten trotz bereits begonnener Ausgabe fehlen. Fehlende Werte nicht als Null-Latenz interpretieren. Vergleiche müssen Stichprobengröße, Fehler, Abbrüche und identische Testbedingungen berücksichtigen.

## Häufige Befunde

| Befund | Nächster Prüfschritt |
|---|---|
| CUDA nicht gefunden oder inkompatibel | Vorhandenen Treiber, vollständiges Toolkit und `nvcc`-Pfad prüfen; bei Bedarf passendes `--cuda-home` wählen |
| KI-Installation bricht sofort ab | Ausdrückliche Bestätigung prüfen; nichtinteraktiv zusätzlich `--confirm-ki-install` erforderlich |
| Keine freien Telefonplätze | SIP-Registrierungen, Agentstatus, KI-Erreichbarkeit und Admission-Verbindung prüfen |
| Fehlende Sprachansagen | `[filler].enabled`, aktive Texte und passendes Clipprofil prüfen; bei freiem Backend regulären Reload vorbereiten |
| `--check` schlägt nach Textänderung fehl | Check erzeugt keine Clips; regulärer Reload kann sie bei aktivierter Regeneration vorbereiten |
| Piper nicht erreichbar | Den separat verwalteten Piper-Dienst prüfen; der KI-Installer repariert ihn nicht |
| Backendinstaller lehnt Chat-Symlink ab | Ziel prüfen; fremde oder defekte Dateien nicht pauschal löschen oder überschreiben |
| Rollback-/Wiederanlaufproblem | Private Sicherung und letzte erfolgreiche TOML zuordnen; keine Zugangsdaten in Supportausgaben kopieren |

Für Fehlerberichte genügen zunächst Version, Betriebssystem, Hardwareprofil, ausgeführter Befehl ohne Geheimnisse, technische Fehlerkennung und ein synthetischer Reproduktionsablauf.
