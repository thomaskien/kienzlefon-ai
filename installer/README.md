# Installer

[Zur Projektübersicht](../README.md)

Die beiden jüngsten lokalen CUDA-/Backendinstaller sind ein versionsgleiches Paar:

- [CUDA-Serverinstaller 2.5.2](install-kienzlefon-ai_v2.5.2.sh)
- [Asterisk-/Dialoginstaller 2.5.2](kienzlefon-installer-asterisk-backend-v2.5.2.sh)

2.5.2 ist lokal geprüft. Sein Wartefeedback-Delta und der Aktivierungsstand stehen in den [Release Notes](../docs/RELEASE-NOTES-v2.5.2.md). Ein Backendupdate erfordert keinen erneuten KI-Installationslauf. Die vorherigen Installer bleiben mit ihren Versionsnummern erhalten; ihre Programmdateien wurden bei der Ordnerbereinigung nicht geändert.

Der eigenständige AMD-Zweig wird mit [AMD-Installer 1.0.2](../7900XTX/install-kienzlefon-ai-amd-v1.0.2.sh) fortgeführt; dazu gehört die [AMD-Anleitung](../docs/AMD-INSTALLATION-v1.0.2.md).

1.0.2 ergänzt ausschließlich Lizenz- und Änderungshinweise und ist lokal mit 71 Selbsttests geprüft. Die XTX-Hardwarebefunde stammen aus 1.0.1. [Delta und Prüfumfang](../docs/RELEASE-NOTES-AMD-v1.0.2.md).

Aus der Projektwurzel lassen sich Version und Hilfe ohne Installation anzeigen:

```bash
bash installer/install-kienzlefon-ai_v2.5.2.sh --version
bash installer/kienzlefon-installer-asterisk-backend-v2.5.2.sh --help
```

Der Ordner enthält auch historische Versionen. Die frühere Chat-Client-/Capacity-Entwicklung mit ihren gekoppelten Dateien liegt unter `archiv/entwicklung/`, weitere frühere Einzelmodule unter `installer/modules/`. Diese Stände sind nicht mit der aktuellen Runtime zu vermischen.

Der bisherige GitHub-Einzelinstaller 1.5 bleibt bytegleich unter [installer/historisch/](historisch/README.md) erhalten. Er dokumentiert einen früheren Entwicklungsstand.
