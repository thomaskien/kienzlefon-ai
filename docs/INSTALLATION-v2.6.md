# Installation und Betrieb von Kienzlefon AI 2.6

Version 2.6 übernimmt Kokoro mit Thorsten Voice aus der Übergabe vom 8. Oktober 2026 in die getrennten KI- und Telefonieinstaller. Neue Telefoniekonfigurationen verwenden Kokoro und eine Sprachendepause von **1000 ms**. Vorhandene ausdrücklich gesetzte Werte bleiben beim Upgrade erhalten. Die Lautstärkeschwelle wird nicht angehoben.

Das Installerpaar besteht aus:

- [KI-Serverinstaller](../installer/install-kienzlefon-ai_v2.6.sh)
- [Asterisk- und Dialoginstaller](../installer/kienzlefon-installer-asterisk-backend-v2.6.sh)

Die Programme sind eigenständige Shell-Dateien; ihre Python-Payloads sind eingebettet. Der [Kokoro-Quellordner](../installer/kokoro-v2.6/) dient der Wartung und muss für die Ausführung des Serverinstallers nicht danebenliegen. Frühere Versionsdateien bleiben erhalten.

## KI und Telefonie getrennt installieren

Der KI-Installer verwaltet LLM, ASR, TTS und optional Pyannote. Nur er installiert Kokoro-Modell, Python-Umgebung und Systemdienst. Der Backendinstaller verwendet vorhandene KI-Dienste und verwaltet Telefonie, Dialog, Ansagen, WAV-Begrüßung und das Umschaltwerkzeug. Er lädt keine Modelle herunter.

Zielplattform bleibt Ubuntu x86_64. LLM, ASR, Qwen und Pyannote verlangen NVIDIA/CUDA. Ausschließlich für Kokoro ist eine bewusste CPU-Auswahl möglich; ein CUDA-Fehler führt niemals automatisch zum CPU-Betrieb. AMD/ROCm gehört nicht zu dieser Version.

Beispiele für eine später ausdrücklich freigegebene Zielinstallation:

```sh
bash installer/install-kienzlefon-ai_v2.6.sh --role tts --tts-engine kokoro --tts-device cuda --tts-gpu GPU-…
bash installer/kienzlefon-installer-asterisk-backend-v2.6.sh --speech-end-ms 1000
```

`GPU-…` ist ein Platzhalter für eine tatsächliche NVIDIA-UUID; alternativ akzeptiert die Auswahl den angezeigten Index. Der Installer speichert die UUID und zeigt Index, UUID, Modell und VRAM. Für eine reine Kokoro-CPU-Installation lautet die Auswahl `--role tts --tts-engine kokoro --tts-device cpu`. Bei `all` bleibt die ausdrückliche Pyannote-Entscheidung bestehen.

Der vorhandene Zustand hat beim Upgrade Vorrang vor neuen Defaults. Alte TTS-Zustandsdateien ohne Engine-Feld werden als Qwen-Bestand erkannt; ein bereits aktiver Kokoro-Dienst wird auch gegenüber einem älteren Qwen-State bevorzugt. Geschützte Dienstkonfigurationen werden über sudo auf die benötigten Felder begrenzt gelesen. Sind beide TTS-Dienste aktiv, muss die Engine ausdrücklich gewählt werden. CLI-Optionen überschreiben nur gezielt. Der Serverinstaller liest dafür ausschließlich KI-Dienstkonfigurationen, keine Telefonie- oder SIP-Konfiguration.

Kokoro ist neu standardmäßig auf `127.0.0.1:8184` erreichbar. Qwen bleibt über `--tts-engine qwen` separat installierbar bzw. konfigurierbar. Die Kokoro-Installation löscht oder stoppt Qwen nicht. Piper wird vom KI-Installer nur auf Erreichbarkeit geprüft und bleibt als vorhandener Dienst unangetastet. Ein Wechsel der vom Telefon verwendeten Engine erfolgt über den unten beschriebenen Umschaltbefehl, nicht durch bloßes Installieren eines Modells.

## Kokoro und GPU-Zuordnung

Das Modell `Thorsten-Voice/Kokoro`, Epoch 5, ist auf Revision `734e593d320a3d876bede7020f773dfd481a0cc7` fixiert. [Modellmanifest](../installer/kokoro-v2.6/model_manifest.json) und [Abhängigkeiten](../installer/kokoro-v2.6/requirements.lock.txt) legen die Dateien fest. Die nicht benötigte Piper-Python-Installation aus der Benchmark-Lockdatei ist entfernt.

Die CUDA-Umgebung für 2.6 liegt unter `/opt/kienzlefon-ai/python/kokoro-venv-v2.6`, die bewusst gewählte CPU-Umgebung unter `/opt/kienzlefon-ai/python/kokoro-venv-v2.6-cpu`. Die CPU-Installation verwendet eine [eigene Lockdatei](../installer/kokoro-v2.6/requirements-cpu.lock.txt) ohne NVIDIA-/Triton-Pakete und benötigt keine GPU-Gerätegruppen. Beide Paketprofile sind lokal geprüft; eine neue Auflösung und Installation auf Ubuntu steht noch aus. Eine ältere Kokoro-Umgebung bleibt erhalten. Modell und Abhängigkeiten werden vor dem Austausch der Dienstdateien vorbereitet. Fehler beim Austausch oder anschließenden Warmup setzen veröffentlichte Dienstdateien und die vorherige Aktivierung zurück, solange Dateien und Dienstzustand noch dem vom Installer beobachteten Stand entsprechen. Bei späteren Änderungen wird nichts darübergeschrieben oder umgeschaltet; ein technischer Fehler fordert die manuelle Prüfung. Das gilt auch für einen zwischenzeitlich von selbst gewechselten Dienstzustand. Vorbereitete Modelle, Paketdownloads und die neue eigene Umgebung werden dabei nicht pauschal gelöscht.

Die Einheit `kienzlefon-kokoro-tts.service` läuft unprivilegiert. Genau eine geladene Instanz bedient die konfigurierte Parallelität. Der Healthcheck meldet Bereitschaft erst nach Modellladen und Warmup. Die VRAM-Prüfung folgt derselben stabilen GPU-UUID wie Torch; eine mehrdeutige Mehr-GPU-Auswahl wird abgelehnt.

GPU-Zuordnung wird im systemd-Drop-in des KI-Installers gespeichert. Eine reine Änderung von `kokoro.device` ersetzt keine fehlende GPU-Zuordnung: Nach einer reinen CPU-Installation zuerst mit dem KI-Installer die CUDA-Umgebung und gewünschte UUID bereitstellen. Eine Konfigurationsänderung installiert keine fehlenden CUDA-Pakete. Nach vorbereiteter CUDA-Installation kann deren Umgebung auch den ausdrücklich gewählten CPU-Betrieb ausführen. `--no-start` hält Kokoro nach der Installation inaktiv und deaktiviert seinen Autostart. Kokoro-Uninstall entfernt die verwalteten Dienst-/Konfigurations-/Programmdateien; Modelle und Python-Umgebungen bleiben erhalten, Qwen/Piper unberührt.

## Zentrale Telefoniekonfiguration

Auf dem Zielserver bleibt `/etc/kienzlefon-ai-asterisk-backend/backend.toml` maßgeblich. Ausschnitte in vorhandene Sektionen einarbeiten, keine zweite gleichnamige Sektion anhängen und keine vollständige Datei ersetzen.

```toml
[dialog]
tts_backend = "kokoro"
greeting_mode = "wav"
greeting_wav = "/opt/kienzlefon-ai-asterisk-backend/audio/begruessung_karl.wav"

[services]
kokoro_url = "http://127.0.0.1:8184/v1/tts/stream"

[kokoro]
device = "cuda"
voice = "thorsten"
speed = 1.0
host = "127.0.0.1"
port = 8184
threads = 4
max_concurrent = 3
model_dir = "/opt/kienzlefon-ai/models/kokoro-thorsten"
model_revision = "734e593d320a3d876bede7020f773dfd481a0cc7"
socket_timeout_seconds = 20

[vad]
speech_end_ms = 1000
```

Der Kokoro-Dienst erhält daraus beim ausdrücklichen Wechsel nur seine abgeleitete Datei `/etc/kienzlefon-ai/kokoro.toml`, ohne SIP-Zugangsdaten. Qwen und Piper bleiben als Backendwerte verfügbar. Vor dem ersten Antwortaudio ist Piper-Fallback möglich; nach bereits begonnener Ausgabe wird derselbe Text nicht über ein anderes Backend wiederholt.

Eine bereits aktivierte Kokoro-Konfiguration aus der Übergabe bleibt beim Backendupgrade erhalten. Auch bestehende CPU-Wahl, URLs, Geschwindigkeit, Threadzahl, Parallelität, Prompt, Ansagetexte/-zeiten, Debug- und Performanceeinstellungen werden übernommen. Die 2.5.2-Standard-Wartefolge 5/11/17 Sekunden bleibt bei fehlenden eigenen Werten bestehen.

## Sprechpause einstellen

`[vad].speech_end_ms` legt die zusammenhängende Zeit unterhalb der Lautstärkeschwelle bis zur Übergabe an ASR fest. Der neue Standard ist 1000 ms; erlaubt sind ganze Zahlen von 100 bis 5000. Die Prüfung gilt auch beim Laden der Runtime und Reload. `--speech-end-ms 1000` überschreibt bei einem Installerlauf gezielt einen vorhandenen Wert.

`energy_threshold` bleibt standardmäßig 520, `speech_start_ms` 120 ms. Letzterer Wert bestätigt den Sprachbeginn und ist nicht die Pause nach dem Sprechen. Leise Wortenden können unter der Schwelle liegen und deshalb bereits zum Stillezähler beitragen. Ein größeres `speech_end_ms` toleriert längere solche Abschnitte, verschiebt bei gleichem Signal aber auch den ASR-Start nach hinten. Die Verarbeitung arbeitet in 20-ms-Frames und rundet Zwischenwerte auf volle Frames auf.

Für einen später freigegebenen reinen Timingwechsel genügt die gezielte Änderung des bestehenden Werts und ein Reload bei freien Plätzen. Dafür weder den KI-Installer erneut ausführen noch Modelle neu laden.

## WAV-Begrüßung und Umschaltung

Vorhandene `greeting_mode`-/`greeting_wav`-Werte und Aufnahmen bleiben erhalten. Fehlende Begrüßungsoptionen bewahren den bisherigen TTS-Modus. Für eine neue WAV-Auswahl kann beim Backendinstaller `--greeting-mode wav --greeting-wav /absoluter/pfad/begruessung_karl.wav` verwendet werden. Eine bereits vorhandene verwaltete Aufnahme wird nicht überschrieben. Ein erneuter Import derselben Bytes ist zulässig; abweichende Dateien werden mit einem Hinweis abgelehnt. Individuelle Bestandswege bleiben ohne neue Dateiauswahl erhalten. Die ursprüngliche Aufnahme aus der Übergabe bleibt eine lokale Datei und ist nicht in den Installer eingebettet.

Der Agent bereitet die WAV beim Start als 16-kHz-PCM im Arbeitsspeicher vor. Das betrifft nur die Begrüßung; Antworten und Warteansagen verwenden das ausgewählte TTS. Eine Änderung der Begrüßung oder des VAD-Werts wird über den Backendreload aktiviert:

```sh
sudo kienzlefon-ai-reload --check
sudo kienzlefon-ai-reload
```

Ein Engine- oder Gerätewechsel benötigt den ausdrücklichen TTS-Umschaltbefehl:

```sh
sudo kienzlefon-ai-tts-apply --check
sudo kienzlefon-ai-tts-apply --apply
```

Der Umschalter prüft lokale Installationsvoraussetzungen und freie Plätze, zieht Kapazität zurück, stoppt Clients, wechselt/wärmt das Modell, bereitet Ansagen vor und stellt Bereitschaft her. Fehler lösen die geprüfte Rücksetzung aus. Muss dafür eine alte Kokoro-Gerätekonfiguration zurückkehren, wird der residente Dienst mit dieser Datei neu gestartet. Bei Rücksetzungskonflikten bleiben die Telefonclients gestoppt und die Kapazität zurückgezogen, bis der Zustand manuell geprüft ist. Remote-TTS-URLs sind für die Runtime möglich; der lokale Umschalter darf daran keine lokalen Ersatzdienste aktivieren. Eine reine Backendaktualisierung führt keinen automatischen Enginewechsel aus.

## G.722 und Hauptanlage

Die KI-Endpunkte des Backendinstallers erlauben ausschließlich G.722; AudioSocket bleibt `slin16` mit 16 kHz. Der passende Hauptanlagen-Generatorfix liegt getrennt als [Patch für den lokalen Kienzlefon-2.4.0-Stand](integration-v2.6/kienzlefon-2.4.0-g722.patch) vor. Seine Anwendbarkeit und drei gerenderte KI-Endpunkte wurden lokal geprüft. Andere Telefonendpunkte behalten ihre Codecauswahl. Der Patch wurde weder im Hauptprojekt noch auf dem Server angewendet.

## Prüfung und Aktivierung

Die [Prüfdokumentation](TESTS-v2.6.md) trennt lokale Prüfungen und übergebene Hardwarebelege. Die früheren Kokoro-/G.722-Ergebnisse gelten für den dort geprüften Serverstand. Eine neue Ubuntu-Installation, ein realer Umschalt-/Rollbackversuch und echte Anrufe mit dem integrierten Installerpaar 2.6 stehen als gesonderte Zielabnahme aus.

Normale Logs bleiben frei von Audio, Transkripten, Dialoginhalten und Tokens. Es erfolgt durch diese lokale Integration kein Upload von Hörproben oder Konfigurationskopien.
