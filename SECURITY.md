# Sicherheit und Datenschutz

Stand: 30. September 2026 · CUDA-/Backendlinie 2.5.1 einschließlich lokaler Fortführung 2.5.2 und separater AMD-Zweig 1.0.2.

## Betriebsgrenzen

LLM und ASR-Gateway sind standardmäßig lokal gebunden, die Textschnittstelle an `127.0.0.1:8300`. Im CUDA-Installer lauscht Pyannote seit 2.5.1 ohne eigene Bestandskonfiguration auf `0.0.0.0:8183`, also allen IPv4-Schnittstellen. Diese Netzwerkbindung ist eine bewusste Betriebsentscheidung: In der eingesetzten Praxis müssen andere berechtigte Rechner den Diarisierungsdienst erreichen können. Der Projektbetreiber hat diesen Standard am 30. September 2026 ausdrücklich bestätigt; eine Umstellung auf reine Loopback-Bindung ist nicht vorgesehen. Der Diarisierungsdienst besitzt keine HTTP-Authentifizierung; sein Hugging-Face-Token schützt nicht den Zugriff auf die HTTP-API. Nur im geschützten Netz betreiben und den Zugriff auf vertrauenswürdige Rechner begrenzen. Der Installer ändert keine Firewallregeln.

Der separate AMD-Installer 1.0.2 verwendet für alle KI-APIs einschließlich Pyannote standardmäßig `127.0.0.1`. Eine andere Bind-Adresse benötigt zusätzlich `--allow-network`; eigene API-Authentifizierung oder TLS sind nicht enthalten. Bei der geprüften XTX-Migration blieben KI-/Piper-/Chat-APIs lokal, SIP nutzte ausschließlich die vorhandene geschützte Netzadresse.

Im CUDA-Installer bleibt eine vorhandene Pyannote-Adresse, auch `127.0.0.1`, erhalten. Dort dient `--pyannote-bind` für eine explizite Adresse; das allgemeine `--bind` steuert Pyannote nicht mehr. Telefonie und Verbindungen zu getrennten KI-Hosts gehören ebenfalls in ein geschütztes Netz. Die bereitgestellten HTTP-/WebSocket-Endpunkte sind nicht als frei erreichbare Internetdienste dokumentiert. Bind-Adressen, Zugriffsregeln und Telefonieports müssen zur tatsächlichen Installation passen.

Der Backendinstaller verwaltet eine dedizierte Asterisk-Instanz und ersetzt deren SIP-Konfiguration und Dialplan nach Sicherung. Das ist bei der Wahl des Installationsziels zu berücksichtigen.

## Geheimnisse und personenbezogene Daten

**Verbindliche Veröffentlichungsvorgabe: Der Hugging-Face-Token und sämtliche Hörproben dürfen keinesfalls hochgeladen werden.** Das gilt auch für synthetische Sprachproben, ausgewählte Warteansagen und Kopien in Archiven, eingebetteten Paketen oder der Git-Historie. Die lokalen Hörproben unter `assets/`, `lokal/hoerproben/` und in Test-/Messverzeichnissen bleiben privat. Ebenso ausgeschlossen sind `lokal/`, `archiv/`, `system-snapshots/` und sämtliche Laufverzeichnisse einschließlich `tests/runs/`. Die Beschreibung ihrer Eigenschaften und Messergebnisse in der Dokumentation enthält keine Freigabe der Audiodateien.

Folgende Inhalte dürfen nicht in Repositorys, Issues, Screenshots, Release-Assets oder normale Benchmarkdateien übernommen werden:

- Hugging-Face-Token, SIP-Passwörter, API-Schlüssel und andere Zugangsdaten.
- Installierte `backend.toml`, `last-reload.toml`, `diarization.env` und unbereinigte Sicherungen davon.
- Patientenangaben, Gesprächsaufnahmen, Transkripte, LLM-Inhalte und TTS-Eingabetexte.
- Ungeprüfte Spool-/Ausgabedaten, Supportpakete und lokale Testartefakte.

Die fachliche Auftragsausgabe des Kienzlefons speichert die erfassten Angaben bestimmungsgemäß. Inhaltsfreie Dienst- und Performancelogs bedeuten deshalb nicht, dass sämtliche Daten des Gesamtsystems flüchtig sind. Rechte und Aufbewahrung von Spool, Ausgabe und Sicherungen müssen gesondert geregelt werden.

Statische Warteansagen sind eine ausdrücklich vorgesehene Audioablage. Dafür nur allgemeine Ansagetexte verwenden. Synthetische Testläufe können vollständige Dialogartefakte in privaten Run-Verzeichnissen erzeugen; auch diese werden nicht automatisch als veröffentlichbare Testdaten behandelt.

## Tokenübergabe

Im CUDA-Installer den Token für die optionale Pyannote-Rolle verdeckt interaktiv oder über `--hf-token-file` übergeben. Der AMD-Installer verwendet für einen notwendigen Erstdownload eine root-private Datei über `--hf-token-file` und kopiert den Token nicht in den Dienstzustand. Kein Tokenwert als CLI-Argument und kein Shell-Debugging mit `set -x` bei geheimnishaltigen Vorgängen.

Bei der CUDA-Installation ist `/etc/kienzlefon-ai/diarization.env` für `root:root` mit Modus `0600` vorgesehen. Nur die Rechte prüfen, nicht den Inhalt ausgeben:

```bash
sudo stat -c '%U %G %a %n' /etc/kienzlefon-ai/diarization.env
```

Das Beispiel verwendet Ubuntu-`stat`. Erwartet: `root root 600` und der Dateipfad.

Bei Offenlegung den Token beim Anbieter widerrufen und ersetzen; das Entfernen einer Kopie allein macht einen bekannt gewordenen Token nicht wieder geheim. Betroffene Sicherungen und gegebenenfalls Git-Historie gesondert prüfen und kontrolliert bereinigen.

## Debugging und Berichte

Sensitive Debugausgabe ist standardmäßig aus. Dialogtexte sind nur bei ausdrücklich aktivierter Konfiguration und zusätzlichem Root-Aufruf der Livekonsole mit `--show-text` sichtbar. Für normale Fehlerberichte technische Diagnose ohne diese Option verwenden.

Öffentliche Fehlerberichte dürfen nur bereinigte technische Angaben und synthetische Beispiele enthalten. Eine vollständige Konfiguration ist wegen enthaltener Zugangsdaten kein geeigneter Anhang.

Vertrauliche Sicherheitsmeldungen bitte per E-Mail an **[tk@mampf.net](mailto:tk@mampf.net)** senden. Geheimnisse oder ausnutzbare vertrauliche Details nicht vorab in einem öffentlichen Issue ablegen. Es wird derzeit keine feste Reaktionszeit oder Supportfrist zugesagt.

## Persönlicher Token und private Arbeitsdateien

Der Projektbetreiber bestätigt am 30. September 2026: Der Hugging-Face-Token ist sein persönlicher Token und war niemals öffentlich. Die dokumentierte Kopie in einer lokalen `diarization.env` beziehungsweise einem privaten System-Snapshot ist daher kein nachgewiesener Veröffentlichungs- oder Kompromittierungsfall. Aus diesem lokalen Befund wird keine erforderliche Tokenrotation abgeleitet. Tokenwert, Konfigurationskopie und Snapshot bleiben vom Upload ausgeschlossen. Die oben genannte Regel zum Widerruf gilt für den Fall einer tatsächlichen Offenlegung.

Auch das XTX-Arbeitsverzeichnis enthält private SSH-/WireGuard-Unterlagen, Netzkonfiguration und ein zugriffsbeschränktes Migrationsarchiv mit Zugangsdaten. Das Verzeichnis `7900XTX/` darf nicht pauschal veröffentlicht werden. Benchmark- und Auditdateien benötigen trotz technischer Inhalte eine eigene Auswahl und Sichtung.

Die [aktualisierte Veröffentlichungscheckliste](docs/VEROEFFENTLICHUNG-2026-09-30-v1.9.md) sieht deshalb eine ausdrückliche Dateiauswahl und eine Prüfung des tatsächlichen Git-Inhalts vor. Das bloße Anlegen einer `.gitignore` würde bereits versionierte Geheimnisse, Hörproben oder frühere Commits nicht entfernen. Die abschließende Prüfung umfasst eingebettete Pakete und die zu veröffentlichende Historie; ein Token- oder Hörprobentreffer stoppt die Veröffentlichung.
