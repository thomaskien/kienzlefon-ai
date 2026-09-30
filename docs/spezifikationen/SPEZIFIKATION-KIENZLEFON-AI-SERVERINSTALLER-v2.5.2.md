# Kienzlefon AI CUDA-Serverinstaller 2.5.2

Stand: 30. September 2026. Referenz: `installer/install-kienzlefon-ai_v2.5.2.sh`.

Gegenüber `installer/install-kienzlefon-ai_v2.5.1.sh` ändern sich ausschließlich Versionsangaben. Alle KI-Verträge einschließlich Pyannote-Bind-Auswahl, Bestandsschutz und Installationsbestätigung aus `docs/spezifikationen/SPEZIFIKATION-KIENZLEFON-AI-SERVERINSTALLER-v2.5.1.md` bleiben unverändert. Die beiden Installer werden als versionsgleiches Paar fortgeführt; 2.5.1 bleibt erhalten.

Die Änderung der Standard-Warteansagen auf 5/11/17 Sekunden betrifft ausschließlich die Telefonieruntime. Für dieses Update den KI-Serverinstaller nicht ausführen. Auch der separat geführte AMD-Installer 1.0.1 bleibt unverändert.

Lokal bestanden: `bash -n`, `--version`, `--help`, vollständiger isolierter `--self-test` mit Warnungen als Fehler sowie bytegleicher Vergleich nach Versionsangleichung. Keine KI-Installation, Dienst-, Treiber-, GPU- oder Netzwerkänderung durchgeführt. Dies ist kein neuer Hardwaretest.
