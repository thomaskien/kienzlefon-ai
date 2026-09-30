# Installation und Update – Version 2.5.1

[Zur README](../README.md) · Stand: 28. September 2026

**2.5.1 ist noch nicht auf der Zielhardware abgenommen.** Die folgenden Installationsbefehle sind für eine bewusst freigegebene Testinstallation bzw. ein geplantes Wartungsfenster bestimmt. Das Erstellen dieser Dokumentation hat keine Installation ausgeführt.

## Den passenden Ablauf wählen

| Ausgangslage | Vorgehen |
|---|---|
| Neue KI-Serverumgebung | Voraussetzungen prüfen, anschließend KI-Serverinstaller mit den gewünschten Rollen ausführen |
| Neue Telefonie-Backendinstanz | Kompatibles Kienzlefon, Haupt-Asterisk, Piper und KI-Dienste vorbereiten; anschließend Backendinstaller |
| Funktionierende KI-Dienste und Backend 2.4.2 vorhanden | Für die 2.5.1-Funktion nur das Backend aktualisieren; KI-Serverinstaller nicht erneut ausführen |
| Backend 2.5.1 bereits installiert, nur Wartefeedback ändern | Vorhandene TOML bearbeiten und kontrollierten Reload verwenden |
| Vorhandenen Pyannote-Dienst gezielt an eine andere Adresse binden | KI-Installer mit `--action configure --role pyannote --pyannote-bind ADRESSE`; dies ändert Konfiguration und startet den Dienst neu |

Die Beispiele werden aus dem Projektwurzelverzeichnis ausgeführt; die beiden 2.5.1-Installer liegen unter `installer/`. `sudo` gilt für einen Benutzer mit sudo-Berechtigung; in einer Root-Shell wird es weggelassen.

## 1. Voraussetzungen vorbereiten

Für die KI-Rollen:

- Ubuntu x86_64 mit systemd; Referenz ist Ubuntu 24.04.4 LTS.
- Funktionierender NVIDIA-Treiber und kompatibles CUDA-Toolkit einschließlich `nvcc`. Beide werden geprüft, nicht installiert oder aktualisiert.
- Ausreichend GPU-/Arbeitsspeicher und Datenträgerplatz für Modelle, Build und Caches. Die Referenz hat 24 GB VRAM und 64 GB RAM; verbindliche Mindestwerte sind noch nicht ermittelt.
- Netzwerkzugriff für Paket-, Quellcode- und Modelldownloads während der Einrichtung.
- Vorhandener Piper-Dienst auf Port 8181 für den Telefonie-Fallback. Der KI-Serverinstaller meldet dessen Nichterreichbarkeit, richtet ihn aber nicht ein.

Für das Telefoniebackend zusätzlich:

- Eine dedizierte Asterisk-Backendinstanz. Der Installer ersetzt nach Sicherung deren `pjsip.conf` und `extensions.conf`; eine beliebige bestehende Telefonanlage ist kein geeignetes Installationsziel.
- Eine lokal installierte kompatible Kienzlefon-Umgebung: `/etc/kienzlefon/kienzlefon.toml`, `/opt/kienzlefon/venv/bin/python` sowie nutzbare Spool-/Ausgabepfade und die vom Installer geprüfte Commit-API.
- Haupt-Asterisk, drei SIP-Konten 8810–8812 mit eigenen Passwörtern sowie Admission-/Handoff-Unterstützung des Hauptsystems.
- Erreichbare ASR-, LLM-, Qwen- und Piper-Endpunkte.
- AudioSocket-Unterstützung für Typ `0x12`/`slin16`, `chan_audiosocket`, `res_audiosocket`, `codec_g722`, `Dial` und `UUID`. Eine Asterisk-Versionsnummer allein belegt diese Fähigkeiten nicht.
- G.722 auch am Haupt-Asterisk für einen breitbandigen Telefonpfad. RTP-Freigaben folgen der tatsächlich verwendeten Telefoniekonfiguration.

Die KI-Dienste dürfen auf demselben oder einem getrennten Host laufen. Nur der KI-Host benötigt für die KI-Rollen die GPU; am Backend müssen bei getrennten Hosts die URLs angepasst werden.

## 2. Dateien und Versionen prüfen

```bash
bash -n installer/install-kienzlefon-ai_v2.5.1.sh
bash -n installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh
bash installer/install-kienzlefon-ai_v2.5.1.sh --version
bash installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh --version
sha256sum installer/install-kienzlefon-ai_v2.5.1.sh installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh
```

Beide Versionsausgaben müssen Version `2.5.1` ausweisen. Die lokalen Referenzhashes stehen in den [Release Notes](RELEASE-NOTES-v2.5.1.md). Die Hashliste ist keine digitale Signatur. Unter macOS lautet das entsprechende Hashwerkzeug `shasum -a 256`; eine lokale Prüfung bedeutet keine macOS-Installationsunterstützung.

## 3. KI-Dienste neu installieren

Interaktive Auswahl von LLM, ASR und TTS mit anschließender ausdrücklicher Pyannote-Entscheidung:

```bash
sudo bash installer/install-kienzlefon-ai_v2.5.1.sh --role all
```

Der Installer erklärt zuerst, dass er KI-Komponenten installiert oder aktualisiert. Nur eine ausdrückliche Zustimmung setzt die Installation fort. Enter, Nein, ungültige Antworten oder EOF brechen vor Änderungen mit Exitcode 1 ab.

`all` umfasst `llm`, `asr` und `tts`. Pyannote wird separat mit Ja/Nein gewählt. Mit `--without-pyannote` lässt es sich ausdrücklich ausschließen:

```bash
sudo bash installer/install-kienzlefon-ai_v2.5.1.sh --role all --without-pyannote
```

Einzelne Rollen lassen sich ebenfalls installieren, beispielsweise:

```bash
sudo bash installer/install-kienzlefon-ai_v2.5.1.sh --role llm
```

Für jede ausgewählte CUDA-Rolle zeigt der Installer GPU-Index, UUID, Modell und VRAM an. Gespeichert wird die stabile UUID. Explizite Optionen sind `--llm-gpu`, `--asr-gpu`, `--tts-gpu` und `--pyannote-gpu`; sie akzeptieren Index oder UUID. Ein Toolkit lässt sich mit `--cuda-home /usr/local/cuda-13.0` auswählen, sofern dieser Pfad auf dem Zielsystem vorhanden und passend ist.

Nichtinteraktive Neuinstallation auf einem bewusst ausgewählten Ein-GPU-System, ohne Pyannote:

```bash
sudo bash installer/install-kienzlefon-ai_v2.5.1.sh \
  --role all --without-pyannote \
  --llm-gpu 0 --asr-gpu 0 --tts-gpu 0 \
  --non-interactive --confirm-ki-install
```

`--non-interactive` allein ist keine Installationsbestätigung. Auf einem bestehenden System übernimmt ein Installationsaufruf ohne `--role` die gespeicherten Rollen, Ports und gültigen UUIDs. Das ist weiterhin eine Installation/Aktualisierung, kein bloßer Versionswechsel.

Modelle und eingebettete KI-Payloads werden unverändert fortgeführt; 2.5.1 ergänzt gegenüber 2.5 die getrennte Pyannote-Bind-Konfiguration. Für das Wartefeedback-Update des Backends entfällt dieser gesamte KI-Installationsschritt.

## 4. Optional: Pyannote-Zugang

Für Pyannote werden ein Hugging-Face-Konto, die erforderliche Modellfreigabe für `pyannote/speaker-diarization-community-1` und ein persönlicher Read-Token benötigt. LLM, ASR und Qwen-TTS benötigen diesen Pyannote-Token nicht.

Interaktiv fragt der Installer ihn verdeckt ab:

```bash
sudo bash installer/install-kienzlefon-ai_v2.5.1.sh --role pyannote
```

Alternativ liest `--hf-token-file /geschuetzter/pfad/hf-token.txt` aus einer vorbereiteten geschützten Datei. Der Dateipfad ist ein Platzhalter. Den Tokenwert nicht in Befehle, Issues oder Dokumente schreiben. Die Serverablage ist `/etc/kienzlefon-ai/diarization.env`, Eigentümer `root:root`, Modus `0600`. Hinweise zu Geheimnissen und Sicherungen: [SECURITY.md](../SECURITY.md).

### Pyannote-Bind-Adresse ab 2.5.1

Die Auswahl erfolgt in dieser Reihenfolge: ausdrückliches `--pyannote-bind`, vorhandenes `DIARIZATION_HOST` aus der geschützten ENV, sonst `0.0.0.0`. Auch ein vorhandenes `127.0.0.1` bleibt erhalten. `--bind` und der gespeicherte allgemeine Bind-Wert überschreiben Pyannote nicht. Ungültige, leere oder unlesbare Bestandswerte führen zum Abbruch; IPv6-Bind-Adressen werden nicht unterstützt.

`0.0.0.0` bindet alle IPv4-Schnittstellen. Der Dienst hat keine HTTP-Authentifizierung. Den Zugriff im geschützten Netz auf vertrauenswürdige Rechner begrenzen; der Installer öffnet oder verändert keine Firewallregeln. Wer Pyannote bei Neuinstallation ausschließlich lokal betreiben möchte, gibt ausdrücklich `--pyannote-bind 127.0.0.1` an.

Eine beabsichtigte Umstellung eines vorhandenen Dienstes auf alle IPv4-Schnittstellen erfolgt nach Vorbereitung der Zugriffsbegrenzung beispielsweise mit:

```bash
sudo bash installer/install-kienzlefon-ai_v2.5.1.sh \
  --action configure --role pyannote --pyannote-bind 0.0.0.0
```

Das ist ein Systemeingriff: Der bestehende Konfigurationspfad einschließlich GPU-Drop-in und Zustandsdatei wird bearbeitet und Pyannote neu gestartet. Der Installer führt dabei keine Paket- oder Modellinstallation aus. Die ausdrückliche KI-Installationsbestätigung gilt für `install`, nicht für diese `configure`-Aktion. Ein vollständiger Installationslauf ist für die Bind-Umstellung nicht nötig. Bei Wildcardbindung prüft der Installer Health über localhost, sonst über die gewählte konkrete Adresse.

## 5. Backend neu installieren

Erst nach Bereitstellung der Hauptsystem-Anbindung, des lokalen Kienzlefon und der KI-Endpunkte:

```bash
sudo bash installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh
```

Interaktiv werden Hauptsystem, Backend-IP, SIP-Zugänge, KI-URLs und Runtimeoptionen erfasst. Für ein getrenntes KI-System können die in `--help` aufgeführten Optionen `--asr-url`, `--llm-url`, `--qwen-url` und `--piper-url` verwendet werden. SIP-Passwörter vorzugsweise verdeckt interaktiv eingeben; Klartext-CLI-Argumente können in Shellhistorie oder Prozesslisten sichtbar werden.

Vor der Installation erfolgt eine Sicherungs-/Installationsbestätigung. Die Runtime enthält den eingebetteten Praxis-Systemprompt; insbesondere Praxisabläufe und feste Aussagen vor Nutzung prüfen. Eine freigegebene angepasste Promptdatei kann mit `--system-prompt-file DATEI` eingelesen werden.

Bei aktivem Wartefeedback bereitet der Installer benötigte statische Ansagen über den vorhandenen Qwen-Dienst vor. Er installiert dafür kein Modell. Piper ersetzt nicht die Qwen-Vorbereitung dieser Ansagen.

## 6. Bestehendes Backend von 2.4.2 oder 2.5 auf 2.5.1 aktualisieren

1. Wartungsfenster mit freien Telefonplätzen vorsehen und die bestehende Runtimeversion feststellen.
2. Sichere Rückfallkopien der vorhandenen Konfiguration, Runtime, Clips und verwalteten Telefoniedateien verfügbar halten; diese Sicherungen enthalten Zugangsdaten.
3. Release Notes lesen und den vorhandenen Qwen-Dienst erreichbar halten, falls neue Clips benötigt werden.
4. Ausschließlich den Backendinstaller 2.5.1 auf der dafür vorgesehenen dedizierten Instanz starten und seine Sicherungs-/Installationsbestätigung prüfen.
5. Technische Bereitschaft sowie anschließend synthetische Testgespräche und Audioübergänge kontrollieren.

Die unterstützten Werte einer vorhandenen lesbaren `backend.toml` werden übernommen. Fehlende 2.5.1-Wartefeedbackwerte werden ergänzt; ein vorhandenes `[filler].enabled = false` und der Live-TTS-Seed bleiben erhalten. `streaming_asr` und `speculative_llm` werden auf `false` gesetzt. Beliebige zusätzliche TOML-Schlüssel oder manuelle systemd-Anpassungen sind nicht allgemein als updatefest zugesichert.

Gegenüber Backend 2.5 sind in 2.5.1 ausschließlich Versionsangaben geändert. Die Wartefeedback-Schlüssel wurden bereits in 2.5 eingeführt. Für eine reine Pyannote-Bind-Änderung ist kein Backend-Neuinstallationslauf erforderlich.

Der vollständige Backendinstaller kann auch Asterisk-Konfiguration und Dienste bearbeiten. Der spätere `kienzlefon-ai-reload` hat einen engeren Umfang und ersetzt keine erstmalige Versionsinstallation. Einfaches Ergänzen der neuen TOML-Schlüssel auf 2.4.2 installiert die 2.5.1-Funktion nicht.

## 7. Bereitschaft prüfen

Auf dem eingerichteten Backend sind diese Prüfungen lesend:

```bash
sudo bash installer/kienzlefon-installer-asterisk-backend-v2.5.1.sh --check
sudo kienzlefon-ai-reload --check
curl -fsS http://127.0.0.1:8300/health
sudo kienzlefon-ai-debug-console --snapshot
```

Freie Plätze, SIP-Registrierung, KI-Erreichbarkeit und erfolgreiches Health sind technische Voraussetzungen. Erst reale Testgespräche belegen den vollständigen Telefonpfad. Vorgehen und offene Fälle: [Tests und Validierungsstand](TESTS-v2.5.1.md).

## Rückweg und Deinstallation

Installer-Sicherungen und die Rücksicherung beim 2.5.1-Reload sind getrennte Mechanismen. Ein Rollback des vollständigen Versionsupdates muss zur tatsächlich angelegten Sicherung passen; die CLI bietet keinen allgemeinen Backendbefehl `--rollback`.

Der KI-Serverinstaller kennt `--action uninstall` für ausgewählte Rollen. Das verändert Dienste und Dateien und ist kein Diagnoseschritt. Ein vollständiger oder rollenweiser Uninstall auf der Zielhardware ist noch nicht abgenommen. Piper bleibt außerhalb der Verwaltung des KI-Serverinstallers.
