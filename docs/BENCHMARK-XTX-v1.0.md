# Benchmarks und Hardwarestand: RX 7900 XTX / RTX 3090

[Zur README](../README.md) · Dokumentation vom 30. September 2026 · Messungen vom 29. September 2026

## Ergebnis

**Die RX 7900 XTX ist als AMD-Plattform für die vier KI-Rollen praktisch erprobt.** Der separate AMD-Installer 1.0.1 hat LLM, ASR, native Qwen-TTS und Pyannote aktiviert. Einzelinferenz, gleichzeitige Anfragen an alle vier Rollen und zwei Lasttests mit jeweils acht Anfragen bestanden. Anschließend wurde die tatsächlich laufende Telefonruntime 2.5 von der RTX-3090-Umgebung übernommen, um Piper ergänzt und technisch geprüft. Auch ein echter Konfigurationsreload auf XTX war erfolgreich.

Besonders deutlich ist der Fortschritt bei TTS: Der native HIP-Pfad liefert echtes frühes PCM-Streaming und etwa 3,7-fache Echtzeit. Der vorherige PyTorch-Pfad lieferte erst die komplette Wellenform und lag ungefähr bei Echtzeit. Im installierten Dienst wurden warm **3,772× Echtzeit und 57,041 ms bis zum ersten PCM-Paket** gemessen.

Diese Ergebnisse belegen funktionierende Hardware- und Dienstpfade. Eine vollständige Telefon-/Hörabnahme, ein längerer Dauerlasttest und der Bootpfad der fertig migrierten XTX-Installation sind noch nicht systematisch abgenommen. Die Maximalbelastung lässt kaum VRAM-Reserve. Die im Folgenden getrennten Messreihen dürfen nicht zu einem einzigen End-to-End-Benchmark zusammengezogen werden.

## Getestete Stände

| Bereich | Stand und Nachweis |
|---|---|
| AMD-KI-Dienste | Eigenständiger Installer **1.0.1**, Ubuntu 24.04 / Python 3.12.3 / GA-Kernel 6.8 / ROCm 7.2.4, genau eine RX 7900 XTX mit 24 GB / gfx1100 |
| AMD-Installation | Vollständiger Vier-Rollen-Lauf erfolgreich; danach finales reguläres ASR-Rollenupdate mit korrigierter Audiowarteschlange erfolgreich |
| Aktive Telefonruntime auf XTX | **2.5**, vom tatsächlich vorgefundenen Quellsystem übernommen; kein dabei ausgeführtes Upgrade auf 2.5.1 |
| CUDA-/Backend-Dateipaar 2.5.1 | Weiterhin separat vorhandener Entwicklungsstand; aus dem XTX-Test folgt keine Installationsabnahme dieses CUDA-Installers |
| Modellvergleich | Vor der AMD-Dienstinstallation ausgeführte Einzelmodell-/Dienstbenchmarks; teilweise andere Kontext- und Ausführungsprofile |

Die finale AMD-Datei wurde als ASR-Rollenupdate geprüft, nicht nochmals als vollständiger Neubau aller vier Rollen auf einem frisch installierten Ubuntu. LLM, TTS und Pyannote blieben auf den regulär installierten, für diese Rollen unveränderten Payloads. Vorhandene Treiber und hashgeprüfte Modell-Caches wurden genutzt. Die final aktiven Releases wurden nicht manuell nachgepatcht.

## 1. Whisper: Vergleich und zusätzliche XTX-Profile

Die Langmessung verwendet dieselbe Aufnahme mit **2343,0 Sekunden / 39:03 Minuten**, PCM16, 16 kHz, mono. Es handelt sich um eine unabhängige Langaufnahme mit mehreren Wiederholungen, nicht um mehrere unabhängige Langfälle. Modell: `large-v3`, identische im Prüfbericht dokumentierte Gewichte.

Im WhisperDoku-Profil sind die wesentlichen Decoderparameter gleich: Deutsch, Beam 5, `best_of=5`, Temperatur 0, vorheriger Textkontext aus, Wortzeitstempel an, VAD aus, nicht gebatcht. XTX verwendet explizit geprüftes FP16; der residente 3090-Dienst verwendet `compute_type=auto` und meldet den tatsächlich gewählten Typ nicht. CT2-Version, CPU und Dienstumgebung unterscheiden sich.

| Messpfad | Wiederholungen | Verarbeitungszeit, Median | Durchsatz |
|---|---:|---:|---:|
| XTX, direktes WhisperDoku-Profil, FP16 | 3 | 133,092 s | **17,60× Echtzeit** |
| RTX 3090, residenter WhisperDoku-Dienst, clientseitig | 3 | 81,001 s | **28,93× Echtzeit** |
| Derselbe 3090-Test, serverseitig gemessen | dieselben 3 | 80,341 s | 29,16× Echtzeit |
| XTX, Beam 1 mit Wortzeitstempeln, Temperatur 0, Kontext/VAD aus | 2 | 104,006 s | **22,53× Echtzeit** |
| XTX, Beam 5, Batch 4 und VAD | 2 | 97,629 s | **24,00× Echtzeit** |
| XTX, Beam 5, Batch 8 und VAD | 2 | 123,110 s | 19,03× Echtzeit |

Durchsatz bedeutet hier `Audiolänge / Verarbeitungszeit`; der Real-Time-Faktor RTF ist dessen Kehrwert. Modellladen liegt bei der XTX außerhalb der Verarbeitungszeit. Die 3090-Clientzeit enthält HTTP und Dekodierung. Die serverseitige Zeit kann eine Wartezeit an der Final-block-Sperre enthalten.

Im praktischen WhisperDoku-Vergleich erreicht die XTX rund **61 % des 3090-Durchsatzes**. Gegenüber ihrer früheren Baseline von 5,14–7,07× ist das eine erhebliche Verbesserung durch ein anderes Decoderprofil. Daraus folgt kein entsprechender Gewinn allein durch GPU oder Treiber. Die alte Baseline mit Temperaturkaskade, Textkontext und ohne Wortzeitstempel ist kein gleich konfigurierter Vergleich mit den neuen Profilen.

Beam 1 mit Wortzeitstempeln liefert rund **28 % mehr Durchsatz** als die XTX-Doku-Referenz bei etwa 4,94 statt 5,19 GiB Prozess-VRAM. Batch 4 ist nochmals rund 6,5 % schneller, benötigt aber etwa 6,78 GiB Prozess-VRAM und ändert zusätzlich VAD/Chunking. Die VAD reduziert die verarbeitete Dauer auf 2021,624 s; die angegebenen Echtzeitfaktoren beziehen sich weiterhin auf die vollständigen 2343 s. Batch 8 bringt in diesem Fall keinen Vorteil.

### Qualität und verworfene Varianten

Die beschriebenen Doku-, Beam-1- und Batchprofile bestehen die Zeitstempelgrenzen ihrer Läufe. Die vollständige Profilserie umfasst 24 abgeschlossene GPU-Inferenzen, davon 22 mit bestandener Zeitstempelprüfung. Zwei Beam-5-Kontrollläufe ohne Wortzeitstempel überschreiten die erlaubte Grenze; ein weiterer Versuch wurde nach dem 600-s-Gesamtprozessbudget ohne Inferenzergebnis beendet. Diese Fälle bleiben Fehlschläge bzw. unvollständige Versuche.

Unterschiedliche Wort- oder Segmentzahlen sind kein Qualitätsnachweis. Es gibt für diese Langaufnahme keinen geprüften WER-Vergleich. Das Beam-1-Profil und Batch 4 sind getestete Kandidaten, keine pauschal freigegebenen Ersatzprofile. Der installierte AMD-Telefon-ASR-Dienst ist ein eigener WhisperLiveKit-/SimulStreaming-Pfad; er ist kein neu installierter WhisperDoku-Langdatei-/Batch-Dienst und bietet nicht den 3090-Endpunkt `/v1/asr/final-block`.

## 2. LLM und Sprechertrennung

| Messung | RX 7900 XTX | RTX 3090 | Einordnung |
|---|---:|---:|---|
| Qwen3.5-9B Q6_K, seriell | **81,22 Token/s** | 96,21 Token/s | XTX rund 84 % des gemessenen 3090-Durchsatzes |
| Drei parallele LLM-Anfragen, aggregiert | **175,84 Token/s** | Median 191,92 Token/s | XTX rund 92 %; ein XTX-Batch und drei 3090-Batches |
| Pyannote Community-1, 2343 s Audio, warm | **26,78 s / 87,48×** | ca. 26,31–26,39 s / 88,8–89,1× | Verarbeitungszeit nahezu gleichauf; keine Qualitätsparität belegt |

Der LLM-Vergleich nutzt identische GGUF-Gewichte und llama.cpp `b9637`, aber ein **Benchmark-Kontextprofil mit 262144 Gesamtkontext**. Die Installerprofile verwenden 131072. Die Messanfragen enthalten nur 27 Prompttoken und je 128 Ausgabetoken. Diese Zahlen belegen weder gefüllte Langkontexte noch die Antwortgeschwindigkeit dreier realer Telefongespräche.

Pyannote liefert auf XTX drei, auf 3090 vier Sprecherkennungen für dieselbe Aufnahme. Ohne annotierte Referenz ist nicht belegt, welche Zuordnung richtig ist. Unterschiedliche PyTorch-/TorchCodec-Stände bleiben Teil des Vergleichs. Eine fast gleiche Laufzeit ist kein DER- oder Qualitätsnachweis.

## 3. TTS: von vollständiger Wellenform zu frühem Streaming

Für die drei identischen synthetischen Eingabetexte ergibt sich folgende Entwicklung auf XTX:

| XTX-Pfad | Kurz | Mittel | Länger | Ausgabe |
|---|---:|---:|---:|---|
| Ursprünglicher PyTorch/BF16-Pfad | 1,08× | 1,06× | 1,04× | Erst nach vollständiger Wellenform |
| Kompilierter Talker und Code-Predictor | 1,61× | 1,54× | 1,50× | Weiterhin vollständige Wellenform |
| Optimierter nativer HIP-Pfad | **3,74×** | **3,74×** | **3,70×** | Echtes PCM-Streaming; erstes Paket nach 56–60 ms |

Die früher dokumentierte TTS-Schwäche um ungefähr Echtzeit beschreibt damit nicht mehr den aktuellen nativen XTX-Pfad. Das Modell `Qwen3-TTS-12Hz-0.6B-CustomVoice`, Sprecher `uncle_fu` und die vorhandenen Gewichte bleiben erhalten. Das ausgewählte Profil verwendet einen ersten Chunk mit 80 ms Audio und Folgechunks mit 160 ms Audio.

### Native XTX gegenüber vorhandener CUDA-Referenz

XTX: Mediane aus drei warmen Läufen je Fall. 3090: ein vorhandener warmer Referenzlauf je Fall; kein im nativen XTX-Auftrag neu ausgeführter Vergleich.

| Fall | XTX erstes PCM | 3090 erstes PCM | XTX Gesamtzeit | 3090 Gesamtzeit | XTX / 3090 erzeugtes Audio |
|---|---:|---:|---:|---:|---:|
| Kurz | 56,0 ms | 54,5 ms | 1,369 s | 0,758 s | 5,12 / 5,52 s |
| Mittel | 57,5 ms | 123,7 ms | 2,249 s | 1,927 s | 8,40 / 12,00 s |
| Länger | 59,6 ms | 279,7 ms | 4,214 s | 4,207 s | 15,60 / 21,12 s |

Der Streamingstart liegt damit im Bereich der 3090-Referenz, bei den beiden längeren Fällen früher. Vollständige Durchsatzparität besteht nicht: Die 3090 erreicht in diesen Fällen 7,28 / 6,23 / 5,02× Echtzeit. Fast gleiche Gesamtzeiten beim längeren Text müssen zusammen mit den unterschiedlichen Audiolängen gelesen werden.

XTX misst am lokalen Pipe-Empfang nach S16LE-Konvertierung, die 3090 am HTTP-Client. Native HIP/BF16-Materialisierungsgrenzen mit FP32-Akkumulation/Codec und CUDA/INT8 sind verschiedene Ausführungen. „Erstes PCM“ bezeichnet verfügbare Audiodaten, nicht den akustischen Beginn eines Wortes am Telefon.

### Wiederholungen und begrenzter Qualitätsnachweis

Die native Reihe umfasst **109 abgeschlossene Benchmark-Synthesen, davon 78 warme Wiederholungen**. Die warmen Ergebnisse sind innerhalb ihres jeweiligen Falls und Profils zur Aufwärmsynthese PCM-identisch. Zehn zusätzliche Wiederholungen des längeren Falls ergeben 4,230–4,237 s Verarbeitungszeit und 59,07–59,76 ms bis zum ersten PCM. Das ausgewählte Profil zeigt in diesen Adaptermessungen keine berechnete Wiedergabelücke.

Sechs weitere Synthesen vergleichen Ausgangs- und optimiertes natives Profil für drei Texte: Die vollständigen Wellenformen sind jeweils byteidentisch. Die sechs GPU-Whisper-Rücktranskriptionen enthalten **0 Wortfehler** bei den drei Referenzsätzen mit 7 / 21 / 40 Wörtern; normalisiert wurden Groß-/Kleinschreibung, Interpunktion und die bekannte Zahl 14. Das ist ein positiver Vollständigkeitsbefund für diese Sätze, keine allgemeine WER-Studie, Hörabnahme oder Gleichwertigkeitsprüfung zur 3090.

## 4. Installierter AMD-Stack: echte gleichzeitige Last

Nach Installation von AMD 1.0.1 wurden 71 Selbsttests auf Ubuntu/XTX bestanden. Zusätzlich liefen echte Inferenztests, ein Vier-Rollen-Test und zweimal **drei ASR-, drei LLM-, eine TTS- und eine Pyannote-Anfrage gleichzeitig**.

| Prüfung am installierten Stand | Ergebnis |
|---|---|
| Drei warme TTS-Läufe, 5,12 s Ausgabe | Median **3,772× Echtzeit**, 1,357 s Verarbeitung, erstes 80-ms-PCM-Paket **57,041 ms** |
| TTS im Vier-Rollen-Test | 2,241× Echtzeit, erstes Paket 96,821 ms |
| TTS in den zwei Acht-Anfragen-Runden | 2,022× / 1,457× Echtzeit, erste Pakete 166,851 / 96,731 ms |
| 60-s-ASR-Burst | **6,800 s**, reguläres Streamende und Inhaltsschlüssel bestanden |
| LLM einzeln und dreifach parallel | Erfolgreich; je 13 Ausgabetoken, kein neuer allgemeiner Token/s-Benchmark |
| Pyannote mit 18 bzw. 60 s Audio | Gültige nichtleere Segmente, auch unter gleichzeitiger Last |
| Abschließende Dienstprüfung | Fünf Units aktiv/enabled, Healthchecks grün, automatische Neustartzähler 0 |
| Gezielter ASR-Neustart bei residenten anderen Rollen | Anschließende Inferenz- und Dienstprüfung bestanden |

Der zuerst fehlgeschlagene 60-s-Burst wurde nach Korrektur der ASR-Queue mit demselben Test erfolgreich wiederholt. Der Decoder wird weiterhin auf der GPU ausgeführt; das Laden des Checkpoints im Hauptspeicher ist kein CPU-Inferenzfallback. Modellgewichte und Rechengenauigkeit wurden für diese Korrektur nicht reduziert. Die hybride CT2-/Torch-ASR darf deshalb trotzdem nicht pauschal als vollständig FP16 beschrieben werden.

HIP/HSA-Bibliotheken aus ROCm 7.2.4 und GPU-Modellparameter wurden geprüft; in den GPU-Prozessen wurden keine NVIDIA-Libraries gefunden. Im finalen Prüffenster gab es keine Kernel-OOM-, GPU-Reset- oder amdgpu-Fault-/Timeouttreffer.

Der abgetastete VRAM-Peak des Lasttests lag bei **25.744.220.160 von 25.753.026.560 Byte**, also praktisch am verfügbaren Limit. Die bestandenen kurzen Tests sind keine Zusage für größere parallele Prompts, längere Audios oder Dauerlast. Für Speicherreserve ist Pyannote von hoher Telefonielast zeitlich zu trennen bzw. ein eigenes Lastprofil zu prüfen.

## 5. Telefonieübernahme und tatsächlicher Reload

Nach der KI-Dienstprüfung wurden Asterisk, drei Agenten, Kapazitätspublisher, lokaler Chat und Piper separat auf XTX ergänzt. Quelle war die **tatsächlich laufende Runtime 2.5**. Die frühere Dokumentationsannahme „auf dem Referenzsystem noch 2.4.2“ ist damit überholt. Das CUDA-/Backend-Paar 2.5.1 und der AMD-Installer wurden für diese Migration nicht geändert.

Technisch bestätigt wurden drei SIP-Registrierungen, drei freie Plätze und die zentrale Admission-Verbindung. Auf dem Quellsystem wurden Asterisk, Agenten und Publisher beendet und ihr Autostart deaktiviert; die KI-Dienste blieben aktiv. Ein kurzzeitiger unerwarteter Wiederanlauf der Quelle wurde in der Schlussprüfung erkannt und per ausdrücklichem systemd-Stop korrigiert.

Reale Aufrufe durch die übernommene Telefonruntime:

| Prüfung | Ergebnis |
|---|---|
| Qwen-TTS, 5,60 s Ausgabe | 1,502 s, **3,729× Echtzeit**, erstes PCM 72,92 ms |
| Piper, 3,75 s Ausgabe | 0,363 s, **10,329× Echtzeit**, erstes PCM 235,11 ms |
| Block-ASR des 5,60-s-Qwen-Audios | 1,018 s; Inhalt im RAM geprüft |
| LLM mit Telefoniedialog-Schema | 2,596 s; gültige strukturierte Antwort |
| Qwen-Ausgabe der LLM-Antwort, 3,28 s Audio | 0,897 s; erstes PCM 65,24 ms |

Zusätzlich bestanden eine idempotente Core-Ausgabe in einem isolierten RAM-Dateisystem und ein flüchtiger HTTP-Chat. Es wurden keine Gesprächs-/Spooldaten migriert. Die bestehende Konfiguration für Demobetrieb und lokale Ausgabe blieb erhalten; daraus folgt keine neu eingerichtete Übertragung von Aufträgen an eine Praxis.

Beim späteren Reload fehlten zunächst das Backup-Verzeichnis und die private Rückfallkonfiguration. Der unveränderte Reload brach vor Dienstaktionen ab; `--check` hatte diese Voraussetzungen nicht vollständig erfasst. Nach kontrollierter Ergänzung aus dem geprüften Migrationsstand gelang der echte Reload mit drei Registrierungen und freien Plätzen. Benutzerkonfiguration und Füllclips blieben erhalten; Asterisk, Piper und alle fünf AMD-KI-Units wurden dabei nicht neu gestartet. Ein absichtlich ausgelöster produktiver Rollback ist weiterhin nicht abgenommen.

Die technische Migration ist kein vollständiger SIP-/RTP-/Telefon-End-to-End-Test. In einer späteren CPU-Diagnose wurde ein aktives Gespräch beobachtet; eine systematische Hör-/Gesprächsabnahme ist damit noch nicht dokumentiert.

## 6. CPU und GPU-Telemetrie richtig einordnen

Direkte CPU-Zeitmessungen ergaben während eines aktiven Gesprächs 7,53 % Gesamtlast. In drei folgenden kurzen Fenstern wurden 0,43 / 0,36 / 0,39 % gemessen; im letzten Fenster waren keine Gespräche oder Kanäle aktiv. Eine anhaltende CPU-Gesamtlast von 30 % im Leerlauf wurde nicht reproduziert.

Der nvtop-Absturz wurde behoben. Für die HIP-Prozesse fehlen jedoch verwertbare GPU-Engine-Zeitfelder; Prozessauslastung bleibt daher N/A statt eines gemessenen Prozentwerts. Der globale GPU-Sensor meldete auch bei niedriger CPU-Last anhaltend 100 %. Diese Anzeige ist kein zuverlässiger Nachweis voller nutzbarer Rechenauslastung. Der Hardwarebeleg beruht auf echten Anfragen, Geräte-/Parameterprüfungen und geladenen HIP-Bibliotheken, nicht allein auf dieser Anzeige.

## 7. Noch offene Grenzen

- Systematische Telefon-/Hörabnahme mit Antwortübergängen, Fallback, Handoff und drei realen Anrufen.
- Längerer Dauerbetrieb und ausreichende VRAM-Reserve unter repräsentativer Last.
- Bootpfad der vollständigen XTX-Installation, Hardware-Uninstall und erzwungener produktiver Rollback.
- WER-/DER-Qualitätsvergleich der langen ASR-/Diarisierungsfälle und breitere TTS-Hörbeurteilung.
- Der im 3090-Vergleich bei zwei von drei Streaming→Final-block-Übergängen beobachtete Fehler bleibt offen. Gesunde Abschluss-Healthchecks belegen keine Behebung; er wurde nicht als OOM nachgewiesen.
- Keine Übertragung der Ergebnisse auf Framework-/gfx1151-Hardware, Multi-GPU oder andere ROCm-/Kernelstände ohne eigene Prüfung.

## Nachweisbasis

Die Übersicht fasst folgende unverändert erhaltene lokale Prüfberichte zusammen. Sie überträgt technische Messwerte, keine Audio-, Transkript- oder Zugangsdaten. Rohdaten und umgebungsspezifische Berichte sind nicht automatisch Bestandteil der öffentlichen Dateiauswahl.

| Aussagebereich | Lokaler Bericht unter `7900XTX/` |
|---|---|
| Whisper, LLM, Pyannote und 3090-Grenzen | `TESTBERICHT-ROCM-VERGLEICH-20260929-v1.1.md` |
| Native TTS, Vergleich, Wiederholungen, Rücktranskription | `tts-native-hip-v1.0/TTS-NATIV-ERGEBNIS-20260929-v1.0.md` |
| Installationsfolge, 71 Tests und gemischte Last | `VALIDIERUNG-AMD-INSTALLER-v1.0.1.md` |
| Tatsächliche Runtime und Migration | `TELEFONIE-MIGRATION-3090-XTX-v1.0.md` |
| Erfolgreicher späterer Reload | `RELOAD-STATE-REPAIR-v1.0.md` |
| CPU-/GPU-Messgrenzen | `NVTOP-MESSWERTE-DIAGNOSE-v1.1.md` |

Die ASR-Profilmediane, nativen TTS-Messungen, Dienst-/Lasttestergebnisse und der VRAM-Peak wurden für diese Dokumentation zusätzlich gegen die vorhandenen technischen JSON-/JSONL-Dateien abgeglichen. Es wurden am 30. September keine neuen Hardwaretests ausgeführt.
